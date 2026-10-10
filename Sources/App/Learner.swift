import Foundation

/// Finds the microphone button: the user presses it a few times, and the signal that changed
/// in step with those presses is the button.
final class Learner {
    enum Failure: Equatable {
        case noMicrophone
        /// Nothing the computer can read changed.
        case noSignal
        /// Something changed, but not three clear presses.
        case missedPresses
    }

    enum Phase: Equatable {
        case calibrating
        case listening(presses: Int)
        case found(LearnedButton)
        case failed(Failure)
    }

    static let requiredPresses = 3
    private static let calibration: TimeInterval = 1.2
    private static let burstGap: TimeInterval = 0.35
    private static let releaseWithin: TimeInterval = 0.7
    private static let settle: TimeInterval = 1.0
    private static let timeout: TimeInterval = 25

    var onPhase: ((Phase) -> Void)?
    var onDevices: (([ConnectedMic]) -> Void)?

    private var hub: SignalHub?
    private var timer: Timer?
    private var startedAt = Date()
    private var listeningSince: Date?
    private var mics: [ConnectedMic] = []

    private var noisy = Set<SignalKey>()
    private var initial: [SignalKey: Int] = [:]
    private var touched = Set<SignalKey>()          // UAC controls that changed while learning
    private var events: [SignalKey: [SignalEvent]] = [:]
    private var sawPress = false
    private var reportedPresses = -1
    private var winner: LearnedButton?
    private var restored: [SignalKey: Bool] = [:]

    private(set) var phase: Phase = .calibrating {
        didSet {
            guard phase != oldValue else { return }
            log.info("learner: \(String(describing: self.phase), privacy: .public)")
            onPhase?(phase)
        }
    }

    func start() {
        stop()
        noisy.removeAll()
        initial.removeAll()
        touched.removeAll()
        events.removeAll()
        sawPress = false
        reportedPresses = -1
        listeningSince = nil
        winner = nil
        startedAt = Date()
        phase = .calibrating

        let hub = SignalHub(scope: .allMics)
        hub.onInitialValue = { [weak self] key, value in self?.initial[key] = value }
        hub.onEvent = { [weak self] e in self?.record(e) }
        hub.onDevicesChanged = { [weak self] mics in
            self?.mics = mics
            self?.onDevices?(mics)
        }
        hub.start()
        self.hub = hub
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.evaluate() }
    }

    /// Ends learning by any path (found, failed, window closed) and puts back what the presses toggled.
    func stop() {
        timer?.invalidate()
        timer = nil
        guard let hub else { return }
        restored = hub.restoreMutes(restoreTargets())
        hub.stop()
        self.hub = nil
    }

    private func record(_ e: SignalEvent) {
        if case .uacMute = e.key.signal { touched.insert(e.key) }
        if listeningSince == nil {
            if case .uacMute = e.key.signal {
                // A Mute control doesn't flip by itself: the user pressed early. Keep waiting until hands are off.
                sawPress = true
                startedAt = Date()
            } else {
                noisy.insert(e.key)   // HID data that moves on its own
            }
            return
        }
        guard !noisy.contains(e.key) else { return }
        sawPress = true
        events[e.key, default: []].append(e)
    }

    /// Changes grouped into presses: one group per burst of activity.
    private func bursts(_ list: [SignalEvent]) -> [[SignalEvent]] {
        var groups: [[SignalEvent]] = []
        var last = -Double.infinity
        for e in list {
            if e.time - last > Self.burstGap { groups.append([]) }
            groups[groups.count - 1].append(e)
            last = e.time
        }
        return groups
    }

    /// For HID buttons that report press and release: the value at rest. nil = the value toggles per press.
    private func restValue(_ list: [SignalEvent]) -> Int? {
        guard let rest = list.last?.value else { return nil }
        // Every move away from rest must come back within a short time.
        var leftAt: TimeInterval?
        var leaves = 0
        for e in list {
            if e.value != rest, e.previous == nil || e.previous == rest {
                leftAt = e.time
                leaves += 1
            } else if e.value == rest {
                guard let t = leftAt, e.time - t <= Self.releaseWithin else { return nil }
                leftAt = nil
            }
        }
        return leaves > 0 && leftAt == nil ? rest : nil
    }

    private func presses(_ key: SignalKey, _ list: [SignalEvent]) -> Int {
        if case .hid = key.signal, let rest = restValue(list) {
            return list.filter { $0.value != rest && ($0.previous == nil || $0.previous == rest) }.count
        }
        return bursts(list).count
    }

    private func evaluate() {
        let now = Date()
        guard let since = listeningSince else {
            if now.timeIntervalSince(startedAt) >= Self.calibration {
                if mics.isEmpty {
                    finish(.failed(.noMicrophone))
                } else {
                    listeningSince = now
                    phase = .listening(presses: 0)
                }
            }
            return
        }

        // A signal that changes far more often than the user presses is not a button.
        var counts: [SignalKey: Int] = [:]
        for (key, list) in events {
            let n = presses(key, list)
            if n > Self.requiredPresses + 3 {
                noisy.insert(key)
                events[key] = nil
            } else {
                counts[key] = n
            }
        }

        let shown = min(Self.requiredPresses, counts.values.max() ?? 0)
        if shown != reportedPresses {
            reportedPresses = shown
            phase = .listening(presses: shown)
        }

        let ready = counts.filter { key, n in
            n >= Self.requiredPresses && now.timeIntervalSinceReferenceDate - (events[key]?.last?.time ?? 0) >= Self.settle
        }
        if let best = ready.keys.sorted(by: { rank($0, counts[$0]!) < rank($1, counts[$1]!) }).first,
           let list = events[best], let first = list.first {
            var device = first.device
            device.locationID = best.locationID
            let idle: Int? = { if case .hid = best.signal { return restValue(list) } else { return nil } }()
            winner = LearnedButton(device: device, signal: best.signal, idleValue: idle)
            finish(.found(winner!))
            return
        }

        if now.timeIntervalSince(since) >= Self.timeout {
            finish(.failed(mics.isEmpty ? .noMicrophone : (sawPress ? .missedPresses : .noSignal)))
        }
    }

    /// Lower is better: exactly the requested number of presses, then UAC (its effect can be undone), then HID.
    private func rank(_ key: SignalKey, _ presses: Int) -> Int {
        let exact = presses == Self.requiredPresses ? 0 : 10
        if case .uacMute = key.signal { return exact }
        return exact + 1
    }

    /// Learning toggled whatever the button controls (e.g. headphone monitoring); put back only that.
    /// With a winner: its own control, plus controls on the same mic that flipped together with it.
    /// Without one: every control that flipped during learning.
    private func restoreTargets() -> [SignalKey: Int] {
        var keys = touched
        if let w = winner {
            let wKey = SignalKey(locationID: w.device.locationID ?? 0, signal: w.signal)
            let wBursts = bursts(events[wKey] ?? []).map { $0[0].time }
            keys = keys.filter { key in
                guard key.locationID == wKey.locationID else { return false }
                if key == wKey { return true }
                let starts = bursts(events[key] ?? []).map { $0[0].time }
                return starts.count == wBursts.count && zip(starts, wBursts).allSatisfy { abs($0 - $1) < 0.12 }
            }
        }
        var targets: [SignalKey: Int] = [:]
        for key in keys {
            if let v = initial[key] ?? events[key]?.first?.previous { targets[key] = v }
        }
        return targets
    }

    private func finish(_ result: Phase) {
        stop()
        if case .found(var button) = result, case .uacMute = button.signal {
            // Putting back what the presses toggled is also the test of whether the mic accepts the write.
            button.undoesOriginal = restored[SignalKey(locationID: button.device.locationID ?? 0, signal: button.signal)]
            phase = .found(button)
            return
        }
        phase = result
    }
}
