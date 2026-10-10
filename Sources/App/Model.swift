import Foundation

/// A USB microphone, identified so that it is found again after replugging or reboot.
struct MicDevice: Codable, Hashable {
    var vendorID: UInt16
    var productID: UInt16
    var serial: String
    var name: String
    /// The USB port it was learned on. Only used to tell apart two mics of the same model without serial numbers.
    var locationID: UInt32? = nil

    func matches(_ other: MicDevice) -> Bool {
        vendorID == other.vendorID && productID == other.productID && (serial.isEmpty || serial == other.serial)
    }
}

/// What the microphone's button changes when pressed.
enum ButtonSignal: Codable, Hashable {
    /// A Mute control of a USB Audio Class Feature Unit that the firmware flips on every press.
    case uacMute(interface: UInt8, unit: UInt8, channel: UInt8, uacVersion: UInt8)
    /// A byte in a HID input report the microphone sends when the button is pressed.
    case hid(reportID: UInt32, byteIndex: Int)
}

struct LearnedButton: Codable, Hashable {
    var device: MicDevice
    var signal: ButtonSignal
    /// For HID buttons that report press and release: the byte value at rest. nil = the value toggles once per press.
    var idleValue: Int?
    /// Whether the app can undo the button's own effect. Some mics refuse the write (the NT-USB Mini does);
    /// then the button keeps its usual job as well, which is fine for a monitoring button. nil = not known.
    var undoesOriginal: Bool? = nil
}

/// What happens when the button is pressed.
struct ButtonAction: Codable, Hashable, Identifiable {
    enum Kind: Codable, Hashable {
        /// Bring `appBundleID` forward (if set) and press a keyboard shortcut.
        case shortcut(keyCode: UInt16, modifiers: UInt64, appBundleID: String?)
        /// Toggle Caps Lock (Claude's global voice input can be bound to it).
        case capsLock
        /// Open a URL, e.g. a deep link of a dictation app.
        case url(String)
    }

    var id: String
    var title: String
    var kind: Kind
    /// After pressing the shortcut in the target app, go back to the app the user was in
    /// (muting a call shouldn't pull you out of your work).
    var returnFocus: Bool? = nil
}

/// Persistent settings.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var button: LearnedButton? {
        get { decode("button") }
        set { encode(newValue, "button") }
    }

    var actionID: String {
        get { defaults.string(forKey: "actionID") ?? Presets.claudeDictation.id }
        set { defaults.set(newValue, forKey: "actionID") }
    }

    var customActions: [ButtonAction] {
        get { decode("customActions") ?? [] }
        set { encode(newValue, "customActions") }
    }

    /// When off, the app leaves the button alone and it does its original job.
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    var allActions: [ButtonAction] { Presets.all + customActions }

    var action: ButtonAction {
        allActions.first { $0.id == actionID } ?? Presets.claudeDictation
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
