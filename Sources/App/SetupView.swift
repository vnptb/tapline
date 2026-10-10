import SwiftUI

extension Color {
    static let brand = Color(red: 0.87, green: 0.42, blue: 0.26)
    static let brandLight = Color(red: 0.96, green: 0.64, blue: 0.49)
    static let brandDark = Color(red: 0.69, green: 0.25, blue: 0.15)
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            StepDots(step: model.step)
                .padding(.top, 18)
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .learn: LearnStep(model: model)
                case .action: ActionStep(model: model)
                case .permission: PermissionStep(model: model)
                case .done: DoneStep(model: model)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(model.step)
        }
        .frame(width: 520, height: 660)
        .background(Background())
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.step)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepLayout(
            title: L("Your mic button, now a remote for AI"),
            subtitle: L("Teach the app to hear the button on your USB microphone. Then one press starts dictation in Claude or ChatGPT, or works as any shortcut you choose.")
        ) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 148, height: 148)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        } footer: {
            PrimaryButton(L("Get started")) { model.begin() }
            Text(L("Takes less than a minute."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LearnStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepLayout(title: title, subtitle: subtitle) {
            VStack(spacing: 14) {
                Orb(mode: orbMode, pulse: presses)
                if case .listening = model.learnPhase {
                    PressDots(count: Learner.requiredPresses, filled: presses)
                } else {
                    PressDots(count: Learner.requiredPresses, filled: presses).hidden()
                }
            }
        } footer: {
            switch model.learnPhase {
            case .found:
                PrimaryButton(L("Continue")) { model.confirmButton() }
            case .failed:
                PrimaryButton(L("Try again")) { model.retryLearning() }
            default:
                PrimaryButton(L("Continue")) {}.disabled(true).opacity(0)
            }
        }
    }

    private var presses: Int {
        switch model.learnPhase {
        case .listening(let n): return n
        case .found: return Learner.requiredPresses
        default: return 0
        }
    }

    private var orbMode: Orb.Mode {
        switch model.learnPhase {
        case .calibrating: return .waiting
        case .listening: return .listening
        case .found: return .success
        case .failed: return .failure
        }
    }

    private var title: String {
        switch model.learnPhase {
        case .calibrating: return L("Hands off the mic for a second")
        case .listening: return String(format: L("Press the mic button %d times"), Learner.requiredPresses)
        case .found: return L("Got it — button recognized")
        case .failed(.noMicrophone): return L("No USB microphone found")
        case .failed(.noSignal): return L("Couldn't hear the button")
        case .failed(.missedPresses): return L("Not quite three presses")
        }
    }

    private var subtitle: String {
        switch model.learnPhase {
        case .calibrating:
            return L("Learning what the microphone does when nobody touches it.")
        case .listening:
            return L("Take your time, about a second between presses. A mute button, a monitoring button or a press on the volume knob will do.")
        case .found(let button):
            if case .uacMute = button.signal, button.undoesOriginal != false {
                return String(format: L("Found the button on %@. While the app is on, a press runs your action instead of its usual job."), button.device.name)
            }
            return String(format: L("Found the button on %@. A press runs your action, and the button keeps its usual job too."), button.device.name)
        case .failed(.noMicrophone):
            return L("Connect the microphone with a USB cable and try again. Bluetooth microphones don't work.")
        case .failed(.noSignal):
            return L("This button seems to work only inside the microphone and never tells the computer it was pressed. Try another button or the knob.")
        case .failed(.missedPresses):
            return L("The app noticed the button, but not three separate presses. Press it again, about a second apart.")
        }
    }
}

private struct ActionStep: View {
    @ObservedObject var model: SetupModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(L("What should the button do?"))
                    .font(.system(size: 24, weight: .bold))
                Text(L("You can change it any time from the menu bar."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 30)
            .padding(.bottom, 20)

            Scrolling(enabled: !isSnapshot) {
                VStack(spacing: 10) {
                    ForEach(sections, id: \.0) { title, actions in
                        SectionTitle(title)
                        ForEach(actions) { action in card(action) }
                    }
                    SectionTitle(L("Your own"))
                    ForEach(model.customActions) { action in card(action) }
                    if model.editingCustom {
                        CustomActionEditor(model: model)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        AddCard().onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.editingCustom = true }
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            }

            VStack {
                PrimaryButton(L("Continue")) { model.confirmAction() }
                    .disabled(model.editingCustom)
            }
            .padding(.vertical, 24)
        }
    }
}

extension ActionStep {
    var sections: [(String, [ButtonAction])] {
        [(L("Voice and AI"), Presets.ai), (L("Mute in calls"), Presets.calls)]
    }

    func card(_ action: ButtonAction) -> some View {
        ActionCard(action: action, selected: action.id == model.actionID && !model.editingCustom)
            .onTapGesture { model.select(action.id) }
            .contextMenu {
                if action.id.hasPrefix("custom.") {
                    Button(L("Delete"), role: .destructive) { model.remove(action.id) }
                }
            }
    }
}

private struct SectionTitle: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.leading, 4)
    }
}

private struct PermissionStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepLayout(
            title: model.hasKeyboardAccess ? L("Permission granted") : String(format: L("Allow %@ to press keys"), Bundle.main.appName),
            subtitle: model.hasKeyboardAccess
                ? L("Everything is in place.")
                : String(format: L("To run “%1$@”, %2$@ presses a keyboard shortcut for you. macOS allows this only with your permission: turn on %2$@ under Privacy & Security → Accessibility."),
                         model.selectedAction.title, Bundle.main.appName)
        ) {
            Orb(mode: model.hasKeyboardAccess ? .success : .waiting, pulse: 0, symbol: "keyboard")
        } footer: {
            if model.hasKeyboardAccess {
                PrimaryButton(L("Continue")) { model.goToDone() }
            } else {
                PrimaryButton(L("Open System Settings")) { model.requestAccess() }
                Text(String(format: L("%@ is already in the list but this doesn't work? Remove it with “−” and allow it again."), Bundle.main.appName))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button { model.goToDone() } label: {
                    Text(L("Skip for now"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        StepLayout(
            title: model.testPresses > 0 ? L("Works") : L("All set"),
            subtitle: model.testPresses > 0
                ? String(format: L("From now on the button runs “%@”. The app lives in the menu bar: change the action there, or give the button its old job back."), model.selectedAction.title)
                : L("Press the button on the microphone to check.")
        ) {
            Orb(mode: model.testPresses > 0 ? .success : .listening, pulse: model.testPresses)
        } footer: {
            PrimaryButton(L("Finish")) { model.finish() }
        }
    }
}

// MARK: - Building blocks

private struct StepLayout<Visual: View, Footer: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var visual: Visual
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            visual
                .frame(height: 300)
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            Spacer(minLength: 16)
            VStack(spacing: 12) { footer }
                .padding(.bottom, 32)
        }
    }
}

private struct StepDots: View {
    var step: SetupModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i <= current ? Color.brand : Color.primary.opacity(0.12))
                    .frame(width: i == current ? 22 : 8, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
        .opacity(step == .welcome ? 0 : 1)
    }

    private var current: Int {
        switch step {
        case .welcome, .learn: return 0
        case .action: return 1
        case .permission: return 2
        case .done: return 3
        }
    }
}

private struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 200)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brand)
        .keyboardShortcut(.defaultAction)
    }
}

/// The big round mic that listens, pulses on every press and turns into a check mark.
struct Orb: View {
    enum Mode { case waiting, listening, success, failure }

    var mode: Mode
    var pulse: Int
    var symbol = "mic.fill"

    @State private var bumped = false

    var body: some View {
        ZStack {
            if mode == .listening || mode == .waiting {
                Ripples(speed: mode == .listening ? 1 : 0.45)
            }
            Circle()
                .fill(fill)
                .frame(width: 136, height: 136)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: shadow.opacity(0.35), radius: 18, y: 10)
            Image(systemName: currentSymbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 250, height: 250)
        .scaleEffect(bumped ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bumped)
        .animation(.easeInOut(duration: 0.3), value: mode)
        .onChange(of: pulse) {
            guard pulse > 0 else { return }
            bumped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { bumped = false }
        }
    }

    private var currentSymbol: String {
        switch mode {
        case .success: return "checkmark"
        case .failure: return "exclamationmark"
        default: return symbol
        }
    }

    private var fill: LinearGradient {
        switch mode {
        case .success:
            return LinearGradient(colors: [Color(red: 0.38, green: 0.80, blue: 0.47), Color(red: 0.18, green: 0.62, blue: 0.33)],
                                  startPoint: .top, endPoint: .bottom)
        case .failure:
            return LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.brandLight, .brand, .brandDark], startPoint: .top, endPoint: .bottom)
        }
    }

    private var shadow: Color {
        switch mode {
        case .success: return .green
        case .failure: return .black
        default: return .brand
        }
    }
}

private struct Ripples: View {
    var speed: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed
            ZStack {
                ForEach(0..<3) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.brand.opacity(0.45 * (1 - p)), lineWidth: 2)
                        .frame(width: 136 + 110 * p, height: 136 + 110 * p)
                }
            }
        }
    }
}

private struct PressDots: View {
    var count: Int
    var filled: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { i in
                ZStack {
                    Circle()
                        .fill(i < filled ? Color.brand : Color.primary.opacity(0.1))
                    if i < filled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 18, height: 18)
                .scaleEffect(i < filled ? 1 : 0.78)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: filled)
            }
        }
    }
}

private struct ActionCard: View {
    var action: ButtonAction
    var selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppGlyph(bundleID: Presets.iconBundleID(action))
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(Presets.detail(action))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            KeyBadge(text: badge)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(selected ? Color.brand : Color.secondary.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.brand.opacity(0.10) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.brand.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var badge: String {
        switch action.kind {
        case let .shortcut(keyCode, modifiers, _): return KeyNames.shortcut(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers))
        case .capsLock: return "⇪"
        case .url: return "URL"
        }
    }
}

private struct AddCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Your own action"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L("Any keyboard shortcut, in any app"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .contentShape(Rectangle())
    }
}

private struct CustomActionEditor: View {
    @ObservedObject var model: SetupModel
    @State private var title = ""
    @State private var keyCode: UInt16?
    @State private var flags: CGEventFlags = []
    @State private var appBundleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Your own action"))
                .font(.system(size: 14, weight: .semibold))

            LabeledRow(L("Name")) {
                TextField(L("e.g. Wispr Flow"), text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledRow(L("Shortcut")) {
                ShortcutField(keyCode: $keyCode, flags: $flags)
                    .frame(height: 28)
            }
            LabeledRow(L("App")) {
                HStack(spacing: 8) {
                    if let appBundleID {
                        AppGlyph(bundleID: appBundleID, size: 20)
                        Text(ActionRunner.appName(appBundleID) ?? appBundleID)
                            .lineLimit(1)
                    } else {
                        Text(L("Whatever app is in front"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(appBundleID == nil ? L("Choose…") : L("Change…")) { chooseApp() }
                    if appBundleID != nil {
                        Button {
                            appBundleID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L("Cancel")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.editingCustom = false }
                }
                Button(L("Add")) {
                    guard let keyCode else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        model.addCustom(title: title, keyCode: keyCode, flags: flags, appBundleID: appBundleID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(keyCode == nil)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.7), lineWidth: 1.5)
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Choose")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            appBundleID = id
            if title.isEmpty { title = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        }
    }
}

private struct LabeledRow<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            content
        }
    }
}

private struct AppGlyph: View {
    var bundleID: String?
    var size: CGFloat = 34

    var body: some View {
        if let bundleID, let icon = ActionRunner.appIcon(bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: size, height: size)
                .overlay(Image(systemName: "keyboard").font(.system(size: size * 0.42)).foregroundStyle(.secondary))
        }
    }
}

private struct KeyBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct Scrolling<Content: View>: View {
    var enabled: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if enabled {
            ScrollView { content }
        } else {
            VStack { content; Spacer(minLength: 0) }
        }
    }
}

private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

private struct Background: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.brand.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: UnitPoint(x: 0.5, y: 0.22), startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}
