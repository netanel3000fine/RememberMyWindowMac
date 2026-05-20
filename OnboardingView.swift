import SwiftUI

// MARK: - Root

struct OnboardingView: View {
    var onComplete: () -> Void

    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var phase: OnboardingPhase = .languagePicker

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            switch phase {
            case .languagePicker:
                OnboardingLanguageView(selectedLanguage: $appLanguage) {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                        phase = .permissions
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .permissions:
                OnboardingPermissionsView(language: appLanguage) {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                        phase = .guide
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .guide:
                OnboardingGuideView(language: appLanguage, onComplete: onComplete)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(width: 560, height: 520)
        .environment(\.layoutDirection, appLanguage == .hebrew ? .rightToLeft : .leftToRight)
    }
}

private enum OnboardingPhase { case languagePicker, permissions, guide }

// MARK: - Phase 1: Language Picker

struct OnboardingLanguageView: View {
    @Binding var selectedLanguage: AppLanguage
    var onContinue: () -> Void

    @State private var hoverEN = false
    @State private var hoverHE = false
    @State private var hoverContinue = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon glow
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .overlay { Circle().stroke(Color.accentColor.opacity(0.22), lineWidth: 1) }
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 22, x: 0, y: 8)

                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 18)

            Text("RememberMyWindows")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("Your window manager")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            Text("Choose Your Language")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)

            HStack(spacing: 16) {
                OBLanguageButton(code: "EN", name: "English",
                                 isSelected: selectedLanguage == .english,
                                 isHovered: hoverEN) { selectedLanguage = .english }
                    .onHover { hoverEN = $0 }

                OBLanguageButton(code: "עב", name: "עברית",
                                 isSelected: selectedLanguage == .hebrew,
                                 isHovered: hoverHE) { selectedLanguage = .hebrew }
                    .onHover { hoverHE = $0 }
            }
            .padding(.bottom, 32)

            Button {
                if selectedLanguage == .auto { selectedLanguage = .english }
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text(selectedLanguage == .hebrew ? "המשך" : "Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 210, height: 44)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 4)
                .scaleEffect(hoverContinue ? 1.03 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hoverContinue)
            }
            .buttonStyle(.plain)
            .onHover { hoverContinue = $0 }

            Spacer()
        }
        .padding(.horizontal, 60)
    }
}

struct OBLanguageButton: View {
    let code: String
    let name: String
    let isSelected: Bool
    let isHovered: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(code)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(width: 130, height: 90)
            .liquidGlass(cornerRadius: 16, isSelected: isSelected, isHovered: isHovered, style: .card)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
            }
            .scaleEffect(isSelected ? 1.04 : (isHovered ? 1.02 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase 1.5: Accessibility Permissions

struct OnboardingPermissionsView: View {
    let language: AppLanguage
    var onContinue: () -> Void

    @State private var hasPermission = AXIsProcessTrusted()
    @State private var hoverGrant = false
    @State private var hoverSkip  = false
    @State private var pulseShield = false
    @State private var permissionTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.30), Color.orange.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .overlay { Circle().stroke(Color.orange.opacity(0.25), lineWidth: 1) }
                    .shadow(color: Color.orange.opacity(0.22), radius: 22, x: 0, y: 8)
                    .scaleEffect(pulseShield ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulseShield)

                Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(hasPermission ? Color.green : Color.orange)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 20)

            Text(hasPermission
                 ? "Accessibility access granted".localized(language)
                 : "Accessibility Permission Required".localized(language))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(hasPermission ? .green : .primary)
                .animation(.easeInOut(duration: 0.3), value: hasPermission)

            Text("RememberMyWindows needs Accessibility permission to restore window positions in other apps like Telegram, Chrome, etc.".localized(language))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .padding(.top, 10)

            Spacer()

            // Grant / Continue button
            if hasPermission {
                Button { onContinue() } label: {
                    HStack(spacing: 8) {
                        Text("Continue".localized(language))
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 210, height: 44)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.green.opacity(0.4), radius: 12, x: 0, y: 4)
                    .scaleEffect(hoverGrant ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hoverGrant)
                }
                .buttonStyle(.plain)
                .onHover { hoverGrant = $0 }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                        Text("Grant Permission…".localized(language))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 210, height: 44)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.orange.opacity(0.4), radius: 12, x: 0, y: 4)
                    .scaleEffect(hoverGrant ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hoverGrant)
                }
                .buttonStyle(.plain)
                .onHover { hoverGrant = $0 }
            }

            // Skip link
            if !hasPermission {
                Button {
                    onContinue()
                } label: {
                    Text("Skip for now".localized(language))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .onHover { hoverSkip = $0 }
            }

            Spacer()
        }
        .padding(.horizontal, 50)
        .onAppear {
            pulseShield = true
            // Poll every second so the shield updates when the user grants permission in System Settings
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                let trusted = AXIsProcessTrusted()
                if trusted != hasPermission {
                    withAnimation { hasPermission = trusted }
                    if trusted {
                        closeSystemSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            onContinue()
                        }
                    }
                }
            }
        }
        .onDisappear { permissionTimer?.invalidate() }
    }

    private func closeSystemSettings() {
        let targetBundleIDs = ["com.apple.systempreferences"]
        let targetNames = ["System Settings", "System Preferences", "הגדרות המערכת"]
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, targetBundleIDs.contains(bundleID) {
                app.terminate()
            } else if let name = app.localizedName, targetNames.contains(name) {
                app.terminate()
            }
        }
    }
}

// MARK: - Phase 2: Guided Tour

struct OnboardingGuideView: View {
    let language: AppLanguage
    var onComplete: () -> Void

    @State private var currentSlide = 0
    @State private var hoverNext = false

    private var slides: [OBSlide] { OBSlide.all(for: language) }
    private var isLast: Bool { currentSlide == slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Slide area
            ZStack {
                ForEach(slides.indices, id: \.self) { i in
                    if i == currentSlide {
                        OBSlideView(slide: slides[i], language: language)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id(currentSlide)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentSlide)

            // Controls
            VStack(spacing: 18) {
                // Dot indicator
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == currentSlide ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: i == currentSlide ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentSlide)
                    }
                }

                Button {
                    if isLast {
                        onComplete()
                    } else {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            currentSlide += 1
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(isLast
                             ? "Get Started".localized(language)
                             : "Next".localized(language))
                        Image(systemName: isLast ? "checkmark" : "arrow.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 210, height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 4)
                    .scaleEffect(hoverNext ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hoverNext)
                }
                .buttonStyle(.plain)
                .onHover { hoverNext = $0 }
            }
            .padding(.bottom, 36)
        }
        .environment(\.layoutDirection, language == .hebrew ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Slide Model

struct OBSlide: Identifiable {
    let id: Int
    let headline: String
    let body: String
    let illustration: AnyView

    static func all(for lang: AppLanguage) -> [OBSlide] {
        [
            OBSlide(id: 0,
                    headline: "Remember Every Window".localized(lang),
                    body: "Save your window layout with one click and restore it in seconds.".localized(lang),
                    illustration: AnyView(OBIllustrationSave())),
            OBSlide(id: 1,
                    headline: "Live Layout Preview".localized(lang),
                    body: "See a real-time minimap of every open window across all your screens.".localized(lang),
                    illustration: AnyView(OBIllustrationLive())),
            OBSlide(id: 2,
                    headline: "Automatic Restoration".localized(lang),
                    body: "Reconnect a monitor or open an app — your layout snaps back instantly.".localized(lang),
                    illustration: AnyView(OBIllustrationRestore())),
            OBSlide(id: 3,
                    headline: "Settings Controls".localized(lang),
                    body: "Customize triggers, Desktop Toggle (Cmd+D), and Notch notifications in Settings.".localized(lang),
                    illustration: AnyView(OBIllustrationSettingsGuide())),
            OBSlide(id: 4,
                    headline: "Make It Yours".localized(lang),
                    body: "Choose a theme colour, language, and Liquid Glass interface — all in Settings.".localized(lang),
                    illustration: AnyView(OBIllustrationCustomize())),
        ]
    }
}

struct OBSlideView: View {
    let slide: OBSlide
    let language: AppLanguage

    @State private var settingsActiveIndex = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if slide.id == 3 {
                OBIllustrationSettingsGuide(activeIndex: settingsActiveIndex)
                    .frame(width: 300, height: 180)
                    .liquidGlass(cornerRadius: 20, style: .card)
                    .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 8)
            } else {
                slide.illustration
                    .frame(width: 300, height: 180)
                    .liquidGlass(cornerRadius: 20, style: .card)
                    .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 8)
            }

            VStack(spacing: 10) {
                Text(slide.headline)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                if slide.id == 3 {
                    Text(getSettingsDescription(for: settingsActiveIndex, lang: language))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 390)
                        .id(settingsActiveIndex) // triggers transition/animation when index changes
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                } else {
                    Text(slide.body)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 390)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .onAppear {
            if slide.id == 3 {
                timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        settingsActiveIndex = (settingsActiveIndex + 1) % 4
                    }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func getSettingsDescription(for index: Int, lang: AppLanguage) -> String {
        switch index {
        case 0:
            return "Restores window layouts automatically when you plug/unplug monitors or open apps.".localized(lang)
        case 1:
            return "Press Cmd+D to hide all windows and show desktop. Press again to restore them.".localized(lang)
        case 2:
            return "Shows an elegant pill-shaped alert sliding out from your screen notch when layouts restore.".localized(lang)
        case 3:
            return "Filters log verbosity. Use 'Necessary' to minimize logging, or 'Verbose' for troubleshooting.".localized(lang)
        default:
            return ""
        }
    }
}

// MARK: - Illustrations

struct OBIllustrationSave: View {
    @State private var saved = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .frame(width: 230, height: 134)

            obWin(x: -58, y: -18, w: 95, h: 72, tint: .accentColor, show: saved)
            obWin(x: 58, y: -14, w: 82, h: 62, tint: .blue, show: saved)
            obWin(x: 0, y: 38, w: 104, h: 48, tint: .purple, show: saved)

            if saved {
                VStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                    Text("Saved")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                .transition(.scale.combined(with: .opacity))
                .offset(x: 88, y: -52)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.5)) {
                saved = true
            }
        }
    }

    @ViewBuilder
    func obWin(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, tint: Color, show: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tint.opacity(show ? 0.6 : 0.18))
            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(tint.opacity(show ? 0.9 : 0.3), lineWidth: 0.75) }
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4), value: show)
    }
}

struct OBIllustrationLive: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .frame(width: 210, height: 130)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    obCell(.accentColor, 72, 42)
                    obCell(.blue, 64, 42)
                }
                HStack(spacing: 4) {
                    obCell(.purple, 52, 36)
                    obCell(.orange, 58, 36)
                    obCell(.green, 26, 36)
                }
            }

            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.35 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                Text("LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
            }
            .offset(x: 78, y: -54)
        }
        .onAppear { pulse = true }
    }

    func obCell(_ color: Color, _ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color.opacity(0.38))
            .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(color.opacity(0.65), lineWidth: 0.5) }
            .frame(width: w, height: h)
    }
}

struct OBIllustrationRestore: View {
    @State private var connected = false
    @State private var flash = false

    var body: some View {
        HStack(spacing: 18) {
            obMonitor(tint: .accentColor, lit: connected)
            Image(systemName: "bolt.fill")
                .font(.system(size: 24))
                .foregroundStyle(flash ? .yellow : Color.primary.opacity(0.25))
                .scaleEffect(flash ? 1.25 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.6), value: flash)
            obMonitor(tint: .blue, lit: connected)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.7)) { connected = true }
            withAnimation(.easeInOut(duration: 0.22).delay(1.0)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { flash = false }
            }
        }
    }

    @ViewBuilder
    func obMonitor(tint: Color, lit: Bool) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .frame(width: 84, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(lit ? 0.5 : 0.12))
                        .frame(width: 64, height: 38)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(lit ? tint.opacity(0.8) : Color.primary.opacity(0.18), lineWidth: 1)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: lit)
            Image(systemName: "display")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct OBIllustrationCustomize: View {
    @State private var sel = 0
    @State private var ticker: Timer?
    let swatches: [Color] = [.accentColor, .purple, .blue, .green, .orange, .pink]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                ForEach(swatches.indices, id: \.self) { i in
                    Circle()
                        .fill(swatches[i])
                        .frame(width: sel == i ? 30 : 20, height: sel == i ? 30 : 20)
                        .shadow(color: swatches[i].opacity(0.55), radius: sel == i ? 8 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: sel)
                }
            }

            HStack(spacing: 8) {
                ForEach([("EN", true), ("עב", false)], id: \.0) { (label, active) in
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 36, height: 24)
                        .background(active ? Color.accentColor : Color.primary.opacity(0.1))
                        .foregroundStyle(active ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .onAppear {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
                withAnimation { sel = (sel + 1) % swatches.count }
            }
        }
        .onDisappear { ticker?.invalidate() }
    }
}

struct OBIllustrationSettingsGuide: View {
    var activeIndex: Int = 0
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        VStack(spacing: 5) {
            obSettingRow(
                icon: "bolt.fill",
                color: .orange,
                title: "Auto-Restore".localized(appLanguage),
                subtitle: "Triggers on display connect or app open".localized(appLanguage),
                isActive: activeIndex == 0
            )
            
            obSettingRow(
                icon: "keyboard",
                color: .purple,
                title: "Desktop Toggle".localized(appLanguage),
                subtitle: "Cmd+D to hide or show all windows".localized(appLanguage),
                isActive: activeIndex == 1
            )
            
            obSettingRow(
                icon: "capsule.inset.filled",
                color: .pink,
                title: "Notch Alerts".localized(appLanguage),
                subtitle: "Pill notifications for layout events".localized(appLanguage),
                isActive: activeIndex == 2
            )

            obSettingRow(
                icon: "list.bullet.rectangle.portrait",
                color: .blue,
                title: "Activity Log Level".localized(appLanguage),
                subtitle: "Filter which events appear in the log".localized(appLanguage),
                isActive: activeIndex == 3
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    func obSettingRow(icon: String, color: Color, title: String, subtitle: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if icon == "list.bullet.rectangle.portrait" {
                // A mini picker / dropdown look
                Text(isActive ? "Verbose".localized(appLanguage) : "Necessary".localized(appLanguage))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // A mini toggle switch
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 22, height: 12)
                    .overlay(alignment: isActive ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .padding(1)
                            .shadow(radius: 0.5)
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
            }
        }
        .scaleEffect(isActive ? 1.02 : 1.0)
    }
}
