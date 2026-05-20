import SwiftUI

extension EventType {
    var icon: String {
        switch self {
        case .autoSave: return "clock.arrow.circlepath"
        case .manualSave: return "arrow.down.doc.fill"
        case .restore: return "arrow.uturn.backward.circle.fill"
        case .system: return "cpu"
        }
    }
    
    var color: Color {
        switch self {
        case .autoSave: return .orange
        case .manualSave: return .blue
        case .restore: return .green
        case .system: return .purple
        }
    }
}

import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var manager: WindowManager
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Header - Compact
                HStack {
                    Text("ACTIVITY LOG".localized(appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            let text = manager.recentEvents.map { event in
                                var str = "[\(event.timeString)] \(event.type.rawValue.uppercased()): \(event.message)"
                                if let details = event.details {
                                    str += "\n" + details.map { "  • \($0)" }.joined(separator: "\n")
                                }
                                return str
                            }.joined(separator: "\n\n")
                            pasteboard.setString(text, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy Full Log".localized(appLanguage))
                        
                        Button(action: { manager.clearEvents() }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Clear Log".localized(appLanguage))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Activity List
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if manager.recentEvents.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "circle.dotted")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("History is empty".localized(appLanguage))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(manager.recentEvents.reversed()) { event in
                                eventRow(event)
                                    .id(event.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: manager.recentEvents.first?.id) { _ in
                if let newest = manager.recentEvents.first {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo(newest.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: TrackingEvent) -> some View {
        let currentThemeColor = themeColor.color ?? .accentColor
        
        return HStack(alignment: .top, spacing: 8) {
            // Compact Icon Block
            ZStack {
                Circle()
                    .fill(event.type.color.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: event.type.icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(event.type.color)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.message)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(event.timeString)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                
                if let details = event.details {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(details, id: \.self) { detail in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(currentThemeColor.opacity(0.5))
                                    .frame(width: 3, height: 3)
                                    .padding(.top, 6)
                                Text(detail)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
