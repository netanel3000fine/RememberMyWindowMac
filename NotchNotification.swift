import SwiftUI
import AppKit
import CoreGraphics

// MARK: - Built-in Screen Detection

private func builtInScreen() -> NSScreen {
    if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
        return notched
    }
    for screen in NSScreen.screens {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let did = CGDirectDisplayID(n.uint32Value)
            if CGDisplayIsBuiltin(did) != 0 {
                return screen
            }
        }
    }
    for screen in NSScreen.screens {
        let name = screen.localizedName.lowercased()
        if name.contains("built-in") || name.contains("retina display")
            || name.contains("liquid retina") || name.contains("color lcd") {
            return screen
        }
    }
    return NSScreen.screens.first ?? NSScreen.main!
}

// MARK: - Notification Data

final class NotificationData: ObservableObject {
    @Published var title: String
    @Published var subtitle: String
    
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Notch Notification Window

final class NotchNotificationWindow: NSPanel {
    let isCompact: Bool
    private let pillWidth: CGFloat
    private let data: NotificationData
    private var dismissTimer: Timer?

    init(title: String, subtitle: String, isCompact: Bool = false) {
        self.isCompact = isCompact
        self.pillWidth = isCompact ? 180 : 280
        self.data = NotificationData(title: title, subtitle: subtitle)
        
        let notchDepth = builtInScreen().safeAreaInsets.top > 0 ? builtInScreen().safeAreaInsets.top : 24.0
        let dynamicPillHeight = notchDepth + (isCompact ? 24.0 : 38.0)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: self.pillWidth, height: dynamicPillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level              = .screenSaver
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func update(title: String, subtitle: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            data.title = title
            data.subtitle = subtitle
        }
        resetDismissTimer()
    }

    func show() {
        let screen = builtInScreen()
        let sf = screen.frame
        let notchDepth = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24.0
        let dynamicPillHeight = notchDepth + (isCompact ? 24.0 : 38.0)
        let visibleY  = sf.maxY - dynamicPillHeight
        let originX   = sf.midX - self.pillWidth / 2

        setFrame(NSRect(x: originX, y: visibleY, width: self.pillWidth, height: dynamicPillHeight), display: true)
        self.alphaValue = 1.0

        let rootView = NotchNotificationView(
            data: data,
            notchDepth: notchDepth,
            pillWidth: self.pillWidth,
            pillHeight: dynamicPillHeight,
            isCompact: isCompact,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: self.pillWidth, height: dynamicPillHeight)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        orderFrontRegardless()
        resetDismissTimer()
    }

    private func resetDismissTimer() {
        dismissTimer?.invalidate()
        let duration: TimeInterval = isCompact ? 2.0 : 5.0
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NotificationCenter.default.post(name: NSNotification.Name("NotchDismiss"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.close()
        }
    }
}

// MARK: - SwiftUI View

struct NotchNotificationView: View {
    @ObservedObject var data: NotificationData
    let notchDepth: CGFloat
    let pillWidth: CGFloat
    let pillHeight: CGFloat
    let isCompact: Bool
    let onDismiss: () -> Void

    @State private var appeared  = false
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 12 : 18, style: .continuous)
                        .fill(Color.black)
                        .padding(.top, isCompact ? -12 : -18)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 12 : 18, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .padding(.top, isCompact ? -12 : -18)
                )
                .clipped()

            HStack(spacing: isCompact ? 8 : 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.22))
                        .frame(width: isCompact ? 18 : 30, height: isCompact ? 18 : 30)
                        .scaleEffect(appeared ? 1.0 : 0.55)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: appeared)
                    Circle()
                        .fill(Color(red: 0.2, green: 0.9, blue: 0.5))
                        .frame(width: isCompact ? 6 : 9, height: isCompact ? 6 : 9)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(data.title)
                        .font(.system(size: isCompact ? 9.5 : 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .id(data.title)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 1.1))
                        ))
                    
                    if !isCompact {
                        Text(data.subtitle)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .id(data.subtitle)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.9)),
                                removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 1.1))
                            ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: data.title)

                Spacer()

                if isHovered && !isCompact {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.65))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.65)))
                }
            }
            .padding(.horizontal, isCompact ? 10 : 14)
            .frame(height: isCompact ? 24 : 38)
        }
        .frame(width: appeared ? pillWidth : (isCompact ? 100 : 160), height: appeared ? pillHeight : notchDepth, alignment: .bottom)
        .shadow(color: .black.opacity(appeared ? 0.55 : 0), radius: appeared ? (isCompact ? 10 : 18) : 0, x: 0, y: isCompact ? 4 : 6)
        .opacity(appeared ? 1.0 : 0.0)
        .scaleEffect(appeared ? 1.0 : 0.8, anchor: .top)
        .frame(width: pillWidth, height: pillHeight, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appeared)
        .onAppear { 
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true 
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NotchDismiss"))) { _ in
            appeared = false
        }
        .onHover { hovering in
            if !isCompact {
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            }
        }
    }
}
