import Foundation
import AppKit

extension CGRect {
    var area: CGFloat { width * height }
}

struct LocationInfo: Codable {
    let latitude: Double
    let longitude: Double
    let address: String?
}

enum LogLevel: String, Codable, CaseIterable {
    case necessary = "Necessary"
    case moderate = "Moderate"
    case verbose = "Verbose"
}

// MARK: - Window Record

/// Stable identity for a window across sessions.
struct WindowID: Codable, Hashable {
    let appBundleID: String
    let appName: String?         // Localized app name
    let windowTitle: String      // Best-effort; empty when Screen Recording permission isn't granted
    let appWindowIndex: Int      // 0-based index among all windows of the same app (ensures uniqueness when title is empty)

    var displayName: String {
        let baseApp = appName ?? appBundleID
        let base = windowTitle.isEmpty ? baseApp : "\(baseApp) – \(windowTitle)"
        return appWindowIndex > 0 ? "\(base) [\(appWindowIndex + 1)]" : base
    }
}

/// A single saved window state.
struct WindowRecord: Codable, Identifiable {
    var id: UUID = UUID()
    let windowID: WindowID
    /// Frame in global screen coordinates (origin = bottom-left of primary screen).
    let globalFrame: CGRect
    /// Screen fingerprint the window was on when saved.
    let screenKey: String
    /// The frame of the screen this window was on (in global coordinates).
    let screenFrame: CGRect?
    let screenName: String?      // Name of the screen this window was on
    let savedAt: Date
    var zIndex: Int?             // 0 = front-most
    /// True when this window was captured via the offScreen fallback path —
    /// meaning the app had no visible windows on the current Space at capture time
    /// (e.g. it was arranged to fill a different Space with a window manager).
    var isFullScreenMode: Bool = false
    /// True when this window was in native macOS full-screen mode at capture time.
    var isNativeFullScreen: Bool = false

    /// Frame relative to the screen's own coordinate space.
    func frameRelativeTo(screen: NSScreen) -> CGRect {
        CGRect(
            x: globalFrame.origin.x - screen.frame.origin.x,
            y: globalFrame.origin.y - screen.frame.origin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }
}

// MARK: - Layout Snapshot

/// All window records for a particular screen configuration.
struct LayoutSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    let screenKey: String
    let readableScreenKey: String? // Human-readable screen description
    var records: [WindowRecord]
    var createdAt: Date
    var updatedAt: Date
    var location: LocationInfo?
    var isAutoSave: Bool = false
    /// Bundle ID of the app that should be brought to the foreground after restore.
    /// Set via right-click → "Bring to Front" in the window list.
    var foregroundBundleID: String? = nil

    /// A cleaned-up version of the name, removing resolutions and shortening common display names for UI display.
    var displayName: String {
        // Remove resolutions like (1440x932) or (2560×1440)
        let cleaned = name.replacingOccurrences(of: "\\s*\\(\\d+[x×]\\d+\\)", with: "", options: .regularExpression)
        
        // Handle both English and Hebrew versions of the built-in name
        let target = lz(cleaned)
        return target.replacingOccurrences(of: "Built-in Retina Display", with: "Built-in")
                     .replacingOccurrences(of: "צג Retina מובנה", with: "מובנה")
    }

    mutating func upsert(_ record: WindowRecord) {
        if let idx = records.firstIndex(where: { $0.windowID == record.windowID }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        updatedAt = Date()
    }
}

// MARK: - Layout Store (top-level persisted object)

struct LayoutStore: Codable {
    /// key = LayoutSnapshot.id.uuidString
    var snapshots: [String: LayoutSnapshot] = [:]
    /// key = ScreenFingerprint.key, value = LayoutSnapshot.id.uuidString
    var defaultSnapshotIDs: [String: String] = [:]
    var autoSaveEnabled: Bool = true
    var autoRestoreEnabled: Bool = true
    var restoreAnimated: Bool = true
    /// Restores an app's layout automatically when it is launched.
    var autoRestoreOnAppOpen: Bool = true
    var logLevel: LogLevel = .moderate


    // Custom decode so new Bool flags fall back to their defaults when the key
    // is absent in an older persisted JSON, instead of throwing and wiping the store.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshots            = try c.decodeIfPresent([String: LayoutSnapshot].self, forKey: .snapshots)            ?? [:]
        defaultSnapshotIDs   = try c.decodeIfPresent([String: String].self,         forKey: .defaultSnapshotIDs)   ?? [:]
        autoSaveEnabled      = try c.decodeIfPresent(Bool.self, forKey: .autoSaveEnabled)      ?? true
        autoRestoreEnabled   = try c.decodeIfPresent(Bool.self, forKey: .autoRestoreEnabled)   ?? true
        restoreAnimated      = try c.decodeIfPresent(Bool.self, forKey: .restoreAnimated)      ?? true
        autoRestoreOnAppOpen = try c.decodeIfPresent(Bool.self, forKey: .autoRestoreOnAppOpen) ?? true
        logLevel             = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel)             ?? .moderate

    }

    init() {}
}

