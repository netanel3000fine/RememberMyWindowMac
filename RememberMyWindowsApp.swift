import SwiftUI
import AppKit

@main
struct RememberMyWindowsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    init() {
        let langStr = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if langStr == "en" {
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        } else if langStr == "he" {
            UserDefaults.standard.set(["he"], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        Window("RememberMyWindows", id: "main") {
            ContentView()
                .environmentObject(WindowManager.shared)
                .tint(themeColor.color)
                .environment(\.locale, currentLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["main"])

        Settings {
            SettingsView()
                .environmentObject(WindowManager.shared)
                .environment(\.locale, currentLocale)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = DesktopToggleManager.shared
        WindowManager.shared.startTracking()
        
        // Determine if launched by user (active) or by system login item (inactive)
        // We must check this before changing activation policy.
        let isUserLaunch = NSApp.isActive
        
        // Start as background accessory (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupWindowObservers()

        // Capture the SwiftUI window as soon as it is created.
        // SwiftUI always opens the WindowGroup window at launch.
        DispatchQueue.main.async {
            if isUserLaunch {
                self.showMainWindow()
            } else {
                // Hide immediately so the window doesn't flash for background launches
                self.captureAndHideMainWindow()
            }
        }
    }

    private func setupWindowObservers() {
        // Automatically show/hide Dock icon based on window visibility
        let nc = NotificationCenter.default
        
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateActivationPolicy()
            }
        }
        
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            // Wait a tiny bit to see if another window is becoming key
            DispatchQueue.main.async {
                Task { @MainActor in
                    self?.updateActivationPolicy()
                }
            }
        }
    }

    private func updateActivationPolicy() {
        // Wait a tiny bit to ensure isVisible state is accurately updated by the system
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                // Only count windows that are visible, not panels/status items, 
                // and belong to our app's main UI
                window.isVisible && !(window is NSPanel) && self.isAppWindow(window)
            }
            
            if hasVisibleWindows {
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
            } else {
                if NSApp.activationPolicy() != .accessory {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func isAppWindow(_ w: NSWindow) -> Bool {
        // Match the main window or any potential settings/secondary windows
        return w.title == "RememberMyWindows" || 
               w.identifier?.rawValue.contains("main") == true || 
               w.title == "Settings"
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.stopTracking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Window management

    private func captureAndHideMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { isMainWindow($0) }) {
            // Hide immediately so the window doesn't flash at launch
            window.orderOut(nil)
        }
    }

    private func isMainWindow(_ w: NSWindow) -> Bool {
        w.title == "RememberMyWindows" || w.identifier?.rawValue.contains("main") == true
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "RememberMyWindows") {
                button.image = img
            } else {
                button.title = "RMW"
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Status Item Click

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || (NSEvent.modifierFlags.contains(.control))

        if isRightClick {
            // Right-click: show context menu
            setupMenu()
            statusItem?.menu = menu
            menu?.delegate = self
            statusItem?.button?.performClick(nil)
        } else {
            // Left-click: restore layout
            WindowManager.shared.restoreNow()
        }
    }

    // Called right after the menu closes so we can detach it
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    // MARK: - Menu

    private func setupMenu() {
        let menu = NSMenu()
        self.menu = menu
        menu.delegate = self

        menu.addItem(withTitle: lz("Open RememberMyWindows"), action: #selector(openMainWindow), keyEquivalent: "o")
        menu.addItem(NSMenuItem.separator())

        let saveTitle = lz(WindowManager.shared.willUpdateSession ? "Update Layout" : "Save Layout")
        let saveItem = menu.addItem(withTitle: saveTitle, action: #selector(saveLayout), keyEquivalent: "s")
        saveItem.isEnabled = !WindowManager.shared.isUpdateRestricted

        if let snap = WindowManager.shared.currentApplicableSnapshot {
            menu.addItem(withTitle: "\(lz("Restore")) '\(snap.displayName)'", action: #selector(restoreNow), keyEquivalent: "r")
            
            if !snap.records.isEmpty {
                let listViewItem = NSMenuItem()
                let hostingView = NSHostingView(rootView: MenuWindowListView(snapshot: snap).environment(\.locale, currentLocale))
                hostingView.layout()
                let size = hostingView.fittingSize
                // Fallback height if fittingSize evaluates to 0
                let viewHeight = size.height > 0 ? size.height : CGFloat(snap.records.count * 36 + 12)
                hostingView.frame = CGRect(x: 0, y: 0, width: 280, height: viewHeight)
                listViewItem.view = hostingView
                menu.addItem(listViewItem)
            }
        } else {
            menu.addItem(withTitle: lz("Restore Default Layout"), action: #selector(restoreNow), keyEquivalent: "r")
        }

        // Saved sessions submenu
        let savedMenu = NSMenu()
        let savedItem = NSMenuItem(title: lz("Saved Sessions"), action: nil, keyEquivalent: "")
        savedItem.submenu = savedMenu

        let savedSnapshots = WindowManager.shared.store.snapshots.values
            .filter { !$0.isAutoSave }
            .sorted { $0.updatedAt > $1.updatedAt }

        if savedSnapshots.isEmpty {
            savedMenu.addItem(withTitle: lz("No saved sessions"), action: nil, keyEquivalent: "")
        } else {
            for snap in savedSnapshots {
                let item = NSMenuItem(title: snap.displayName, action: #selector(restoreSpecificSnapshot(_:)), keyEquivalent: "")
                item.representedObject = snap.id.uuidString
                savedMenu.addItem(item)
            }
        }
        menu.addItem(savedItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: lz("Quit"), action: #selector(quitApp), keyEquivalent: "q")
    }

    // MARK: - Actions

    @objc private func openMainWindow() {
        showMainWindow()
    }

    func showMainWindow() {
        // Just ensure activation policy is correct; updateActivationPolicy will handle it too
        NSApp.setActivationPolicy(.regular)

        // Use the URL scheme to trigger SwiftUI's Window handling.
        // This is much more reliable than searching NSApp.windows manually if the window was destroyed (e.g. after restart/login item launch).
        if let url = URL(string: "remembermywindows://main") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func saveLayout() {
        WindowManager.shared.saveNow()
    }

    @objc private func restoreNow() {
        WindowManager.shared.restoreNow()
    }

    @objc private func restoreSelected() {
        if let key = WindowManager.shared.selectedSnapshotKey {
            WindowManager.shared.restore(key: key)
        } else {
            WindowManager.shared.restoreNow()
        }
    }

    @objc private func restoreSpecificSnapshot(_ sender: NSMenuItem) {
        if let idString = sender.representedObject as? String,
           let key = WindowManager.shared.store.snapshots.first(where: { $0.value.id.uuidString == idString })?.key {
            WindowManager.shared.restore(key: key)
        }
    }



    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}


