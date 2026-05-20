import AppKit
import Combine
import Foundation
import CoreLocation
import ServiceManagement

@MainActor
final class WindowManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = WindowManager()

    // MARK: - Published state
    @Published var store: LayoutStore = LayoutStore() {
        didSet { persist() }
    }
    @Published private(set) var currentFingerprint: ScreenFingerprint = .current()
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var recentEvents: [TrackingEvent] = []
    

    @Published var statusMessage: String = "Ready"
    @Published var selectedSnapshotKey: String? = nil
    /// Live-updating window list (never persisted). Updated by polling every 5 s.
    @Published private(set) var liveRecords: [WindowRecord] = []
    @Published var launchAtLogin: Bool = false {
        didSet {
            if launchAtLogin != (ServiceManagement.SMAppService.mainApp.status == .enabled) {
                updateLaunchAtLogin(enabled: launchAtLogin)
            }
        }
    }

    // Sentinel key used to identify the live layout selection (not stored in the snapshot dict).
    static let liveKey = "__live__"

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var windowObservers: [AnyObject] = []
    private var debounceTask: Task<Void, Never>?
    private let saveURL: URL

    // Throttle: only record a window move/resize after it's been still for 0.8 s
    private var pendingSaves: [WindowID: WindowRecord] = [:]
    private var flushTask: Task<Void, Never>?
    private var trackingTask: Task<Void, Never>?
    private var lastKnownWindows: [WindowID: (frame: CGRect, id: UUID)] = [:]
    /// Persists AX window info across captures. When an app loses AX visibility (not frontmost,
    /// or in its own full-screen Space), AX returns virtual-space coordinates that are useless.
    /// We cache the last-known accurate frames and reuse them in those cases.
    private var cachedAXWindowsByPID: [Int32: [AXWindowInfo]] = [:]
    private var lastCGWindowsByPID: [Int32: [CGWindowBriefInfo]] = [:]
    private let locationManager = CLLocationManager()
    @Published private(set) var currentLocation: CLLocation? = nil
    private var pendingSaveName: String? = nil
    private var pendingSaveUpdate = false
    private var pendingCapturedWindows: [WindowRecord]? = nil
    private var pendingFP: ScreenFingerprint? = nil
    private var isWaitingForLocationPermission: Bool = false
    private var isWaitingForLocationUpdate: Bool = false
    private var lastLocationTimestamp: Date? = nil
    /// Tracks window count across consecutive captures to detect sudden anomalous drops.
    private var lastWindowCount: Int = 0

    override private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RememberMyWindows", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("layouts.json")
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        launchAtLogin = ServiceManagement.SMAppService.mainApp.status == .enabled
        
        load()
    }

    // MARK: - Public API

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true

        // Observe screen changes (display connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Location updates removed per user request

        // Observe ALL existing and new windows via accessibility / polling
        observeRunningApps()

        // Also watch for new apps launching
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        // Track which app is frontmost — critical for diagnosing AX cache invalidations
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appFocusChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        startPolling()

        log("Monitoring started", level: .necessary, type: .system)
    }

    func stopTracking() {
        isTracking = false
        trackingTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        log("Monitoring stopped", level: .necessary, type: .system)
    }

    /// True if saving right now would update an existing session rather than creating a new one.
    var willUpdateSession: Bool {
        let fp = currentFingerprint
        return store.snapshots.values.contains { !$0.isAutoSave && $0.screenKey == fp.key }
    }

    var isUpdateRestricted: Bool {
        let fp = currentFingerprint
        
        // If the user has selected a specific saved session
        if let selectedKey = selectedSnapshotKey,
           selectedKey != WindowManager.liveKey,
           let selectedSnap = store.snapshots[selectedKey] {
            
            let snapFP = ScreenFingerprint.from(key: selectedSnap.screenKey)
            
            // 1. Physical Mismatch: If models match but UUIDs differ, restrict update
            let currentUUIDs = Set(fp.displays.compactMap { $0.uuid })
            let snapUUIDs = Set(snapFP.displays.compactMap { $0.uuid })
            if fp.modelKey == snapFP.modelKey && currentUUIDs != snapUUIDs {
                return true
            }

            // 2. Single-screen session while multiple screens connected
            if fp.displays.count >= 2 && snapFP.displays.count == 1 {
                return true
            }
        }
        
        return false
    }

    /// The snapshot that `restoreNow()` will restore based on current displays.
    var currentApplicableSnapshot: LayoutSnapshot? {
        let fp = currentFingerprint
        if let defaultID = store.defaultSnapshotIDs[fp.key],
           let snap = store.snapshots[defaultID], !snap.isAutoSave {
            return snap
        } else {
            return store.snapshots.values
                .filter { $0.screenKey == fp.key && !$0.isAutoSave }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
    }

    /// Manually save current window positions for this screen config.
    /// If a session already exists for the current screen configuration it is updated
    /// in-place and the diff (added / removed windows) is surfaced in the activity log.
    func saveNow(named snapshotName: String? = nil) {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            pendingSaveName = snapshotName
            isWaitingForLocationPermission = true
            locationManager.requestWhenInUseAuthorization()
            log("Waiting for location permission before saving...", level: .moderate, type: .system)
            statusMessage = "Waiting for location permission…"
            return
        }
        
        performSave(named: snapshotName)
    }

    private func performSave(named snapshotName: String?) {
        let fp = ScreenFingerprint.current()
        
        // Use previously captured windows if we are resuming from a location update
        let windows: [WindowRecord]
        if let pending = pendingCapturedWindows, let pFP = pendingFP, pFP.key == fp.key {
            windows = pending
            log("🔄 Resuming save with \(windows.count) preserved window records", level: .moderate, type: .system)
        } else {
            windows = captureAllWindows(for: fp)
        }
        
        // Include native full-screen windows so they can be restored as full screen
        let filteredWindows = windows
        
        // Ensure we have latest location if possible
        let status = locationManager.authorizationStatus
        let isAuthorized = status != .notDetermined && status != .denied && status != .restricted
        
        if isAuthorized && !isWaitingForLocationUpdate {
            // If location is nil OR older than 60 seconds, request a fresh one for manual save
            let isStale = currentLocation == nil || (lastLocationTimestamp?.timeIntervalSinceNow ?? -1000) < -60
            
            if isStale {
                pendingSaveName = snapshotName
                pendingSaveUpdate = (snapshotName == nil)
                pendingCapturedWindows = windows
                pendingFP = fp
                isWaitingForLocationUpdate = true
                
                // Note: We DON'T clear currentLocation here anymore to avoid UI flickering, 
                // but we wait for the fresh update below.
                
                locationManager.requestLocation()
                log("📍 Requesting fresh location before saving...", level: .moderate, type: .system)
                statusMessage = "Locating…"
                return
            }
        }
        
        // Clear pending state after we have location (or decided we don't need it)
        isWaitingForLocationUpdate = false
        pendingCapturedWindows = nil
        pendingFP = nil

        // ── Check for an existing saved session for this EXACT screen config ────
        let existingEntry = store.snapshots
            .filter { !$0.value.isAutoSave && $0.value.screenKey == fp.key }
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .first

        if let (existingKey, existingSnapshot) = existingEntry {
            // ── UPDATE existing session (Exact match) ───────────────────────────
            let oldIDs = Set(existingSnapshot.records.map { $0.windowID })
            let addedRecords = filteredWindows.filter { !oldIDs.contains($0.windowID) }
            
            var mergedRecords = existingSnapshot.records
            for newRecord in filteredWindows {
                if let index = mergedRecords.firstIndex(where: { $0.windowID == newRecord.windowID }) {
                    mergedRecords[index] = newRecord
                } else {
                    mergedRecords.append(newRecord)
                }
            }

            var updated = existingSnapshot
            updated.records  = mergedRecords
            updated.updatedAt = Date()
            
            // Also update location if we have a fresh one and the snapshot lacks it or it's old
            if let loc = currentLocation {
                updated.location = LocationInfo(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    address: updated.location?.address // Keep existing address for now, geocoder will update it
                )
            }
            
            store.snapshots[existingKey] = updated
            persist()

            // Trigger geocoder update for the updated session as well
            if let loc = currentLocation {
                updateSnapshotLocation(key: existingKey, location: loc)
            }

            // Build human-readable diff details
            let addedNames = addedRecords.map { $0.windowID.displayName }
            var diffLines: [String] = []
            for n in addedNames { diffLines.append("➕ \(n)") }

            let summary: String
            if addedNames.isEmpty {
                summary = "Positions updated"
            } else {
                summary = "\(addedNames.count) added, positions updated"
            }

            log("Session updated: '\(updated.name)' — \(summary)", level: .moderate,
                type: .manualSave,
                details: diffLines.isEmpty ? filteredWindows.map { formatWindowDetail(record: $0) } : diffLines)
            statusMessage = "Updated '\(updated.name)' · \(summary)"
            return
        }

        // ── Check if we have a session for the same hardware but DIFFERENT geometry ──
        let sameHardwareDiffGeometry = store.snapshots.values
            .filter { !$0.isAutoSave && ScreenFingerprint.from(key: $0.screenKey).hardwareKey == fp.hardwareKey }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first

        if let matchingHardware = sameHardwareDiffGeometry {
            log("Detected geometry change for '\(matchingHardware.name)'. Saving as a NEW session.", level: .moderate, type: .system)
        }

        // ── CREATE new session ───────────────────────────────────────────────────
        let newID = UUID().uuidString
        var snapshot = LayoutSnapshot(
            id: UUID(uuidString: newID) ?? UUID(),
            name: snapshotName ?? defaultName(for: fp),
            screenKey: fp.key,
            readableScreenKey: fp.readableName,
            records: [],
            createdAt: Date(),
            updatedAt: Date(),
            location: nil,
            isAutoSave: false
        )

        if let loc = currentLocation {
            snapshot.location = LocationInfo(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                address: nil
            )
            updateSnapshotLocation(key: newID, location: loc)
        }
        filteredWindows.forEach { snapshot.upsert($0) }
        store.snapshots[newID] = snapshot
        persist()
        let details = filteredWindows.map { formatWindowDetail(record: $0) }
        log("Snapshot saved: \(snapshot.name)", level: .necessary, type: .manualSave, details: details)
        statusMessage = "Saved layout '\(snapshot.name)'"
    }

    /// Restore saved layout for the current screen config.
    /// Prefers the user-marked default; falls back to the most recent saved session.
    func restoreNow(animated: Bool? = nil) {
        let fp = ScreenFingerprint.current()
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
        guard let snapshot = candidate else {
            statusMessage = "No saved layout for current display config"
            return
        }
        let anim = animated ?? store.restoreAnimated
        restore(snapshot: snapshot, animated: anim)
    }

    /// Checks if a snapshot can be restored based on current screen configuration.
    /// Returns false if the snapshot requires external screens that are not currently connected.
    func canRestore(snapshot: LayoutSnapshot) -> Bool {
        // If the screen config matches exactly, it's always restorable
        if snapshot.screenKey == currentFingerprint.key {
            return true
        }

        let currentScreenNames = NSScreen.screens.map { $0.localizedName }
        
        // Find all screens used in the snapshot that are external
        let requiredExternalNames = Set(snapshot.records.compactMap { $0.screenName })
            .filter { name in
                let lower = name.lowercased()
                return !lower.contains("built-in") && !lower.contains("retina display")
            }

        for name in requiredExternalNames {
            if !currentScreenNames.contains(name) {
                // An external screen required by this snapshot is not detected
                return false
            }
        }

        return true
    }

    func restore(key: String, animated: Bool? = nil) {
        guard let snapshot = store.snapshots[key] else { return }
        
        if !canRestore(snapshot: snapshot) {
            log("Cannot restore: required external screens missing", level: .moderate, type: .system)
            statusMessage = "Restore failed: External screen not detected"
            return
        }

        let anim = animated ?? store.restoreAnimated
        restore(snapshot: snapshot, animated: anim)
    }

    @objc private func appFocusChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let name = app.localizedName ?? "Unknown App"
        // Focus changes can sometimes signal that an app has moved to a different Space,
        // which might invalidate our AX frame cache for that PID.
        log("🎯 Focus changed: \(name)", level: .verbose, type: .system)
    }



    /// Brings the app with the given bundle ID above all other windows.
    func bringAppToFront(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID || $0.localizedName == bundleID
        }) else {
            log("Bring to front: '\(bundleID)' not running", level: .moderate, type: .system)
            return
        }
        
        if app.isActive {
            log("'\(app.localizedName ?? bundleID)' is already in front, skipping activation", level: .verbose, type: .system)
            return
        }
        
        // 1. Try standard activation
        app.activate()
        
        // 2. Try Workspace openApplication (often more aggressive)
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
        
        log("Brought '\(app.localizedName ?? bundleID)' to front", level: .moderate, type: .system)
    }

    /// Sets the preferred app to bring to front for a specific layout.
    func setForegroundApp(key: String, bundleID: String) {
        store.snapshots[key]?.foregroundBundleID = bundleID
        persist()
        log("Set foreground app to '\(bundleID)' for session", level: .moderate, type: .system)
    }

    func deleteSnapshot(key: String) {
        if let snap = store.snapshots[key] {
            store.snapshots.removeValue(forKey: key)
            if store.defaultSnapshotIDs[snap.screenKey] == key {
                store.defaultSnapshotIDs.removeValue(forKey: snap.screenKey)
                // Don't automatically assign a new default; let the next auto-save create a fresh one if needed
            }
            if selectedSnapshotKey == key {
                selectedSnapshotKey = nil
            }
            persist()
            log("Session deleted: \(snap.name)", level: .moderate, type: .system)
        }
    }

    func removeAppFromSnapshot(key: String, windowID: WindowID) {
        if var snap = store.snapshots[key] {
            snap.records.removeAll { $0.windowID == windowID }
            store.snapshots[key] = snap
            persist()
            log("Removed '\(windowID.displayName)' from session: \(snap.name)", level: .moderate, type: .system)
        }
    }

    func renameSnapshot(key: String, newName: String) {
        store.snapshots[key]?.name = newName
        persist()
    }

    func makeDefault(key: String) {
        guard let snapshot = store.snapshots[key] else { return }
        store.defaultSnapshotIDs[snapshot.screenKey] = key
        persist()
    }

    func updateLocationAddress(key: String, newAddress: String) {
        store.snapshots[key]?.location = LocationInfo(
            latitude: store.snapshots[key]?.location?.latitude ?? 0,
            longitude: store.snapshots[key]?.location?.longitude ?? 0,
            address: newAddress
        )
        persist()
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        let service = ServiceManagement.SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            log("\(enabled ? "Enabled" : "Disabled") launch at login", level: .moderate, type: .system)
        } catch {
            log("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)", level: .moderate, type: .system)
            // Revert state if it failed
            Task { @MainActor in
                self.launchAtLogin = service.status == .enabled
            }
        }
    }

    // MARK: - Tracking internals

    private func observeRunningApps() {
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            observeApp(app)
        }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Brief delay so the app's windows appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.observeApp(app)
            
            if self.store.autoRestoreOnAppOpen {
                if let snapshot = self.currentApplicableSnapshot {
                    let targetID = app.bundleIdentifier ?? app.localizedName
                    if let targetID = targetID {
                        self.restore(snapshot: snapshot, animated: self.store.restoreAnimated, specificAppBundleID: targetID, showNotification: true)
                    }
                }
            }
        }
    }

    private func observeApp(_ app: NSRunningApplication) {
        guard let pid = Optional(app.processIdentifier), pid > 0 else { return }
        _ = AXUIElementCreateApplication(pid)

        // We can't enumerate AX windows from here without accessibility permission,
        // so instead we hook NSWindow notifications for windows in OUR process,
        // and use a polling approach for other processes via NSWorkspace/CGWindowList.
        // For our own process we use notification observers.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            attachWindowNotifications()
        }
        // External windows are captured via CGWindowList on demand.
    }

    private func attachWindowNotifications() {
        let nc = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification
        ]
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let win = note.object as? NSWindow else { return }
                    self?.windowDidChange(win)
                }
            }
            windowObservers.append(obs as AnyObject)
        }
    }

    private func windowDidChange(_ window: NSWindow) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let title = window.title
        let frame = window.frame
        let fp = ScreenFingerprint.current()
        let screenKey = fp.key
        
        // Find which screen this window is mostly on
        let midPoint = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(midPoint) } ?? NSScreen.screens.first { $0.frame.intersects(frame) }
        let screenName = screen?.localizedName ?? "Unknown Screen"
        let appName = ProcessInfo.processInfo.processName

        let wid = WindowID(appBundleID: bundleID, appName: appName, windowTitle: title, appWindowIndex: 0)
        let record = WindowRecord(
            windowID: wid,
            globalFrame: frame,
            screenKey: screenKey,
            screenFrame: screen?.frame,
            screenName: screenName,
            savedAt: Date()
        )

        pendingSaves[wid] = record

        // Debounce flush
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    private func flushPendingSaves() {
        pendingSaves.removeAll()
        let fp = ScreenFingerprint.current()
        let currentWindows = captureAllWindows(for: fp, silent: true)
        let newCount = currentWindows.count

        // Detect sudden anomalous window count drops (≥3 windows lost in one cycle).
        // Normal fluctuations are 0–1 as apps launch/quit. Large drops signal a filter regression.
        if lastWindowCount > 0 && lastWindowCount - newCount >= 3 {
            log("⚠️ Window count dropped: \(lastWindowCount) → \(newCount) — possible AX filter regression or Space switch", level: .moderate, type: .system)
        }
        lastWindowCount = newCount

        liveRecords = currentWindows
        log("Live layout updated (\(newCount) windows)", level: .verbose, type: .autoSave)
    }


    func clearEvents() {
        recentEvents.removeAll()
    }

    // MARK: - Screen Change
    
    private var screenChangeTask: Task<Void, Never>?
    private var pendingConnectedNames: Set<String> = []

    @objc private func screensChanged() {
        let oldFP = currentFingerprint
        let newFP = ScreenFingerprint.current()
        let newKey = newFP.key
        currentFingerprint = newFP

        if oldFP == newFP {
            log("🖥️ Display parameters changed (e.g. transparency), but physical configuration is identical. Ignoring.", level: .verbose, type: .system)
            return
        }

        log("🖥️ Display config changed → \(newFP.readableName) (\(newFP.displays.count) screen(s))", level: .moderate, type: .system)

        let hasSavedSession = store.snapshots.values.contains { $0.screenKey == newKey && !$0.isAutoSave }

        // Detect added / removed displays
        let oldScreens = Set(oldFP.displays.map { $0.screenNumber })
        let newScreens = Set(newFP.displays.map { $0.screenNumber })
        let addedScreens   = newScreens.subtracting(oldScreens)
        let removedScreens = oldScreens.subtracting(newScreens)

        if !removedScreens.isEmpty {
            // Display removal invalidates all cached AX frames — positions shift unpredictably
            log("⚠️ Display removed — clearing AX cache to prevent ghost windows", level: .moderate, type: .system)
            cachedAXWindowsByPID.removeAll()
            lastCGWindowsByPID.removeAll()
        }


        let connectedScreenNames = addedScreens.compactMap { num in
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int) == num }?.localizedName
        }
        
        for name in connectedScreenNames {
            if name != "Unknown Screen" && !name.isEmpty {
                pendingConnectedNames.insert(name)
            }
        }
        
        // Even if we don't know the name yet, remember that a screen was added
        let hasAnyAddedScreens = !addedScreens.isEmpty

        if store.autoRestoreEnabled && hasSavedSession {
            screenChangeTask?.cancel()
            screenChangeTask = Task { @MainActor [weak self] in
                // Wait 1.0 second for the display connection storm to settle
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self = self else { return }

                // Show initial "Connected" notification
                let names = Array(self.pendingConnectedNames)
                if !names.isEmpty {
                    let joinedNames = names.joined(separator: " & ")
                    self.showNotchNotification(title: "\(joinedNames) Connected", subtitle: "Restoring layout...")
                } else if hasAnyAddedScreens {
                    self.showNotchNotification(title: "Display Connected", subtitle: "Restoring layout...")
                }

                // Start restoration
                self.restoreNow()
                
                // Clear the pending names
                self.pendingConnectedNames.removeAll()
            }
        }
    }

    // MARK: - Notch Notification
    
    private var notchWindow: NotchNotificationWindow?
    private func showNotchNotification(title: String, subtitle: String, isCompact: Bool = false) {
        let showNotch = UserDefaults.standard.object(forKey: "showNotchNotification") as? Bool ?? true
        guard showNotch else { return }

        if let window = notchWindow, window.isVisible, window.isCompact == isCompact {
            window.update(title: title, subtitle: subtitle)
        } else {
            notchWindow?.dismiss()
            let window = NotchNotificationWindow(title: title, subtitle: subtitle, isCompact: isCompact)
            notchWindow = window
            window.show()
        }
    }

    // MARK: - Capture

    private func captureAllWindows(for fp: ScreenFingerprint, silent: Bool = false) -> [WindowRecord] {
        var records: [WindowRecord] = []
        let screens = NSScreen.screens
        let primaryScreenHeight = screens.first?.frame.height ?? 0

        // Use .optionAll so we capture windows on ALL Spaces (including full-screen spaces).
        // .excludeDesktopElements removes dock, menu bar wallpaper panels, etc.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        // Map of PID to NSRunningApplication for quick lookup.
        let runningApps = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { _, new in new }
        )

        // Build the set of valid CG-coordinate screen rects (top-left origin) so we can
        // distinguish real AX positions from virtual-Space coordinates.
        let primaryH = screens.first?.frame.height ?? 0
        let screenCGRects: [CGRect] = screens.map { s in
            // Convert AppKit frame (bottom-left origin) → CG frame (top-left origin)
            CGRect(x: s.frame.minX, y: primaryH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }

        // Build the set of current CG window geometries per PID for Zero-IPC idle optimization
        var cgWindowsByPID: [Int32: [CGWindowBriefInfo]] = [:]
        for entry in windowList {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let app = runningApps[pid],
                  app.activationPolicy == .regular else { continue }

            guard let windowID = entry[kCGWindowNumber as String] as? UInt32,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  let windowLayer = entry[kCGWindowLayer as String] as? Int,
                  windowLayer == 0 else { continue }

            guard w > 50, h > 50 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.01 else { continue }

            let frame = CGRect(x: x, y: y, width: w, height: h)
            cgWindowsByPID[pid, default: []].append(CGWindowBriefInfo(windowID: windowID, bounds: frame))
        }

        // Retrieve true window frames and full-screen status directly from the accessibility tree.
        // This is used to filter out system ghost windows and accurately identify full-screen windows.
        let axWindowsByPID = getValidAXWindows(runningApps: runningApps, screenCGRects: screenCGRects, cgWindowsByPID: cgWindowsByPID)

        struct RawEntry {
            let entry: [String: Any]
            let pid: Int32
            let isOnScreen: Bool
            let area: CGFloat
            let zOrder: Int        // position in CGWindowList (front = lower index)
            let isAXFullScreen: Bool
            let frame: CGRect
            let matchedAXFrameIndex: Int // index into axWindowsByPID[pid]; -1 if no AX data
        }

        var groupedEntries: [Int32: [RawEntry]] = [:]
        var ghostCountByApp:  [Int32: Int] = [:]
        var zOrder = 0

        for entry in windowList {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let app = runningApps[pid],
                  app.activationPolicy == .regular else { zOrder += 1; continue }

            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  let windowLayer = entry[kCGWindowLayer as String] as? Int,
                  windowLayer == 0 else { zOrder += 1; continue }

            guard w > 50, h > 50 else { zOrder += 1; continue }

            // Filter out completely transparent ghost windows
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.01 else { zOrder += 1; continue }

            let isOnScreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            let title = entry[kCGWindowName as String] as? String ?? ""
            let cgFrame = CGRect(x: x, y: y, width: w, height: h)
            var isAXFullScreen = false

            // --- Pre-filter obvious ghost windows ---
            // Only drop clearly-impossible sizes; real full-screen windows (even untitled) must survive.
            if !isOnScreen && title.isEmpty {
                if (w == 64 && h == 64) || (w == 500 && h == 500) || h < 70 {
                    zOrder += 1; continue
                }
            }

            // --- AX Frame Matching ---
            if let axWins = axWindowsByPID[pid] {
                var matchedIdx = -1

                for (i, aw) in axWins.enumerated() {
                    // x/w: 5px tolerance (CG and AX align closely for normal windows;
                    //   the old 10px was causing ghost windows like 1400x718 to match 1408x718)
                    // y/h: 35px tolerance (full-screen AX frames include the hidden menu bar, +~29px)
                    let xMatch = abs(aw.frame.origin.x - cgFrame.origin.x) < 5
                    let yMatch = abs(aw.frame.origin.y - cgFrame.origin.y) < 35
                    let wMatch = abs(aw.frame.width - cgFrame.width) < 5
                    let hMatch = abs(aw.frame.height - cgFrame.height) < 35

                    if xMatch && yMatch && wMatch && hMatch {
                        matchedIdx = i
                        isAXFullScreen = aw.isFullScreen
                        break
                    }
                }

                if matchedIdx == -1 {
                    // Window not in AX tree → ghost.
                    ghostCountByApp[pid, default: 0] += 1
                    zOrder += 1; continue
                }

                let raw = RawEntry(entry: entry, pid: pid, isOnScreen: isOnScreen,
                                   area: w * h, zOrder: zOrder, isAXFullScreen: isAXFullScreen,
                                   frame: cgFrame, matchedAXFrameIndex: matchedIdx)
                groupedEntries[pid, default: []].append(raw)
            } else {
                // No AX data — deduplication will handle this app.
                let raw = RawEntry(entry: entry, pid: pid, isOnScreen: isOnScreen,
                                   area: w * h, zOrder: zOrder, isAXFullScreen: false,
                                   frame: cgFrame, matchedAXFrameIndex: -1)
                groupedEntries[pid, default: []].append(raw)
            }
            zOrder += 1
        }

        // Log any apps where we silently dropped ghost windows
        for (pid, count) in ghostCountByApp {
            let name = runningApps[pid]?.localizedName ?? "pid\(pid)"
            _ = (count, name) // ghost drops are normal operation; only log if anomalously high
        }
        
        // --- Heuristic Deduplication for non-AX Apps ---
        var selectedEntries: [RawEntry] = []

        for (_, entries) in groupedEntries {
            let pid = entries.first!.pid

            if axWindowsByPID[pid] != nil {
                // AX data present. Each CGWindow was matched to a specific AX frame index.
                // Group by that index and keep only the OLDEST window per AX frame
                // (ghosts are always newer — higher kCGWindowNumber — than the real window).
                var bestPerAXFrame: [Int: RawEntry] = [:]
                for e in entries {
                    let idx = e.matchedAXFrameIndex
                    if let existing = bestPerAXFrame[idx] {
                        let existNum = existing.entry[kCGWindowNumber as String] as? Int ?? Int.max
                        let newNum   = e.entry[kCGWindowNumber as String] as? Int ?? Int.max
                        if newNum < existNum { bestPerAXFrame[idx] = e }
                    } else {
                        bestPerAXFrame[idx] = e
                    }
                }
                let kept = bestPerAXFrame.values.sorted { $0.zOrder < $1.zOrder }
                // Duplicate drops are normal ghost-filter operation — no log needed
                selectedEntries.append(contentsOf: kept)
                continue
            }

            let onScreen = entries.filter { $0.isOnScreen }

            if !onScreen.isEmpty {
                // App has on-screen windows — off-screen ones are macOS ghosts. Drop them silently.
                selectedEntries.append(contentsOf: onScreen)
            } else {
                let offScreen = entries.filter { !$0.isOnScreen }
                if offScreen.isEmpty { continue }

                if offScreen.count == 1 {
                    selectedEntries.append(offScreen[0])
                } else {
                    // Multiple off-screen windows — pick the oldest (real windows are created first).
                    let sorted = offScreen.sorted { a, b in
                        let numA = a.entry[kCGWindowNumber as String] as? Int ?? Int.max
                        let numB = b.entry[kCGWindowNumber as String] as? Int ?? Int.max
                        return numA < numB
                    }
                    let winner = sorted[0]
                    selectedEntries.append(winner)
                }
            }
        }
        
        // Sort selected entries back to original zOrder
        selectedEntries.sort { $0.zOrder < $1.zOrder }

        // ── Convert raw entries → WindowRecords ────────────────────────────────
        var appWindowCounts: [Int32: Int] = [:]
        var currentZIndex = 0

        for raw in selectedEntries {
            guard let app = runningApps[raw.pid],
                  let bounds = raw.entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat else { continue }

            let appName  = app.localizedName ?? (raw.entry[kCGWindowOwnerName as String] as? String) ?? "Unknown"
            let bundleID = app.bundleIdentifier ?? appName
            let title    = raw.entry[kCGWindowName as String] as? String ?? ""

            // AppKit coords: (bottom-left origin)
            let appKitFrame = CGRect(x: x, y: primaryScreenHeight - y - h, width: w, height: h)

            // Find which screen this window primarily lives on
            let screen = screens.max(by: { s1, s2 in
                let area1 = s1.frame.intersection(appKitFrame).area
                let area2 = s2.frame.intersection(appKitFrame).area
                return area1 < area2
            })

            let index = appWindowCounts[raw.pid, default: 0]
            appWindowCounts[raw.pid] = index + 1

            let wid = WindowID(appBundleID: bundleID, appName: appName, windowTitle: title, appWindowIndex: index)
            let recordID = self.lastKnownWindows[wid]?.id ?? UUID()

            var record = WindowRecord(
                id: recordID,
                windowID: wid,
                globalFrame: appKitFrame,
                screenKey: fp.key,
                screenFrame: screen?.frame,
                screenName: screen?.localizedName ?? "Unknown Screen",
                savedAt: Date(),
                zIndex: currentZIndex
            )

            // Mark windows that are in native macOS full-screen mode.
            if raw.isAXFullScreen {
                record.isNativeFullScreen = true
                record.isFullScreenMode = true
            } else if let s = screen {
                let matchesFrame = abs(appKitFrame.width - s.frame.width) < 2 && abs(appKitFrame.height - s.frame.height) < 2

                if matchesFrame {
                    // Perfectly matches the full physical screen frame (e.g. YouTube PWA full-screen).
                    record.isFullScreenMode = true
                } else if !raw.isOnScreen {
                    // Check the native full-screen "parked" signature against every connected screen.
                    // When a full-screen app is in its own Space, its CG window sits at the screen's
                    // top-left corner (or 29px below for the primary display's menu bar).
                    // This works for both built-in (x=0, y≈29) and external monitors (x=-588, y≈-1440).
                    let isParkedFullScreen = screens.contains { sc in
                        let scCGMinX = sc.frame.minX
                        let scCGMinY = primaryScreenHeight - sc.frame.maxY
                        let xOK = abs(raw.frame.origin.x - scCGMinX) < 5
                        let wOK = abs(raw.frame.width - sc.frame.width) < 5
                        let yAtTop        = abs(raw.frame.origin.y - scCGMinY) < 10
                        let yBelowMenuBar = abs(raw.frame.origin.y - scCGMinY - 29) < 10
                        return xOK && wOK && (yAtTop || yBelowMenuBar)
                    }
                    if isParkedFullScreen {
                        record.isNativeFullScreen = true
                        record.isFullScreenMode = true
                    }
                }
            }

            records.append(record)
            currentZIndex += 1
        }

        if !silent {
            log("Scanned \(records.count) active windows via CGWindowList", level: .verbose)
        }
        return records
    }

    struct AXWindowInfo {
        let frame: CGRect
        let isFullScreen: Bool
    }

    struct CGWindowBriefInfo: Equatable {
        let windowID: UInt32
        let bounds: CGRect
    }

    /// Retrieves all valid window frames and their full-screen status directly from the Accessibility API.
    /// Results are cached per-PID. When AX returns empty or virtual-space coordinates (app not frontmost),
    /// the last known good cache is used instead to guarantee frame matching still works.
    private func getValidAXWindows(
        runningApps: [Int32: NSRunningApplication],
        screenCGRects: [CGRect],
        cgWindowsByPID: [Int32: [CGWindowBriefInfo]]
    ) -> [Int32: [AXWindowInfo]] {
        var result: [Int32: [AXWindowInfo]] = [:]
        
        // Prune cache for apps that are no longer running
        let activePIDs = Set(runningApps.keys)
        let stalePIDs = cachedAXWindowsByPID.keys.filter { !activePIDs.contains($0) }
        stalePIDs.forEach { cachedAXWindowsByPID.removeValue(forKey: $0) }
        let staleCGPIDs = lastCGWindowsByPID.keys.filter { !activePIDs.contains($0) }
        staleCGPIDs.forEach { lastCGWindowsByPID.removeValue(forKey: $0) }

        for (pid, app) in runningApps {
            guard app.activationPolicy == .regular else { continue }
            
            // Finder's AX tree only exposes the desktop background pseudo-window (e.g. 2560x2372),
            // not real folder windows. Including it would cause every Finder CGWindow to fail
            // frame-matching and be discarded as a ghost. Finder is handled by heuristic deduplication.
            if app.bundleIdentifier == "com.apple.finder" { continue }

            // Zero-IPC Idle Optimization: Skip AX query if the app has no active CG windows
            // or if window IDs and bounds have not changed since the last check.
            guard let currentCGWindows = cgWindowsByPID[pid], !currentCGWindows.isEmpty else {
                lastCGWindowsByPID.removeValue(forKey: pid)
                cachedAXWindowsByPID.removeValue(forKey: pid)
                continue
            }

            if let lastCGWindows = lastCGWindowsByPID[pid],
               lastCGWindows == currentCGWindows,
               let cachedAX = cachedAXWindowsByPID[pid] {
                // Geometry is completely identical. Safe to skip AX IPC queries and reuse cache!
                result[pid] = cachedAX
                continue
            }

            let axApp = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            var wins: [AXUIElement] = []
            
            // Try standard windows attribute
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let foundWins = windowsRef as? [AXUIElement] {
                wins = foundWins
            }
            
            // If empty, try children attribute (common fallback for non-standard apps)
            if wins.isEmpty {
                if AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &windowsRef) == .success,
                   let children = windowsRef as? [AXUIElement] {
                    wins = children.filter { child in
                        var roleRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                           let role = roleRef as? String {
                            if role == kAXWindowRole { return true }
                            var subroleRef: CFTypeRef?
                            if AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                               let subrole = subroleRef as? String {
                                return subrole == kAXStandardWindowSubrole ||
                                       subrole == kAXFloatingWindowSubrole ||
                                       subrole == kAXDialogSubrole
                            }
                        }
                        return false
                    }
                }
            }

            var axWins: [AXWindowInfo] = []
            for win in wins {
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
                
                var pos = CGPoint.zero
                var size = CGSize.zero
                if let posVal = posRef as! AXValue?, AXValueGetValue(posVal, .cgPoint, &pos) {}
                if let sizeVal = sizeRef as! AXValue?, AXValueGetValue(sizeVal, .cgSize, &size) {}
                
                var fsRef: CFTypeRef?
                var isFullScreen = false
                if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fsRef) == .success,
                   let fsVal = fsRef as? Bool {
                    isFullScreen = fsVal
                }
                
                // Only accept windows whose origin lands within a real connected screen (in CG coords).
                // When an app is not frontmost and in its own full-screen Space, AX reports the window
                // at the virtual Space position, which is far outside all physical screen bounds.
                // Example: Antigravity on Dell full-screen → AX reports (-588, -1440) when not frontmost,
                // but the Dell's CG rect is (-588, -508) to (1972, 932). The y=-1440 is out of all screens.
                let windowCGOrigin = CGPoint(x: pos.x, y: pos.y)
                let isOnAnyScreen = screenCGRects.contains { rect in
                    let expanded = rect.insetBy(dx: -50, dy: -50)
                    return expanded.contains(windowCGOrigin)
                }
                // Ignore tiny auxiliary windows (toolbars, panels < 50×50).
                // These match no CGWindow (which also has a >50×50 guard) and would pollute the cache,
                // causing real full-screen windows to fail frame-matching on the next capture cycle.
                let isSizeable = size.width > 50 && size.height > 50
                if isOnAnyScreen && isSizeable {
                    axWins.append(AXWindowInfo(frame: CGRect(origin: pos, size: size), isFullScreen: isFullScreen))
                }
            }
            
            if !axWins.isEmpty {
                // Fresh AX data from an on-screen position — update cache.
                let wasStale = cachedAXWindowsByPID[pid] == nil
                let appLabel = app.localizedName ?? "pid\(pid)"
                let fsSuffix = axWins.contains(where: { $0.isFullScreen }) ? " [fullscreen]" : ""
                if wasStale {
                    log("💾 AX cache POPULATED for \(appLabel): \(axWins.count) frame(s)\(fsSuffix)", level: .verbose, type: .system)
                }
                cachedAXWindowsByPID[pid] = axWins
                lastCGWindowsByPID[pid] = currentCGWindows
                result[pid] = axWins
            } else if let cached = cachedAXWindowsByPID[pid] {
                // AX returned nothing useful (app is backgrounded / in its own full-screen Space).
                // Use the last known good frames so ghost-window filtering still works correctly.
                lastCGWindowsByPID[pid] = currentCGWindows
                result[pid] = cached
            } else {
                // No fresh data and no cache — deduplication will handle it.
                // (Normal for apps that haven't been focused since launch.)
            }
        }
        return result
    }

    // MARK: - Permission Check

    /// Returns true if the app currently has Accessibility permission.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission (shows system dialog once).
    func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Restore

    private func restore(snapshot: LayoutSnapshot, animated: Bool, specificAppBundleID: String? = nil, showNotification: Bool = true) {
        let fp = ScreenFingerprint.current()

        if !hasAccessibilityPermission {
            log("⚠️ Accessibility permission not granted — grant it in System Settings › Privacy › Accessibility then rebuild/relaunch", level: .necessary)
            if specificAppBundleID == nil {
                statusMessage = "Accessibility permission required"
                requestAccessibilityPermission()
            }
            // Don't return — still attempt AppleScript fallback for each window
        }

        let primaryScreenH = NSScreen.screens.first?.frame.height ?? 0
        let ownProcessName = ProcessInfo.processInfo.processName  // e.g. "RememberMyWindows"

        let records: [WindowRecord]
        if let targetApp = specificAppBundleID {
            records = snapshot.records.filter { $0.windowID.appBundleID == targetApp || $0.windowID.appName == targetApp }
            if records.isEmpty { return }
            log("Starting auto-restoration for \(targetApp) (\(records.count) windows)", level: .necessary, type: .restore)
        } else {
            records = snapshot.records
            log("Starting restoration of \(records.count) windows for \(fp.readableName)", level: .necessary, type: .restore)
            statusMessage = "Restoring \(records.count) windows…"
        }

        let details = records.map { self.formatWindowDetail(record: $0) }

        Task {
            let screens = NSScreen.screens
            let primaryH = screens.first?.frame.height ?? 0
            let screenCGRects: [CGRect] = screens.map { s in
                CGRect(x: s.frame.minX, y: primaryH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
            }
            let runningApps = Dictionary(
                NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
                uniquingKeysWith: { _, new in new }
            )
            let axWindowsByPID = self.getValidAXWindows(runningApps: runningApps, screenCGRects: screenCGRects, cgWindowsByPID: [:])
            let fullScreenPIDs = Set(axWindowsByPID.compactMap { pid, wins in
                wins.contains(where: { $0.isFullScreen }) ? pid : nil
            })

            await withTaskGroup(of: Void.self) { group in
                for record in records {
                    let appName = record.windowID.appBundleID
                    
                    // Calculate the target frame once per window, respecting the "Behind Dock" setting
                    let target = self.calculateTargetFrame(for: record)

                    // ---------- Skip if app is not running ----------
                    if !runningApps.values.contains(where: { $0.bundleIdentifier == appName || $0.localizedName == appName }) {
                        self.log("⏭️ Skipping '\(appName)' — app is not running", level: .verbose, type: .restore)
                        continue
                    }

                    // ---------- Skip if app is currently in full-screen (and NOT intended to be) ----------
                    if let app = runningApps.values.first(where: { $0.bundleIdentifier == appName || $0.localizedName == appName }),
                       fullScreenPIDs.contains(app.processIdentifier),
                       !(record.isNativeFullScreen || record.isFullScreenMode) {
                        self.log("⏭️ Skipping '\(appName)' — currently in full-screen mode", level: .verbose, type: .restore)
                        continue
                    }

                    // ---------- Our own windows: use NSWindow directly ----------
                    if appName == ownProcessName {
                        group.addTask { @MainActor [weak self] in
                            if let win = NSApplication.shared.windows.first(where: { $0.title == record.windowID.windowTitle }) {
                                if animated {
                                    win.animator().setFrame(target, display: true)
                                } else {
                                    win.setFrame(target, display: true)
                                }
                                self?.log("✅ Own window '\(record.windowID.windowTitle)' restored", level: .verbose)
                            }
                        }
                        continue
                    }

                    // ---------- External apps: AX first, osascript fallback ----------
                    self.log("→ Queuing restore for '\(appName)'", level: .verbose)
                    let rec = record
                    let screenH = primaryScreenH
                    group.addTask { [weak self] in
                        let axOK = await self?.restoreViaAX(record: rec, targetFrame: target, primaryScreenH: screenH) ?? false
                        if !axOK {
                            await self?.log("⚠️ AX failed for '\(appName)', trying AppleScript...", level: .verbose, type: .system)
                            await self?.restoreViaOsascript(record: rec, targetFrame: target, primaryScreenH: screenH)
                        }
                    }
                }
            }

            // Finally, bring the user's preferred foreground app to the absolute front (if set)
            // We wait a brief moment to allow macOS window server to settle after the frame changes.
            if specificAppBundleID == nil, let targetBundleID = snapshot.foregroundBundleID {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
                self.bringAppToFront(bundleID: targetBundleID)
            }

            if specificAppBundleID == nil {
                self.log("Restoring layout for \(fp.readableName)", level: .necessary, type: .restore, details: details)
                self.statusMessage = "Restore complete"
            } else {
                self.log("Restored \(records.count) window(s) for \(specificAppBundleID!)", level: .necessary, type: .restore, details: details)
            }

            // Show notch notification after windows have settled
            if showNotification {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isCompact = specificAppBundleID != nil
                if isCompact {
                    let appName = records.first?.windowID.appName ?? specificAppBundleID ?? "App"
                    self.showNotchNotification(
                        title: "\(appName) \(lz("Restored"))",
                        subtitle: "",
                        isCompact: true
                    )
                } else {
                    self.showNotchNotification(
                        title: "Layout Restored",
                        subtitle: "\(snapshot.name) · \(snapshot.records.count) windows"
                    )
                }
            }
        }
    }

    // MARK: - AX restore (must be called from @MainActor context)

    private func restoreViaAX(record: WindowRecord, targetFrame: CGRect, primaryScreenH: CGFloat) async -> Bool {
        let appName = record.windowID.appBundleID

        // CG/AX coords: origin = top-left of primary screen
        let axX = targetFrame.origin.x
        let axY = primaryScreenH - targetFrame.origin.y - targetFrame.height  // AppKit → CG Y flip
        let axW = targetFrame.width
        let axH = targetFrame.height

        guard hasAccessibilityPermission else {
            log("AX ❌ no permission for '\(appName)' — will fall back to osascript", level: .verbose)
            return false
        }

        // Find the running app by its process name (kCGWindowOwnerName == localizedName)
        guard let app = NSWorkspace.shared.runningApplications.first(
            where: { $0.localizedName == appName || $0.bundleIdentifier == appName }
        ) else {
            log("AX ❌ '\(appName)' not running", level: .verbose)
            return false
        }

        // Try to activate the app (sometimes required for AX to work reliably)
        app.activate()
        
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        var wins: [AXUIElement] = []
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let foundWins = windowsRef as? [AXUIElement] {
            wins = foundWins
        }
        
        if wins.isEmpty {
            // Retry a few times with a small delay, as some apps take a moment to report windows after activation
            for _ in 1...3 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let foundWins = windowsRef as? [AXUIElement], !foundWins.isEmpty {
                    wins = foundWins
                    break
                }
            }
        }
        
        if wins.isEmpty {
            if AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &windowsRef) == .success,
               let children = windowsRef as? [AXUIElement] {
                wins = children.filter { child in
                    var roleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                       let role = roleRef as? String {
                        if role == kAXWindowRole { return true }
                        
                        // Check subroles for non-standard windows (common in media players)
                        var subroleRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                           let subrole = subroleRef as? String {
                            return subrole == kAXStandardWindowSubrole || 
                                   subrole == kAXFloatingWindowSubrole || 
                                   subrole == kAXDialogSubrole
                        }
                    }
                    return false
                }
            }
        }
        
        guard !wins.isEmpty else {
            log("AX ❌ '\(appName)' — no windows found via AX", level: .verbose)
            return false
        }

        // Match by title first; if no title, use appWindowIndex to pick the nth window.
        // This ensures multiple windows from the same app are restored correctly
        // even without Screen Recording permission (which is needed for window titles).
        let target: AXUIElement?
        if !record.windowID.windowTitle.isEmpty {
            // Match by title (exact then fuzzy)
            target = wins.first { w in
                var tv: CFTypeRef?
                guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tv) == .success,
                      let t = tv as? String else { return false }
                return t == record.windowID.windowTitle
            } ?? wins.first { w in
                var tv: CFTypeRef?
                guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tv) == .success,
                      let t = tv as? String else { return false }
                return t.contains(record.windowID.windowTitle) || record.windowID.windowTitle.contains(t)
            }
        } else {
            let idx = record.windowID.appWindowIndex
            target = idx < wins.count ? wins[idx] : wins.first
        }

        guard let win = target else {
            log("⚠️ Restore: '\(appName)' — no AX window found for title '\(record.windowID.windowTitle)'", level: .verbose, type: .restore)
            return false
        }

        if record.isNativeFullScreen || record.isFullScreenMode {
            // Move window to the target screen first so it enters full-screen on the right display
            var pos = CGPoint(x: axX, y: axY)
            if let v = AXValueCreate(.cgPoint, &pos) {
                _ = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
            }

            // Send AXFullScreen = true
            let fsErr = AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, kCFBooleanTrue)
            if fsErr == .success {
                log("✅ Restore: '\(appName)' → entering Full Screen", level: .verbose, type: .restore)
                return true
            } else if fsErr.rawValue == -25200 || fsErr.rawValue == -25205 {
                // kAXErrorIllegalArgument / kAXErrorActionUnsupported:
                // App doesn't expose AXFullScreen for writing (e.g. Stremio).
                // The window is already at the correct position/size — accept as done.
                log("ℹ️ Restore: '\(appName)' — programmatic full-screen not supported, window positioned instead", level: .verbose, type: .restore)
                return true
            } else {
                log("❌ Restore: '\(appName)' — AXFullScreen failed (AXError \(fsErr.rawValue))", level: .verbose, type: .restore)
                return false
            }
        }

        // Position must be set before size
        var pos = CGPoint(x: axX, y: axY)
        if let v = AXValueCreate(.cgPoint, &pos) {
            let e = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
            if e != .success { log("AX ⚠️ '\(appName)' set-position error \(e.rawValue)", level: .verbose) }
        }
        var sz = CGSize(width: axW, height: axH)
        if let v = AXValueCreate(.cgSize, &sz) {
            let e = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v)
            if e != .success { log("AX ⚠️ '\(appName)' set-size error \(e.rawValue)", level: .verbose) }
        }

        log("AX ✅ '\(appName)' → (\(Int(axX)), \(Int(axY))) \(Int(axW))×\(Int(axH))", level: .verbose)
        return true
    }

    // MARK: - osascript fallback (nonisolated — safe on any thread)

    nonisolated private func restoreViaOsascript(record: WindowRecord, targetFrame: CGRect, primaryScreenH: CGFloat) async {
        let appName = record.windowID.appBundleID
        let x       = Int(targetFrame.origin.x)
        let y       = Int(primaryScreenH - targetFrame.origin.y - targetFrame.height)
        let right   = x + Int(targetFrame.width)
        let bottom  = y + Int(targetFrame.height)
        let title   = record.windowID.windowTitle

        var script = ""
        
        // Window bounds setting part
        if title.isEmpty {
            script += """
            try
                tell application id "\(appName)"
                    set bounds of front window to {\(x), \(y), \(right), \(bottom)}
                end tell
            end try
            """
        } else {
            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            script += """
            try
                tell application id "\(appName)"
                    try
                        set bounds of window "\(safeTitle)" to {\(x), \(y), \(right), \(bottom)}
                    on error
                        set bounds of front window to {\(x), \(y), \(right), \(bottom)}
                    end try
                end tell
            end try
            """
        }

        // Full-screen part (System Events fallback)
        if record.isNativeFullScreen || record.isFullScreenMode {
            script += """
            
            tell application "System Events"
                try
                    set value of attribute "AXFullScreen" of (first window of (first process whose bundle identifier is "\(appName)")) to true
                end try
            end tell
            """
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run { [weak self] in
                if proc.terminationStatus == 0 {
                    self?.log("osascript ✅ '\(appName)' → (\(x), \(y)) \(right - x)×\(bottom - y)", level: .verbose)
                } else {
                    self?.log("osascript ❌ '\(appName)': \(output.isEmpty ? "unknown error" : output)", level: .verbose)
                }
            }
        } catch {
            await MainActor.run { [weak self] in
                self?.log("osascript ❌ could not launch for '\(appName)': \(error)", level: .verbose)
            }
        }
    }

    /// Calculates the final intended frame for a window based on user preferences.
    /// Returns a frame adjusted for the specific screen's visible area (clamped to avoid being hidden under the menu bar or dock).
    private func calculateTargetFrame(for record: WindowRecord) -> CGRect {
        let f = record.globalFrame
        
        // Find which screen this window primarily lives on
        guard let screen = NSScreen.screens.max(by: { $0.frame.intersection(f).area < $1.frame.intersection(f).area }) else {
            return f
        }
        
        let vf = screen.visibleFrame
        
        // Standard Clamp: Ensure window stays within visible bounds (on top of Dock and below Menu Bar)
        let targetY = max(f.origin.y, vf.minY)
        let targetX = max(f.origin.x, vf.minX)
        
        // Limit height/width so they don't push the window off the other side of the visible frame
        let targetMaxY = min(f.origin.y + f.height, vf.maxY)
        let targetMaxX = min(f.origin.x + f.width, vf.maxX)
        
        let finalW = max(50, targetMaxX - targetX)
        let finalH = max(50, targetMaxY - targetY)
        
        return CGRect(x: targetX, y: targetY, width: finalW, height: finalH)
    }

    private func startPolling() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            // Initial snapshot to avoid logging everything on start
            if let self = self {
                let fp = ScreenFingerprint.current()
                let records = self.captureAllWindows(for: fp, silent: true)
                for r in records {
                    self.lastKnownWindows[r.windowID] = (r.globalFrame, r.id)
                }
                if !records.isEmpty {
                    self.handleExternalChanges([:]) // Trigger a sync
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                // Always poll to keep liveRecords current.
                guard let self = self, isTracking else { continue }
                
                let fp = ScreenFingerprint.current()
                let currentRecords = self.captureAllWindows(for: fp, silent: true)
                
                var hasChanges = false
                if currentRecords.count != self.lastKnownWindows.count {
                    hasChanges = true
                } else {
                    for r in currentRecords {
                        if let last = self.lastKnownWindows[r.windowID] {
                            if abs(last.frame.origin.x - r.globalFrame.origin.x) > 2 ||
                               abs(last.frame.origin.y - r.globalFrame.origin.y) > 2 ||
                               abs(last.frame.width - r.globalFrame.width) > 2 ||
                               abs(last.frame.height - r.globalFrame.height) > 2 {
                                hasChanges = true
                                break
                            }
                        } else {
                            hasChanges = true
                            break
                        }
                    }
                }
                
                if hasChanges {
                    // Update cache with ONLY current windows to avoid accumulating stale IDs
                    var nextMap: [WindowID: (frame: CGRect, id: UUID)] = [:]
                    for r in currentRecords {
                        nextMap[r.windowID] = (r.globalFrame, r.id)
                    }
                    self.lastKnownWindows = nextMap
                    self.handleExternalChanges([:])
                }
            }
        }
    }

    private func handleExternalChanges(_: [WindowID: WindowRecord]) {
        // We now ignore the parameter and perform a full sync in flushPendingSaves
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }



    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            log("Persist error: \(error)", level: .necessary)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              var loaded = try? JSONDecoder().decode(LayoutStore.self, from: data) else { return }

        var migrated = false
        for (key, snap) in loaded.snapshots {
            if key == snap.screenKey {
                let newID = UUID().uuidString
                loaded.snapshots.removeValue(forKey: key)
                var updatedSnap = snap
                updatedSnap.id = UUID(uuidString: newID) ?? UUID()
                loaded.snapshots[newID] = updatedSnap
                if loaded.defaultSnapshotIDs[snap.screenKey] == nil {
                    loaded.defaultSnapshotIDs[snap.screenKey] = newID
                }
                migrated = true
            }
        }

        // Native full-screen windows are now supported again, so we no longer prune them here.

        // Purge old auto-save snapshots that were persisted by earlier app versions.
        // The live layout is now tracked via in-memory liveRecords and is never stored.
        var purged = false
        for (key, snap) in loaded.snapshots where snap.isAutoSave {
            loaded.snapshots.removeValue(forKey: key)
            if loaded.defaultSnapshotIDs[snap.screenKey] == key {
                loaded.defaultSnapshotIDs.removeValue(forKey: snap.screenKey)
            }
            purged = true
        }

        store = loaded
        pruneStore()
        if migrated || purged { persist() }
    }

    /// Removes 'ghost' records that no longer pass the filtering criteria (e.g. from accessory apps).
    private func pruneStore() {
        var changed = false
        for (snapKey, var snapshot) in store.snapshots {
            let originalCount = snapshot.records.count
            snapshot.records.removeAll { record in
                // Check if it's our own app
                if record.windowID.appBundleID == Bundle.main.bundleIdentifier ||
                   record.windowID.appName == ProcessInfo.processInfo.processName ||
                   record.windowID.appName == "RememberMyWindows" ||
                   record.windowID.appBundleID == "RememberMyWindows" {
                    return true
                }
                
                // Check if the app still exists and is 'regular'
                // We use the bundle ID if available, otherwise app name
                let appRef = record.windowID.appBundleID
                if let app = NSWorkspace.shared.runningApplications.first(where: { 
                    $0.bundleIdentifier == appRef || $0.localizedName == appRef 
                }) {
                    return app.activationPolicy != .regular
                }
                return false
            }
            if snapshot.records.count != originalCount {
                store.snapshots[snapKey] = snapshot
                changed = true
            }
        }
        if changed {
            persist()
            log("Pruned \(store.snapshots.values.reduce(0) { $0 + $1.records.count }) windows across all sessions", type: .system)
        }
    }

    // MARK: - Helpers

    private func defaultName(for fp: ScreenFingerprint) -> String {
        fp.readableName
    }

    func log(_ msg: String, level: LogLevel = .moderate, type: EventType = .system, details: [String]? = nil) {
        // Determine if we should record this log based on importance
        let currentLevelImportance: Int
        switch store.logLevel {
        case .necessary: currentLevelImportance = 0
        case .moderate:  currentLevelImportance = 1
        case .verbose:   currentLevelImportance = 2
        }

        let msgImportance: Int
        switch level {
        case .necessary: msgImportance = 0
        case .moderate:  msgImportance = 1
        case .verbose:   msgImportance = 2
        }

        if msgImportance > currentLevelImportance {
            return
        }

        let event = TrackingEvent(type: type, message: msg, details: details, date: Date())
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 100 { recentEvents.removeLast() }
        print("[RememberMyWindows] [\(type.rawValue)] \(msg)")
        if let details = details {
            details.forEach { print("  - \($0)") }
        }
    }

    private func formatWindowDetail(record: WindowRecord) -> String {
        let app = record.windowID.appName ?? record.windowID.appBundleID
        let title = record.windowID.windowTitle
        let size = "\(Int(record.globalFrame.width))×\(Int(record.globalFrame.height))"
        let screen = record.screenName ?? "Unknown Screen"
        
        // If the window title is exactly the same as the app name, or contains it redundantly, simplify
        if title.isEmpty || title == app {
            return "\(app) [\(size)] on \(screen)"
        } else {
            return "\(app) '\(title)' [\(size)] on \(screen)"
        }
    }

    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
            lastLocationTimestamp = Date()
            
            if isWaitingForLocationUpdate {
                isWaitingForLocationUpdate = false
                log("📍 Location received. Completing save...", level: .moderate, type: .system)
                performSave(named: pendingSaveName)
                pendingSaveName = nil
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            log("Location error: \(error.localizedDescription)", type: .system)
            if isWaitingForLocationUpdate {
                isWaitingForLocationUpdate = false
                log("⚠️ Location update failed. Proceeding with save anyway.", type: .system)
                performSave(named: pendingSaveName)
                pendingSaveName = nil
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            
            // If authorized, start a single request to get the initial location
            if status != .notDetermined && status != .denied && status != .restricted {
                manager.requestLocation()
            }
            
            if isWaitingForLocationPermission && status != .notDetermined {
                isWaitingForLocationPermission = false
                let isAuthorized = status != .denied && status != .restricted
                log("Location permission updated (\(isAuthorized ? "authorized" : "denied")). Resuming save.", type: .system)
                performSave(named: pendingSaveName)
                pendingSaveName = nil
            }
        }
    }

    /// Helper to geocode and update a snapshot's location
    private func updateSnapshotLocation(key: String, location: CLLocation) {
        Task {
            let coder = CLGeocoder()
            if let placemarks = try? await coder.reverseGeocodeLocation(location),
               let first = placemarks.first {
                let addr = [first.name, first.locality, first.administrativeArea]
                    .compactMap { $0 }.joined(separator: ", ")
                await MainActor.run {
                    if self.store.snapshots[key] != nil {
                        self.store.snapshots[key]?.location = LocationInfo(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            address: addr
                        )
                        self.persist()
                    }
                }
            }
        }
    }
}

// MARK: - Event model

enum EventType: String, Codable {
    case autoSave = "Auto-save"
    case manualSave = "Save"
    case restore = "Restore"
    case system = "System"
}

struct TrackingEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let message: String
    let details: [String]?
    let date: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
