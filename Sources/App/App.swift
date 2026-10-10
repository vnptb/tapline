import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var monitor: ButtonMonitor?
    private var connectedMic: MicDevice?
    private var setupWindow: NSWindow?
    private var setupModel: SetupModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        let args = CommandLine.arguments
        if settings.button == nil {
            openSetup(at: .welcome)
        } else if let i = args.firstIndex(of: "--setup-step"), i + 1 < args.count, args[i + 1] == "done" {
            openSetup(at: .done)   // relaunched after the permission was granted during setup
        } else {
            restartMonitor()
            if ActionRunner.needsKeyboardAccess(settings.action) && !Permissions.keyboardGranted {
                Permissions.request()
            }
        }
    }

    // MARK: Monitor

    private func restartMonitor() {
        monitor?.stop()
        monitor = nil
        connectedMic = nil
        defer { updateIcon() }
        guard setupWindow == nil, settings.enabled, let button = settings.button else { return }
        let m = ButtonMonitor(button: button, suppressOriginal: true)
        m.onPress = { [weak self] in
            guard let self else { return }
            ActionRunner.run(self.settings.action)
        }
        m.onConnected = { [weak self] device in
            self?.connectedMic = device
            self?.updateIcon()
        }
        m.start()
        monitor = m
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let button = settings.button {
            let status = connectedMic != nil
                ? String(format: L("%@ — connected"), button.device.name)
                : String(format: L("%@ — not connected"), button.device.name)
            menu.addItem(disabled(status))
            menu.addItem(.separator())

            menu.addItem(disabled(L("The mic button")))
            menu.addItem(item(String(format: L("Runs “%@”"), settings.action.title), #selector(enable), checked: settings.enabled))
            menu.addItem(item(L("Does its usual job"), #selector(disable), checked: !settings.enabled))
            menu.addItem(.separator())

            let actions = NSMenuItem(title: L("Action"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let sections: [(String, [ButtonAction])] = [
                (L("Voice and AI"), Presets.ai),
                (L("Mute in calls"), Presets.calls),
                (L("Your own"), settings.customActions),
            ]
            for (title, actions) in sections where !actions.isEmpty {
                if sub.numberOfItems > 0 { sub.addItem(.separator()) }
                sub.addItem(.sectionHeader(title: title))
                for action in actions {
                    let i = item(action.title, #selector(chooseAction(_:)), checked: action.id == settings.actionID)
                    i.representedObject = action.id
                    sub.addItem(i)
                }
            }
            sub.addItem(.separator())
            sub.addItem(item(L("Add your own…"), #selector(openActions)))
            actions.submenu = sub
            menu.addItem(actions)

            if ActionRunner.needsKeyboardAccess(settings.action) && !Permissions.keyboardGranted {
                menu.addItem(item(L("⚠️ Allow key presses…"), #selector(openAccessibility)))
            }
            menu.addItem(item(L("Set up the button again…"), #selector(openLearn)))
        } else {
            menu.addItem(item(L("Set up the mic button…"), #selector(openWelcome)))
        }

        menu.addItem(.separator())
        menu.addItem(item(L("Open at login"), #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(item(L("Quit"), #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = checked ? .on : .off
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func updateIcon() {
        let symbol: String
        if settings.button == nil {
            symbol = "mic.badge.plus"
        } else {
            symbol = settings.enabled ? "mic.fill" : "mic"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: Bundle.main.appName)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = settings.button != nil && settings.enabled && connectedMic == nil
    }

    @objc private func enable() {
        settings.enabled = true
        restartMonitor()
    }

    @objc private func disable() {
        settings.enabled = false
        restartMonitor()
    }

    @objc private func chooseAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.actionID = id
        if ActionRunner.needsKeyboardAccess(settings.action) && !Permissions.keyboardGranted {
            Permissions.request()
        }
    }

    @objc private func openWelcome() { openSetup(at: .welcome) }
    @objc private func openLearn() { openSetup(at: .learn) }
    @objc private func openActions() { openSetup(at: .action, editingCustom: true) }

    @objc private func openAccessibility() {
        Permissions.request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Setup window

    private func openSetup(at step: SetupModel.Step, editingCustom: Bool = false) {
        if let window = setupWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        // While setting up, the regular monitor must not fire actions.
        monitor?.stop()
        monitor = nil

        let model = SetupModel(start: step)
        model.editingCustom = editingCustom
        model.onClose = { [weak self] in self?.setupWindow?.close() }
        setupModel = model

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.delegate = self
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === setupWindow else { return }
        setupModel?.teardown()
        setupModel = nil
        setupWindow = nil
        restartMonitor()
    }
}

extension Bundle {
    var appName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Tapline"
    }
}

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: args[i + 1])) }
            return
        }
        if let i = args.firstIndex(of: "--check-access"), i + 1 < args.count {
            let report = "postEvent=\(CGPreflightPostEventAccess()) axTrusted=\(AXIsProcessTrusted())\n"
            try? report.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
            return
        }
        if let i = args.firstIndex(of: "--selftest") {
            SelfTest.run(seconds: i + 1 < args.count ? Double(args[i + 1]) ?? 30 : 30)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
