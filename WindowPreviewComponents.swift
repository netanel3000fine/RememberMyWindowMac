import SwiftUI

// MARK: - Window Preview Icon (for list rows)

struct WindowPreviewIcon: View {
    let record: WindowRecord
    let tint: Color

    private let displayW: CGFloat = 52
    private let displayH: CGFloat = 34
    private let cornerR: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ── Screen bezel ──────────────────────────────────
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .stroke(tint.opacity(0.2), lineWidth: 0.75) // Theme-colored bezel
                }

            // ── Window rectangle ──────────────────────────────
            GeometryReader { geo in
                let screenFrame = record.screenFrame
                    ?? NSScreen.main?.frame
                    ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

                let canvasW = geo.size.width
                let canvasH = geo.size.height

                let scaleX = canvasW / screenFrame.width
                let scaleY = canvasH / screenFrame.height

                let relX = (record.globalFrame.origin.x - screenFrame.origin.x) * scaleX
                let relY = (screenFrame.height
                            - (record.globalFrame.origin.y - screenFrame.origin.y)
                            - record.globalFrame.height) * scaleY
                let winW  = min(canvasW, max(6, record.globalFrame.width  * scaleX))
                let winH  = min(canvasH, max(5, record.globalFrame.height * scaleY))
                let isFilled = winW >= canvasW * 0.92 && winH >= canvasH * 0.92
                let winCorner: CGFloat = isFilled ? cornerR : 2

                ZStack(alignment: .topLeading) {
                    // Window body
                    RoundedRectangle(cornerRadius: winCorner, style: .continuous)
                        .fill(tint.opacity(isFilled ? 0.28 : 0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: winCorner, style: .continuous)
                                .stroke(tint.opacity(0.8), lineWidth: 0.75)
                        }
                    
                    // Abstract Content Blocks
                    VStack(alignment: .leading, spacing: 2) {
                        // Title bar with dots
                        HStack(spacing: 1.5) {
                            Circle().fill(tint.opacity(0.6)).frame(width: 1.5, height: 1.5)
                            Circle().fill(tint.opacity(0.4)).frame(width: 1.5, height: 1.5)
                            Circle().fill(tint.opacity(0.4)).frame(width: 1.5, height: 1.5)
                        }
                        .padding(.leading, 2)
                        .padding(.top, 1)
                        
                        // Body bars
                        if winH > 10 {
                            VStack(alignment: .leading, spacing: 2) {
                                RoundedRectangle(cornerRadius: 0.5).fill(tint.opacity(0.2)).frame(width: winW * 0.6, height: 1.5)
                                RoundedRectangle(cornerRadius: 0.5).fill(tint.opacity(0.15)).frame(width: winW * 0.8, height: 1.5)
                                RoundedRectangle(cornerRadius: 0.5).fill(tint.opacity(0.1)).frame(width: winW * 0.4, height: 1.5)
                            }
                            .padding(.leading, 3)
                            .padding(.top, 1)
                        }
                    }
                }
                .frame(width: winW, height: winH)
                .offset(x: relX, y: relY)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: record.globalFrame)
            }
        }
        .frame(width: displayW, height: displayH)
    }
}

// MARK: - Full-Screen Window Preview Icon

struct FullScreenPreviewIcon: View {
    let tint: Color
    private let displayW: CGFloat = 52
    private let displayH: CGFloat = 34
    private let cornerR: CGFloat = 4

    var body: some View {
        ZStack {
            // Screen bezel — fully filled with tint
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(tint.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .stroke(tint.opacity(0.6), lineWidth: 0.75)
                }

            // Abstract Content: Multiple bars to show "filling"
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.3)).frame(width: 30, height: 2)
                RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.2)).frame(width: 25, height: 2)
                RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.1)).frame(width: 20, height: 2)
            }
            .offset(y: 2)
        }
        .frame(width: displayW, height: displayH)
    }
}

// MARK: - Layout Preview View (for detail view)

struct AppIconView: View {
    let bundleID: String
    var body: some View {
        let image: NSImage? = {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return nil
        }()
        
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }
}

struct LayoutPreviewView: View {
    let snapshot: LayoutSnapshot
    let selectedRecordID: UUID?
    let tint: Color
    
    var body: some View {
        GeometryReader { geo in
            let boundingBox = calculateBoundingBox()
            let scale = calculateScale(for: geo.size, boundingBox: boundingBox)
            
            ZStack {
                // Screens
                ForEach(getScreenFrames(), id: \.origin.x) { frame in
                    screenView(frame: frame, boundingBox: boundingBox, scale: scale)
                }
                
                // Windows
                ForEach(snapshot.records) { record in
                    windowView(record: record, boundingBox: boundingBox, scale: scale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .liquidGlass(cornerRadius: 16, style: .card)
    }
    
    private func screenView(frame: CGRect, boundingBox: CGRect, scale: CGFloat) -> some View {
        let x = (frame.origin.x - boundingBox.origin.x) * scale
        let y = (boundingBox.height - (frame.origin.y - boundingBox.origin.y + frame.height)) * scale
        let w = frame.width * scale
        let h = frame.height * scale
        
        let cornerR: CGFloat = 10 * scale
        
        return ZStack {
            // Main Panel
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(Color.black.opacity(0.65))
            
            // Inner glow / bezel detail
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.15), .clear, .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        }
        .frame(width: w, height: h)
        .position(x: x + w/2, y: y + h/2)
    }
    
    private func windowView(record: WindowRecord, boundingBox: CGRect, scale: CGFloat) -> some View {
        let isSelected = record.id == selectedRecordID
        let x = (record.globalFrame.origin.x - boundingBox.origin.x) * scale
        let y = (boundingBox.height - (record.globalFrame.origin.y - boundingBox.origin.y + record.globalFrame.height)) * scale
        let w = record.globalFrame.width * scale
        let h = record.globalFrame.height * scale
        
        // Match Theme Colors
        let baseTint = tint
        let winCorner: CGFloat = max(4, 8 * scale)
        
        return ZStack {
            // Window body with theme-colored glass
            RoundedRectangle(cornerRadius: winCorner, style: .continuous)
                .fill(baseTint.opacity(isSelected ? 0.45 : 0.25))
                .overlay {
                    // Vibrant theme-colored border
                    RoundedRectangle(cornerRadius: winCorner, style: .continuous)
                        .stroke(baseTint.opacity(isSelected ? 1.0 : 0.6), lineWidth: isSelected ? 1.5 : 0.75)
                }
                .shadow(color: baseTint.opacity(isSelected ? 0.5 : 0.0), radius: 8, x: 0, y: 0)
            
            // App Icon
            AppIconView(bundleID: record.windowID.appBundleID)
                .frame(width: min(w * 0.7, 32), height: min(h * 0.7, 32))
                .shadow(color: .black.opacity(0.2), radius: 2)
            
            // Optional label if window is large enough
            if w > 60 && h > 40 {
                VStack {
                    Spacer()
                    Text(record.windowID.appName?.prefix(12) ?? "")
                        .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.bottom, 4)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
        }
        .frame(width: max(8, w), height: max(8, h))
        .position(x: x + w/2, y: y + h/2)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: record.globalFrame)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
    
    // Helpers
    
    private func getScreenFrames() -> [CGRect] {
        let frames = Set(snapshot.records.compactMap { $0.screenFrame }).sorted { $0.origin.x < $1.origin.x }
        if frames.isEmpty {
            return [NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        }
        return frames
    }
    
    private func calculateBoundingBox() -> CGRect {
        let frames = getScreenFrames()
        guard let first = frames.first else { return .zero }
        return frames.reduce(first) { $0.union($1) }
    }
    
    private func calculateScale(for size: CGSize, boundingBox: CGRect) -> CGFloat {
        let horizontalScale = size.width / boundingBox.width
        let verticalScale = size.height / boundingBox.height
        return min(horizontalScale, verticalScale) * 0.9 // Add some padding
    }
}

// MARK: - Screen Layout Thumbnail (for snapshot list rows)

/// Draws proportional monitor-outline rectangles for each display in a snapshot's screen config.
/// Single display → one rectangle. Two displays side-by-side → two rectangles, etc.
struct ScreenLayoutThumbnail: View {
    let screenKey: String
    let tint: Color
    let isLive: Bool

    /// Fixed canvas size for the thumbnail area
    private let canvasW: CGFloat = 34
    private let canvasH: CGFloat = 22

    private var fingerprint: ScreenFingerprint {
        ScreenFingerprint.from(key: screenKey)
    }

    private var displays: [ScreenFingerprint.DisplayID] {
        let d = fingerprint.displays
        // Sort left-to-right by origin so layout order is preserved
        return d.sorted { $0.originX < $1.originX }
    }

    private var boundingBox: CGRect {
        guard let first = displays.first else { return .zero }
        return displays.reduce(CGRect(x: first.originX, y: first.originY,
                                     width: first.width, height: first.height)) { box, d in
            box.union(CGRect(x: d.originX, y: d.originY, width: d.width, height: d.height))
        }
    }

    var body: some View {
        let bb = boundingBox
        guard bb.width > 0, bb.height > 0 else { return AnyView(EmptyView()) }

        let scaleX = canvasW / bb.width
        let scaleY = canvasH / bb.height
        let scale  = min(scaleX, scaleY)

        // Center the layout within the canvas
        let layoutW = bb.width  * scale
        let layoutH = bb.height * scale
        let offsetX = (canvasW - layoutW) / 2
        let offsetY = (canvasH - layoutH) / 2

        return AnyView(
            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.offset) { _, d in
                    let x = CGFloat(d.originX - Int(bb.minX)) * scale + offsetX
                    // Invert Y: macOS is Y-up, SwiftUI is Y-down.
                    // Calculate distance from the TOP of the bounding box to the TOP of this display.
                    let y = CGFloat(Int(bb.maxY) - (d.originY + d.height)) * scale + offsetY
                    let w = max(6, CGFloat(d.width)  * scale)
                    let h = max(4, CGFloat(d.height) * scale)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(isLive ? 0.18 : 0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(tint.opacity(isLive ? 0.85 : 0.55), lineWidth: 1)
                        }
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
            .frame(width: canvasW, height: canvasH)
        )
    }
}

// MARK: - Menu Window List View (for Menu Bar)

struct MenuWindowListView: View {
    let snapshot: LayoutSnapshot
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default

    var body: some View {
        VStack(spacing: 2) {
            ForEach(snapshot.records) { record in
                let isForeground = record.windowID.appBundleID == snapshot.foregroundBundleID
                let rowTint = record.isFullScreenMode ? Color.indigo : (themeColor.color ?? .accentColor)
                
                HStack(spacing: 12) {
                    if record.isFullScreenMode {
                        FullScreenPreviewIcon(tint: rowTint)
                            .frame(width: 32, height: 21)
                    } else {
                        WindowPreviewIcon(record: record, tint: rowTint)
                            .frame(width: 32, height: 21)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(record.windowID.appName ?? record.windowID.appBundleID)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .lineLimit(1)
                            
                            if isForeground {
                                Image(systemName: "square.3.layers.3d.top.filled")
                                    .font(.system(size: 8))
                                    .foregroundStyle(themeColor.color ?? Color.accentColor)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            if let screenName = record.screenName {
                                Text(lz(screenName))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(rowTint.opacity(0.1))
                                    .foregroundStyle(rowTint)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            
                            if !record.windowID.windowTitle.isEmpty {
                                Text(record.windowID.windowTitle)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
    }
}

