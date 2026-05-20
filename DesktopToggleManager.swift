import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class DesktopToggleManager: ObservableObject {
    static let shared = DesktopToggleManager()

    /// Whether the global Cmd+D shortcut is active.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enableDesktopToggleShortcut")
            if isEnabled { start() } else { stop() }
        }
    }

    /// Whether to automatically run window restoration when unhiding apps.
    @Published var restoreOnUnhide: Bool {
        didSet {
            UserDefaults.standard.set(restoreOnUnhide, forKey: "desktopToggleRestoreOnUnhide")
        }
    }

    /// Whether to focus the configured session frontmost app on unhide.
    @Published var focusConfiguredAppOnUnhide: Bool {
        didSet {
            UserDefaults.standard.set(focusConfiguredAppOnUnhide, forKey: "desktopToggleFocusConfiguredAppOnUnhide")
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var hasLoggedMissingPermissions = false

    // Toggle state
    private var isDesktopHidden = false
    private var previouslyVisibleApps: Set<String> = []
    private var previousFrontmostAppBundleID: String?
    private var finderHadWindows = false

    private init() {
        UserDefaults.standard.register(defaults: [
            "enableDesktopToggleShortcut": true,
            "desktopToggleFocusConfiguredAppOnUnhide": true
        ])
        self.isEnabled = UserDefaults.standard.bool(forKey: "enableDesktopToggleShortcut")
        self.restoreOnUnhide = UserDefaults.standard.bool(forKey: "desktopToggleRestoreOnUnhide")
        self.focusConfiguredAppOnUnhide = UserDefaults.standard.bool(forKey: "desktopToggleFocusConfiguredAppOnUnhide")
        if self.isEnabled { start() }
    }

    // MARK: - Tap lifecycle

    private func start() {
        guard eventTap == nil else { return }

        guard AXIsProcessTrusted() else {
            if !hasLoggedMissingPermissions {
                WindowManager.shared.log("Failed to enable Cmd+D. Missing Accessibility permissions. Waiting...", type: .system)
                hasLoggedMissingPermissions = true
            }
            scheduleRetry()
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags   = event.flags
                let isCmd   = flags.contains(.maskCommand)
                let noMods  = !flags.contains(.maskShift) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)

                // Cmd+D only
                guard keyCode == 2, isCmd, noMods else { return Unmanaged.passUnretained(event) }

                // Let Safari keep its native Cmd+D (bookmark shortcut).
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari" {
                    return Unmanaged.passUnretained(event)
                }

                DispatchQueue.main.async {
                    DesktopToggleManager.shared.toggleDesktop()
                }
                return nil  // consume the event
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            WindowManager.shared.log("Desktop toggle shortcut (Cmd+D) enabled", type: .system)
            hasLoggedMissingPermissions = false
        } else {
            if !hasLoggedMissingPermissions {
                WindowManager.shared.log("Failed to enable Cmd+D tap. Retrying...", type: .system)
                hasLoggedMissingPermissions = true
            }
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isEnabled == true { self?.start() }
            }
        }
    }

    private func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Toggle

    func toggleDesktop() {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        WindowManager.shared.log("Cmd+D pressed. Focused: \(frontApp) (\(frontID))", level: .verbose)

        if isDesktopHidden {
            WindowManager.shared.log("Cmd+D action: showing desktop apps", type: .system)
            showDesktop()
        } else {
            if isCurrentSpaceFullScreen() {
                WindowManager.shared.log("Cmd+D action: escaping full-screen app", type: .system)
            } else {
                WindowManager.shared.log("Cmd+D action: hiding desktop apps", type: .system)
            }
            hideDesktop()
        }
    }

    // MARK: - Hide

    private func hideDesktop() {
        let workspace = NSWorkspace.shared
        
        // Avoid overwriting state if already hidden (e.g. rapid double-press)
        guard !isDesktopHidden else {
            WindowManager.shared.log("Desktop already hidden, ensuring space switch", level: .verbose)
            if isCurrentSpaceFullScreen() {
                if let finder = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                    finder.activate(options: .activateIgnoringOtherApps)
                }
            }
            return
        }

        let frontmostApp = workspace.frontmostApplication
        previousFrontmostAppBundleID = frontmostApp?.bundleIdentifier

        // If already on a full-screen Space, we'll switch to the Desktop space
        // so the user actually sees it.
        if isCurrentSpaceFullScreen() {
            WindowManager.shared.log("Full-screen state detected — forcing space switch", type: .system)
            if let finder = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                // 1. Standard activation
                finder.activate(options: .activateIgnoringOtherApps)
                
                // 2. AppleScript activation (more forceful)
                _ = executeAppleScript("tell application \"Finder\" to activate")
                
                // 3. System Events focus
                _ = executeAppleScript("tell application \"System Events\" to tell process \"Finder\" to set frontmost to true")
            }
        }

        // Hide all regular windowed apps.
        var visibleApps: Set<String> = []
        var hiddenNames: [String] = []
        for app in workspace.runningApplications {
            guard app.bundleIdentifier != "com.apple.finder" else { continue }
            
            if !app.isHidden && app.activationPolicy == .regular {
                if let bundleID = app.bundleIdentifier { 
                    visibleApps.insert(bundleID)
                    hiddenNames.append(app.localizedName ?? bundleID)
                }
                app.hide()
            }
        }
        previouslyVisibleApps = visibleApps
        WindowManager.shared.log("Apps hidden: \(hiddenNames.isEmpty ? "None" : hiddenNames.joined(separator: ", "))", level: .verbose)

        // Collapse any open Finder windows.
        let checkScript = "tell application \"Finder\" to return (count of windows) > 0"
        if let res = executeAppleScript(checkScript), res.booleanValue {
            finderHadWindows = true
            WindowManager.shared.log("Collapsing Finder windows", level: .verbose)
            _ = executeAppleScript("tell application \"Finder\" to set collapsed of windows to true")
        } else {
            finderHadWindows = false
        }

        isDesktopHidden = true
    }

    // MARK: - Show

    private func showDesktop() {
        let workspace = NSWorkspace.shared
        var restoredNames: [String] = []

        // Unhide apps that were visible before.
        for app in workspace.runningApplications {
            guard app.bundleIdentifier != "com.apple.finder" else { continue }
            if let bundleID = app.bundleIdentifier, previouslyVisibleApps.contains(bundleID) {
                app.unhide()
                restoredNames.append(app.localizedName ?? bundleID)
            }
        }
        WindowManager.shared.log("Apps restored: \(restoredNames.isEmpty ? "None" : restoredNames.joined(separator: ", "))", level: .verbose)

        // Restore Finder windows.
        if finderHadWindows {
            WindowManager.shared.log("Restoring Finder windows", level: .verbose)
            _ = executeAppleScript("tell application \"Finder\" to set collapsed of windows to false")
        }

        // Restore the previously active app or the configured frontmost app.
        var targetBundleID = previousFrontmostAppBundleID
        
        if focusConfiguredAppOnUnhide {
            let fp = ScreenFingerprint.current()
            let store = WindowManager.shared.store
            let candidate: LayoutSnapshot?
            if let defaultID = store.defaultSnapshotIDs[fp.key],
               let snap = store.snapshots[defaultID], !snap.isAutoSave {
                candidate = snap
            } else {
                candidate = store.snapshots.values
                    .filter { $0.screenKey == fp.key && !$0.isAutoSave }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .first
            }
            if let configuredID = candidate?.foregroundBundleID {
                targetBundleID = configuredID
                WindowManager.shared.log("Cmd+D unhide: Found configured session front app '\(configuredID)'", level: .verbose)
            }
        }
        
        if let bundleID = targetBundleID,
           let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            WindowManager.shared.log("Re-activating: \(app.localizedName ?? bundleID)", level: .verbose)
            app.activate(options: .activateIgnoringOtherApps)
        }

        isDesktopHidden = false
        previouslyVisibleApps.removeAll()
        previousFrontmostAppBundleID = nil
        
        // Auto-restore layout if enabled.
        if restoreOnUnhide {
            WindowManager.shared.log("Cmd+D action: triggering layout restore", type: .system)
            WindowManager.shared.restoreNow()
        }
    }

    // MARK: - AppleScript helper

    private func executeAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if let err = error { print("AppleScript error: \(err)") }
            return result
        }
        return nil
    }

    // MARK: - Space detection

    /// Returns true when the current Space is a native full-screen Space,
    /// OR when the frontmost application is in full-screen mode.
    private func isCurrentSpaceFullScreen() -> Bool {
        // 1. Check if the frontmost app is in AX full-screen mode (most reliable)
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                for window in windows {
                    var isFullScreen: AnyObject?
                    if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &isFullScreen) == .success,
                       let fsNumber = isFullScreen as? NSNumber, fsNumber.boolValue {
                        WindowManager.shared.log("Full-screen detected via AX (Frontmost: \(frontApp.localizedName ?? frontApp.bundleIdentifier ?? "Unknown"))", level: .verbose)
                        return true
                    }
                }
            }
        }

        // 2. Fallback to CGSSpace private SPI (less reliable with multi-monitor)
        typealias CGSConnectionID = UInt32
        typealias CGSSpaceID      = UInt64

        guard
            let cgsBundleURL = Bundle(identifier: "com.apple.CoreGraphics")?.bundleURL
                ?? Bundle(path: "/System/Library/Frameworks/CoreGraphics.framework")?.bundleURL,
            let cgsHandle = dlopen(cgsBundleURL.appendingPathComponent("CoreGraphics").path, RTLD_NOLOAD | RTLD_LAZY)
        else { return false }
        defer { dlclose(cgsHandle) }

        typealias CGSMainConnectionFn = @convention(c) () -> CGSConnectionID
        typealias CGSGetActiveSpaceFn = @convention(c) (CGSConnectionID) -> CGSSpaceID
        typealias CGSSpaceGetTypeFn   = @convention(c) (CGSConnectionID, CGSSpaceID) -> Int32

        guard
            let mainConnSym  = dlsym(cgsHandle, "CGSMainConnectionID"),
            let activeSpSym  = dlsym(cgsHandle, "CGSGetActiveSpace"),
            let spaceTypeSym = dlsym(cgsHandle, "CGSSpaceGetType")
        else { return false }

        let getConn:       CGSMainConnectionFn = unsafeBitCast(mainConnSym,  to: CGSMainConnectionFn.self)
        let getActiveSpace: CGSGetActiveSpaceFn = unsafeBitCast(activeSpSym,  to: CGSGetActiveSpaceFn.self)
        let getSpaceType:   CGSSpaceGetTypeFn   = unsafeBitCast(spaceTypeSym, to: CGSSpaceGetTypeFn.self)

        let conn      = getConn()
        let spaceID   = getActiveSpace(conn)
        let spaceType = getSpaceType(conn, spaceID)
        
        let result = (spaceType == 1)
        if result {
            WindowManager.shared.log("Full-screen detected via CGSSpace (Type: \(spaceType))", level: .verbose)
        }
        return result
    }
}
