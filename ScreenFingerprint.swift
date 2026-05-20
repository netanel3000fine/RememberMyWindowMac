import AppKit
import Foundation
import QuartzCore

/// Uniquely identifies a physical display or a combination of displays.
struct ScreenFingerprint: Codable, Hashable, CustomStringConvertible {

    /// Per-display identifier derived from IOKit/Quartz display UUID.
    struct DisplayID: Codable, Hashable {
        let uuid: String?              // Stable physical ID (UUID from EDID)
        let name: String?              // Localized name of the display
        let screenNumber: Int          // System-assigned number (fallback)
        let width: Int
        let height: Int
        let originX: Int
        let originY: Int

        var frame: CGRect {
            CGRect(x: CGFloat(originX), y: CGFloat(originY), width: CGFloat(width), height: CGFloat(height))
        }

        /// Use UUID if available for the description/key, otherwise fallback to screenNumber.
        var description: String { 
            let id = uuid ?? "\(screenNumber)"
            let normalizedName = normalizeToEnglish(name ?? "Unknown")
            let safeName = normalizedName.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: "+", with: "")
            return "\(id)|\(safeName)@\(originX),\(originY),\(width)x\(height)" 
        }
    }

    /// Sorted display IDs so order doesn't matter.
    let displays: [DisplayID]

    var key: String { displays.map(\.description).sorted().joined(separator: "+") }
    
    /// Identifies the set of physical screens regardless of their arrangement.
    var hardwareKey: String { 
        displays.map { 
            let id = $0.uuid ?? "\($0.screenNumber)"
            return "\(id)@\(Int($0.width))x\(Int($0.height))" 
        }
        .sorted()
        .joined(separator: "+") 
    }
    
    /// Identifies screens by model (name and resolution) but ignores physical identity (UUID) and arrangement.
    var modelKey: String {
        displays.map { 
            let n = normalizeToEnglish($0.name ?? "Unknown")
            return "\(n)@\(Int($0.width))x\(Int($0.height))"
        }
        .sorted()
        .joined(separator: "+")
    }

    var description: String { key }

    // MARK: - Factory

    static func current() -> ScreenFingerprint {
        let displays = NSScreen.screens.compactMap { screen -> DisplayID? in
            let desc = screen.deviceDescription
            guard
                let screenNum = desc[NSDeviceDescriptionKey("NSScreenNumber")] as? Int,
                let size = desc[NSDeviceDescriptionKey("NSDeviceSize")] as? NSSize
            else { return nil }

            // Fetch physical UUID (stable across reboots and ports)
            var uuid: String? = nil
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(screenNum)) {
                let cfUUID = uuidRef.takeRetainedValue()
                uuid = CFUUIDCreateString(nil, cfUUID) as String
            }

            // Fallback: use pixel dimensions from the screen frame
            let w = Int(size.width > 0 ? size.width : screen.frame.width)
            let h = Int(size.height > 0 ? size.height : screen.frame.height)
            let ox = Int(screen.frame.origin.x)
            let oy = Int(screen.frame.origin.y)
            let name = screen.localizedName
            return DisplayID(uuid: uuid, name: name, screenNumber: screenNum, width: w, height: h, originX: ox, originY: oy)
        }
        return ScreenFingerprint(displays: displays.sorted { ($0.uuid ?? "") < ($1.uuid ?? "") })
    }

    /// Reconstructs a fingerprint from a key string.
    static func from(key: String) -> ScreenFingerprint {
        let components = key.components(separatedBy: "+")
        let displays = components.compactMap { comp -> DisplayID? in
            // Handle new format: "UUID|Name@Geo" or old format: "ID@Geo"
            let mainParts = comp.components(separatedBy: "@")
            guard mainParts.count == 2 else { return nil }
            
            let idAndName = mainParts[0].components(separatedBy: "|")
            let idPart = idAndName[0]
            let name = idAndName.count > 1 ? idAndName[1] : nil
            
            var uuid: String? = nil
            var screenNum = 0
            
            if idPart.contains("-") && idPart.count > 10 {
                uuid = idPart
            } else {
                screenNum = Int(idPart) ?? 0
            }
            
            let geoParts = mainParts[1].components(separatedBy: ",")
            guard geoParts.count == 3 else { return nil }
            let ox = Int(geoParts[0]) ?? 0
            let oy = Int(geoParts[1]) ?? 0
            
            let sizeParts = geoParts[2].components(separatedBy: "x")
            guard sizeParts.count == 2 else { return nil }
            let w = Int(sizeParts[0]) ?? 0
            let h = Int(sizeParts[1]) ?? 0
            
            return DisplayID(uuid: uuid, name: name, screenNumber: screenNum, width: w, height: h, originX: ox, originY: oy)
        }
        return ScreenFingerprint(displays: displays)
    }

    /// Human-readable summary, e.g. "Built-in (2560×1600) + Dell U2722 (2560×1440)"
    var readableName: String {
        if displays.isEmpty { return lz("No Display") }
        
        // Count occurrences of each name to detect duplicates
        var nameCounts: [String: Int] = [:]
        for d in displays {
            var n = d.name ?? "\(lz("Display")) \(d.screenNumber)"
            if n.hasPrefix("Built-in") || n.contains("מובנה") { n = lz("Built-in") }
            nameCounts[n, default: 0] += 1
        }

        return displays.map { d in
            let originalName = d.name ?? "\(lz("Display")) \(d.screenNumber)"
            var label = originalName
            if label.hasPrefix("Built-in") || label.contains("מובנה") { label = lz("Built-in") }
            else { label = lz(label) }
            
            // Disambiguate if multiple monitors have the same name
            if nameCounts[label, default: 0] > 1, let uuid = d.uuid {
                let shortID = String(uuid.suffix(4))
                label += " (\(shortID))"
            }
            
            label += " (\(d.width)×\(d.height))"
            return label
        }.joined(separator: " + ")
    }
}
