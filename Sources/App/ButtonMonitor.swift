import Foundation

/// Watches the learned button and reports presses. For UAC buttons the hub also undoes the
/// button's own effect (e.g. keeps headphone monitoring as it was), so a press only triggers the action.
final class ButtonMonitor {
    var onPress: (() -> Void)?
    var onConnected: ((MicDevice?) -> Void)?

    private let button: LearnedButton
    private let suppressOriginal: Bool
    private var hub: SignalHub?
    private var lastFire: TimeInterval = 0

    init(button: LearnedButton, suppressOriginal: Bool) {
        self.button = button
        self.suppressOriginal = suppressOriginal
    }

    func start() {
        let hub = SignalHub(scope: .only(button.device))
        if suppressOriginal, case .uacMute = button.signal { hub.holdSignal = button.signal }
        hub.onDevicesChanged = { [weak self] mics in self?.onConnected?(mics.first?.device) }
        hub.onEvent = { [weak self] e in self?.handle(e) }
        hub.start()
        self.hub = hub
    }

    func stop() {
        hub?.stop()
        hub = nil
    }

    private func handle(_ e: SignalEvent) {
        guard hub != nil, e.key.signal == button.signal else { return }
        switch e.key.signal {
        case .uacMute:
            fire(at: e.time)
        case .hid:
            if let idle = button.idleValue {
                // press/release button: react to leaving the rest value
                if e.value != idle && (e.previous == nil || e.previous == idle) { fire(at: e.time) }
            } else {
                fire(at: e.time)
            }
        }
    }

    private func fire(at time: TimeInterval) {
        guard time - lastFire > 0.3 else { return }
        lastFire = time
        log.info("press")
        onPress?()
    }
}
