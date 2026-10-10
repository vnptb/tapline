import AppKit

/// `--selftest [seconds]` runs learning and then the button monitor in the terminal, printing what happens.
/// Pair it with presses on the real button (or a tool that flips the same control) to test without the UI.
enum SelfTest {
    private static var learner: Learner?
    private static var monitor: ButtonMonitor?

    static func run(seconds: TimeInterval) {
        setvbuf(stdout, nil, _IOLBF, 0)
        _ = NSApplication.shared
        let learner = Learner()
        learner.onDevices = { mics in print("devices: \(mics.map(\.device.name))") }
        learner.onPhase = { phase in
            print("phase: \(phase)")
            switch phase {
            case .found(let button): startMonitor(button)
            case .failed: exit(1)
            default: break
            }
        }
        learner.start()
        self.learner = learner
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            print("selftest: done")
            exit(0)
        }
        RunLoop.main.run()
    }

    private static func startMonitor(_ button: LearnedButton) {
        print("learned: \(button)")
        let m = ButtonMonitor(button: button, suppressOriginal: true)
        m.onConnected = { print("monitor connected: \($0?.name ?? "none")") }
        m.onPress = { print("PRESS") }
        m.start()
        monitor = m
    }
}
