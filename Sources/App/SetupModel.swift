import AppKit
import Combine

/// State of the setup window. Drives the learner, the action choice and the final check.
final class SetupModel: ObservableObject {
    enum Step: Int {
        case welcome, learn, action, permission, done
    }

    @Published var step: Step
    @Published var learnPhase: Learner.Phase = .calibrating
    @Published var learned: LearnedButton?
    @Published var actionID: String
    @Published var customActions: [ButtonAction]
    @Published var editingCustom = false
    @Published var hasKeyboardAccess = Permissions.keyboardGranted
    @Published var testPresses = 0

    var onClose: (() -> Void)?

    private let learner = Learner()
    private var testMonitor: ButtonMonitor?
    private var accessTimer: Timer?
    private let live: Bool

    init(start: Step, live: Bool = true) {
        let settings = Settings.shared
        step = start
        learned = settings.button
        actionID = settings.actionID
        customActions = settings.customActions
        self.live = live
        learner.onPhase = { [weak self] phase in self?.learnPhaseChanged(phase) }
        if live && start == .learn { learner.start() }
        if live && start == .done { startTest() }
    }

    var actions: [ButtonAction] { Presets.all + customActions }
    var selectedAction: ButtonAction { actions.first { $0.id == actionID } ?? Presets.claudeDictation }

    // MARK: Navigation

    func begin() {
        step = .learn
        learner.start()
    }

    func retryLearning() {
        learner.start()
    }

    func confirmButton() {
        step = .action
    }

    func confirmAction() {
        Settings.shared.actionID = actionID
        if ActionRunner.needsKeyboardAccess(selectedAction) && !Permissions.keyboardGranted {
            step = .permission
            watchAccess()
        } else {
            goToDone()
        }
    }

    func requestAccess() {
        Permissions.request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        watchAccess()
    }

    func goToDone() {
        accessTimer?.invalidate()
        // Granted while this process was running: restart once so key presses really go through.
        if live && Permissions.relaunchIfStale(arguments: ["--setup-step", "done"]) { return }
        if live { Settings.shared.enabled = true }   // the done screen promises the button now runs the action
        step = .done
        startTest()
    }

    func finish() {
        onClose?()
    }

    func teardown() {
        learner.stop()
        testMonitor?.stop()
        testMonitor = nil
        accessTimer?.invalidate()
    }

    // MARK: Actions

    func select(_ id: String) {
        actionID = id
        editingCustom = false
    }

    func addCustom(title: String, keyCode: UInt16, flags: CGEventFlags, appBundleID: String?) {
        let name = title.trimmingCharacters(in: .whitespaces)
        let action = ButtonAction(id: "custom." + UUID().uuidString, title: name.isEmpty ? L("My action") : name,
                                  kind: .shortcut(keyCode: keyCode, modifiers: flags.rawValue, appBundleID: appBundleID))
        customActions.append(action)
        Settings.shared.customActions = customActions
        select(action.id)
    }

    func remove(_ id: String) {
        customActions.removeAll { $0.id == id }
        Settings.shared.customActions = customActions
        if actionID == id { actionID = Presets.claudeDictation.id }
    }

    // MARK: Private

    private func learnPhaseChanged(_ phase: Learner.Phase) {
        learnPhase = phase
        if case .found(let button) = phase {
            learned = button
            Settings.shared.button = button
            NSSound(named: "Glass")?.play()
        }
    }

    private func watchAccess() {
        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Permissions.keyboardGranted
            if granted != self.hasKeyboardAccess { self.hasKeyboardAccess = granted }
        }
    }

    private func startTest() {
        guard live, let button = learned else { return }
        testMonitor?.stop()
        let monitor = ButtonMonitor(button: button, suppressOriginal: true)
        monitor.onPress = { [weak self] in self?.testPresses += 1 }
        monitor.start()
        testMonitor = monitor
    }
}

extension SetupModel {
    /// Fixed states for rendering screenshots of every step.
    static func preview(_ step: Step, phase: Learner.Phase = .calibrating, presses: Int = 0) -> SetupModel {
        let m = SetupModel(start: step, live: false)
        m.learnPhase = phase
        m.testPresses = presses
        m.hasKeyboardAccess = false
        return m
    }
}
