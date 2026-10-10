import AppKit
import SwiftUI

/// `--snapshot <dir>` renders every setup step in light and dark mode to PNG files.
/// Used to review the setup screens without clicking through them.
enum Snapshot {
    @MainActor
    static func render(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sample = LearnedButton(device: MicDevice(vendorID: 0x19f7, productID: 0x15, serial: "", name: "RØDE NT-USB Mini"),
                                   signal: .uacMute(interface: 0, unit: 4, channel: 1, uacVersion: 1), idleValue: nil, undoesOriginal: false)
        let states: [(String, () -> SetupModel)] = [
            ("1-welcome", { .preview(.welcome) }),
            ("2-calibrating", { .preview(.learn, phase: .calibrating) }),
            ("3-listening", { .preview(.learn, phase: .listening(presses: 2)) }),
            ("4-found", { .preview(.learn, phase: .found(sample)) }),
            ("5-failed", { .preview(.learn, phase: .failed(.noSignal)) }),
            ("6-action", { .preview(.action) }),
            ("6b-custom", { .preview(.action) }),
            ("7-permission", { .preview(.permission) }),
            ("8-done", { .preview(.done) }),
            ("9-works", { .preview(.done, presses: 1) }),
        ]
        for (name, make) in states {
            for dark in [false, true] {
                let model = make()
                if name == "6b-custom" { model.editingCustom = true }
                let host = NSHostingView(rootView: SetupView(model: model).environment(\.controlActiveState, .key))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        print("snapshots: \(dir.path)")
    }
}
