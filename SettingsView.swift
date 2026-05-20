import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var manager: WindowManager
    @ObservedObject var desktopToggleManager = DesktopToggleManager.shared
    @AppStorage("isLiquidGlass") private var isLiquidGlass: Bool = true
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("showNotchNotification") private var showNotchNotification: Bool = true
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Automation Section
                SettingsSection(title: "Automation".localized(appLanguage), icon: "bolt.fill") {
                    VStack(spacing: 0) {

                        SettingsToggle(
                            title: "Auto-restore on connect",
                            subtitle: "Restores layout when displays reconnect",
                            icon: "display.2",
                            isOn: Binding(
                                get: { manager.store.autoRestoreEnabled },
                                set: { manager.store.autoRestoreEnabled = $0 }
                            )
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Auto-restore on app open",
                            subtitle: "Restores layout when an app is launched",
                            icon: "app.badge.checkmark",
                            isOn: Binding(
                                get: { manager.store.autoRestoreOnAppOpen },
                                set: { manager.store.autoRestoreOnAppOpen = $0 }
                            )
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Animate restoration",
                            subtitle: "Smoothly move windows to their spots",
                            icon: "wand.and.stars",
                            isOn: Binding(
                                get: { manager.store.restoreAnimated },
                                set: { manager.store.restoreAnimated = $0 }
                            )
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Launch at login",
                            subtitle: "Start RememberMyWindows automatically",
                            icon: "arrow.right.square.fill",
                            isOn: $manager.launchAtLogin
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsPicker(
                            title: "Activity Log Level",
                            subtitle: "Filter which events appear in the log",
                            icon: "list.bullet.rectangle.portrait",
                            selection: Binding(
                                get: { manager.store.logLevel },
                                set: { manager.store.logLevel = $0 }
                            )
                        )
                    }
                }

                // Experimental Section
                SettingsSection(title: "Experimental".localized(appLanguage), icon: "flask.fill") {
                    VStack(spacing: 0) {
                        SettingsToggle(
                            title: "Desktop Toggle (Cmd+D)",
                            subtitle: "Quickly hide/show all windows (disabled for Safari)",
                            icon: "keyboard",
                            isOn: $desktopToggleManager.isEnabled
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Restore on Cmd+D unhide",
                            subtitle: "Automatically run layout restore when showing windows",
                            icon: "arrow.uturn.backward",
                            isOn: $desktopToggleManager.restoreOnUnhide
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Focus configured app on unhide",
                            subtitle: "Bring the snapshot's frontmost app to focus when unhiding",
                            icon: "app.badge",
                            isOn: $desktopToggleManager.focusConfiguredAppOnUnhide
                        )
                    }
                }

                // Appearance Section
                SettingsSection(title: "Appearance".localized(appLanguage), icon: "paintpalette.fill") {
                    VStack(spacing: 0) {
                        SettingsToggle(
                            title: "Liquid Glass interface",
                            subtitle: "Enable premium transparency and effects",
                            icon: "sparkles",
                            isOn: $isLiquidGlass
                        )

                        Divider().padding(.horizontal, 12)

                        SettingsToggle(
                            title: "Notch Notification",
                            subtitle: "Show layout restore alerts from the notch",
                            icon: "capsule.inset.filled",
                            isOn: $showNotchNotification
                        )

                        Divider().padding(.horizontal, 12)

                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Theme Color".localized(appLanguage))
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Primary accent for the interface".localized(appLanguage))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(themeColor.color ?? .accentColor)
                                    .font(.system(size: 14))
                                    .frame(width: 24)
                            }

                            Spacer()

                            Picker("", selection: $themeColor) {
                                ForEach(ThemeColor.allCases) { theme in
                                    Text(theme.rawValue).tag(theme)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        .padding(12)

                        Divider().padding(.horizontal, 12)

                        SettingsLanguagePicker(
                            title: "App Language",
                            subtitle: "Override the system language",
                            icon: "globe",
                            selection: $appLanguage
                        )

                        Text("Restart app to apply to system menus".localized(appLanguage))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                }

                // System Permissions Section
                SettingsSection(title: "System Permissions".localized(appLanguage), icon: "shield.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(manager.hasAccessibilityPermission ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                                .shadow(color: (manager.hasAccessibilityPermission ? Color.green : Color.orange).opacity(0.5), radius: 4)

                            Text(manager.hasAccessibilityPermission
                                 ? "Accessibility access granted".localized(appLanguage)
                                 : "Accessibility access required".localized(appLanguage))
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            if !manager.hasAccessibilityPermission {
                                Button("Grant Permission…".localized(appLanguage)) {
                                    manager.requestAccessibilityPermission()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }

                        Text("RememberMyWindows needs Accessibility permission to restore window positions in other apps like Telegram, Chrome, etc.".localized(appLanguage))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        } label: {
                            HStack {
                                Text("Open System Settings…".localized(appLanguage))
                                Image(systemName: "arrow.up.forward.app")
                            }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                    .padding(16)
                }

                // About Section
                VStack(spacing: 8) {
                    HStack {
                        Text("Version 1.0.0".localized(appLanguage))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 650)
        .navigationTitle("Settings".localized(appLanguage))
        .background {
            if isLiquidGlass {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            } else {
                VisualEffectView(material: .windowBackground, blendingMode: .withinWindow)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: appLanguage) { oldValue, newValue in
            if newValue == .english {
                UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            } else if newValue == .hebrew {
                UserDefaults.standard.set(["he"], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            content
                .liquidGlass(style: .card)
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    // Each component observes appLanguage so it re-renders when the language changes
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized(appLanguage))
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle.localized(appLanguage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .padding(4)
            }
        }
    }
}

struct SettingsPicker: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var selection: LogLevel

    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized(appLanguage))
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle.localized(appLanguage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.localized(appLanguage)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 100)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .padding(4)
            }
        }
    }
}

struct SettingsLanguagePicker: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var selection: AppLanguage

    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized(appLanguage))
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle.localized(appLanguage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // EN / HE toggle buttons — same pattern as The Real Screen Recorder
            HStack(spacing: 6) {
                Button { selection = .english } label: {
                    Text("EN")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 34, height: 24)
                        .background(selection == .english
                            ? Color.accentColor
                            : Color.primary.opacity(0.1))
                        .foregroundColor(selection == .english ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button { selection = .hebrew } label: {
                    Text("עב")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 34, height: 24)
                        .background(selection == .hebrew
                            ? Color.accentColor
                            : Color.primary.opacity(0.1))
                        .foregroundColor(selection == .hebrew ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .padding(4)
            }
        }
    }
}
