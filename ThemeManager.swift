import SwiftUI

enum ThemeColor: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case grey      = "Grey"
    case purple    = "Purple"
    case yellow    = "Yellow"
    case red       = "Red"
    case blue      = "Blue"
    case lightBlue = "Light Blue"
    case green     = "Green"
    case orange    = "Orange"

    var id: String { rawValue }

    var color: Color? {
        switch self {
        case .default:   return nil
        case .grey:      return .gray
        case .purple:    return .purple
        case .yellow:    return .yellow
        case .red:       return .red
        case .blue:      return .blue
        case .lightBlue: return .cyan
        case .green:     return .green
        case .orange:    return .orange
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto   = "system"
    case english = "en"
    case hebrew  = "he"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .auto:    return "Auto"
        case .english: return "English"
        case .hebrew:  return "עברית"
        }
    }
}


struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Liquid Glass Helper

struct LiquidGlassModifier: ViewModifier {
    @AppStorage("isLiquidGlass") private var isLiquidGlass: Bool = true
    
    var cornerRadius: CGFloat = 12
    var isSelected: Bool = false
    var prominent: Bool = false
    var tint: Color? = nil
    var isHovered: Bool = false
    var style: GlassStyle = .row

    func body(content: Content) -> some View {
        if isLiquidGlass {
            content
                .background {
                    ZStack {
                        if style == .card {
                            VisualEffectView(material: .selection, blendingMode: .withinWindow)
                                .opacity(isHovered ? 0.45 : 0.35)
                        }
                        
                        if prominent {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.white.opacity(isHovered ? 0.12 : 0.04))
                        } else {
                            if isSelected {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                            } else if isHovered {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(style == .card ? 0.08 : 0.04), lineWidth: 0.5)
                        .overlay {
                            if style == .card {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            }
                        }
                }
                .shadow(color: Color.black.opacity(style == .card ? 0.1 : (isSelected ? 0.08 : (prominent ? 0.15 : 0.0))), 
                        radius: style == .card ? 6 : (isSelected ? 1.0 : (prominent ? 1.5 : 0)), 
                        x: 0, 
                        y: style == .card ? 3 : (isSelected ? 0.5 : (prominent ? 1 : 0)))
                .scaleEffect(isHovered && style != .card && !isSelected && !prominent ? 1.015 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        } else {
            content
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill((tint ?? .accentColor).opacity(0.15))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
                .overlay {
                    if style == .card {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 12, isSelected: Bool = false, prominent: Bool = false, tint: Color? = nil, isHovered: Bool = false, style: GlassStyle = .row) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isSelected: isSelected, prominent: prominent, tint: tint, isHovered: isHovered, style: style))
    }
}

enum GlassStyle {
    case row
    case card
}
