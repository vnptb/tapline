import AppKit
import Carbon.HIToolbox

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum Presets {
    static let claudeBundle = "com.anthropic.claudefordesktop"
    /// ChatGPT, Codex and Work are one desktop app since July 2026.
    static let chatGPTBundle = "com.openai.codex"

    static let claudeDictation = ButtonAction(
        id: "claude.dictation", title: L("Dictation in Claude"),
        kind: .shortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: CGEventFlags.maskCommand.rawValue, appBundleID: claudeBundle))

    static let claudeVoice = ButtonAction(
        id: "claude.voice", title: L("Claude voice input anywhere"), kind: .capsLock)

    static let chatGPTVoice = ButtonAction(
        id: "chatgpt.voice", title: L("Voice chat in ChatGPT"),
        kind: .shortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: CGEventFlags([.maskControl, .maskShift]).rawValue,
                        appBundleID: chatGPTBundle))

    /// ChatGPT's global "Single-tap shortcut" has no default; the user sets it to this combo.
    static let chatGPTDictation = ButtonAction(
        id: "chatgpt.dictation", title: L("ChatGPT dictation anywhere"),
        kind: .shortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskShift]).rawValue,
                        appBundleID: nil))

    static let ai: [ButtonAction] = [claudeDictation, claudeVoice, chatGPTVoice, chatGPTDictation]

    /// Mute in call apps. The app comes forward for a moment, then the user is taken back.
    static let calls: [ButtonAction] = [
        callMute("zoom", "Zoom", "us.zoom.xos", kVK_ANSI_A, [.maskCommand, .maskShift]),
        callMute("teams", "Microsoft Teams", "com.microsoft.teams2", kVK_ANSI_M, [.maskCommand, .maskShift]),
        callMute("slack", "Slack", "com.tinyspeck.slackmacgap", kVK_Space, [.maskCommand, .maskShift]),
        callMute("discord", "Discord", "com.hnc.Discord", kVK_ANSI_M, [.maskCommand, .maskShift]),
    ]

    static let all: [ButtonAction] = ai + calls

    private static func callMute(_ id: String, _ app: String, _ bundle: String, _ key: Int, _ flags: CGEventFlags) -> ButtonAction {
        ButtonAction(id: "call.\(id)", title: String(format: L("Mute in %@"), app),
                     kind: .shortcut(keyCode: UInt16(key), modifiers: flags.rawValue, appBundleID: bundle),
                     returnFocus: true)
    }

    /// Other bundle IDs the same app has had.
    private static let alternates: [String: [String]] = [
        "com.microsoft.teams2": ["com.microsoft.teams"],
    ]

    /// The bundle ID under which the app is actually installed, or nil if it isn't.
    static func installedBundleID(_ bundleID: String) -> String? {
        ([bundleID] + (alternates[bundleID] ?? [])).first {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    static func isInstalled(_ action: ButtonAction) -> Bool {
        guard let id = iconBundleID(action) else { return true }
        return installedBundleID(id) != nil
    }

    /// One line under the title in the action picker.
    static func detail(_ action: ButtonAction) -> String {
        switch action.id {
        case claudeDictation.id: return L("Opens Claude and starts dictation in the message box")
        case claudeVoice.id: return L("From any app. Set Claude's voice shortcut to Caps Lock first, or the button only toggles Caps Lock")
        case chatGPTVoice.id: return L("Opens ChatGPT and starts a voice chat. Works in Codex too")
        case chatGPTDictation.id: return L("Types into any app. In ChatGPT settings, set the single-tap dictation shortcut to ⌃⌥⇧D")
        default:
            if action.id.hasPrefix("call.") {
                return L("Switches the mic on or off in the call and takes you back to your app")
            }
            return ActionRunner.describe(action)
        }
    }

    /// Whose icon to show next to the action.
    static func iconBundleID(_ action: ButtonAction) -> String? {
        switch action.id {
        case claudeVoice.id: return claudeBundle
        case chatGPTDictation.id: return chatGPTBundle
        default:
            if case let .shortcut(_, _, app) = action.kind { return app }
            return nil
        }
    }
}

enum ActionRunner {
    static func needsKeyboardAccess(_ action: ButtonAction) -> Bool {
        if case .shortcut = action.kind { return true }
        return false
    }

    static func run(_ action: ButtonAction) {
        switch action.kind {
        case let .shortcut(keyCode, modifiers, appBundleID):
            guard Permissions.keyboardGranted else {
                log.info("no Accessibility permission, shortcut not sent")
                Permissions.request()
                NSSound.beep()
                return
            }
            if Permissions.relaunchIfStale() { return }
            let previous = NSWorkspace.shared.frontmostApplication
            let press = { post(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers)) }
            if let appBundleID, let target = Presets.installedBundleID(appBundleID) {
                bringForward(target) {
                    press()
                    if action.returnFocus == true, let previous, previous.bundleIdentifier != target {
                        goBack(to: previous)
                    }
                }
            } else if appBundleID != nil {
                NSSound.beep()   // the app isn't installed
            } else {
                press()
            }
        case .capsLock:
            if mb_toggle_caps_lock() < 0 { NSSound.beep() }
        case .url(let string):
            if let url = URL(string: string) { NSWorkspace.shared.open(url) } else { NSSound.beep() }
        }
    }

    /// Human-readable summary, e.g. "⌘D in Claude".
    static func describe(_ action: ButtonAction) -> String {
        switch action.kind {
        case let .shortcut(keyCode, modifiers, app):
            let keys = KeyNames.shortcut(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers))
            guard let app, let name = appName(app) else { return keys }
            return String(format: L("%@ in %@"), keys, name)
        case .capsLock:
            return "⇪ Caps Lock"
        case .url(let s):
            return s
        }
    }

    static func appName(_ bundleID: String) -> String? {
        guard let id = Presets.installedBundleID(bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func appIcon(_ bundleID: String) -> NSImage? {
        guard let id = Presets.installedBundleID(bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Our app runs in the background, so a shortcut would land in whatever app is in front.
    /// Bring the target app forward first, and never press keys anywhere else.
    private static var waitingForApp = false   // main thread only

    private static func isFront(_ bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func bringForward(_ bundleID: String, then action: @escaping () -> Void) {
        if isFront(bundleID) {
            action()
            return
        }
        guard !waitingForApp else { return }   // a press is already waiting for this app
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSSound.beep()
            return
        }
        waitingForApp = true
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    waitingForApp = false
                    NSSound.beep()
                    return
                }
                waitUntilFront(bundleID, attempts: 30, then: action)
            }
        }
    }

    private static func waitUntilFront(_ bundleID: String, attempts: Int, then action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if isFront(bundleID) {
                // a short pause lets the app's window take keyboard focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    waitingForApp = false
                    if isFront(bundleID) { action() } else { NSSound.beep() }
                }
            } else if attempts > 0 {
                waitUntilFront(bundleID, attempts: attempts - 1, then: action)
            } else {
                waitingForApp = false
                NSSound.beep()
            }
        }
    }

    /// Returns to the app the user was in, once the shortcut has been handled.
    private static func goBack(to app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    private static func post(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

enum KeyNames {
    static func shortcut(keyCode: UInt16, flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        if flags.contains(.maskSecondaryFn) && !isFunctionKey(keyCode) { s += "fn " }
        return s + key(keyCode)
    }

    static func flags(from m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.shift) { f.insert(.maskShift) }
        return f
    }

    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_CapsLock: "⇪",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    private static func isFunctionKey(_ code: UInt16) -> Bool {
        (special[Int(code)] ?? "").hasPrefix("F")
    }

    /// The key's label in an ASCII-capable layout, so ⌘D reads "⌘D" with a Russian layout active too.
    static func key(_ keyCode: UInt16) -> String {
        if let s = special[Int(keyCode)] { return s }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
