import CoreAudio
import Foundation
import IOKit.hid
import os

let log = Logger(subsystem: "io.github.vnptb.tapline", category: "button")

/// A connected USB audio device.
struct ConnectedMic: Hashable {
    var locationID: UInt32
    var device: MicDevice
}

/// One signal of one connected device.
struct SignalKey: Hashable {
    var locationID: UInt32
    var signal: ButtonSignal
}

struct SignalEvent {
    var key: SignalKey
    var device: MicDevice
    var value: Int
    /// The value before this change; nil for the first HID report of its kind (nothing to compare with).
    var previous: Int?
    var time: TimeInterval
}

/// Watches everything a microphone button can change: Mute controls of USB Audio Class
/// Feature Units (polled, because the firmware flips them silently) and HID input reports.
/// Callbacks arrive on the main queue.
final class SignalHub {
    enum Scope {
        case allMics
        case only(MicDevice)
    }

    var onEvent: ((SignalEvent) -> Void)?
    /// First value read for each UAC control (lets the learner restore what it changed).
    var onInitialValue: ((SignalKey, Int) -> Void)?
    var onDevicesChanged: (([ConnectedMic]) -> Void)?

    /// When set, flips of this UAC control are handled here, on the polling queue: the control is
    /// put back to its resting value right away and the flip is reported as one press. Flips made
    /// by macOS itself (another app changing mute or monitoring) are adopted, not reported.
    var holdSignal: ButtonSignal?

    private let scope: Scope
    private let queue = DispatchQueue(label: "tapline.signals")
    private var timer: DispatchSourceTimer?
    private var lastScan = Date.distantPast

    // queue-confined
    private var opened: [UInt32: OpenMic] = [:]
    private var rest: [SignalKey: Int] = [:]
    private var pending: [SignalKey: (value: Int, since: TimeInterval)] = [:]

    // main-confined
    private var hidDevices: [UInt64: HIDMic] = [:]   // by registry entry ID
    private var rejectedHID = Set<UInt64>()
    private var mics: [ConnectedMic] = []
    private var stopped = false

    private final class OpenMic {
        let mic: ConnectedMic
        let registryID: UInt64
        let handle: UnsafeMutableRawPointer
        var controls: [mb_mute_control]
        var last: [Int]
        var failures = 0
        var audio: CoreAudioWatch?

        init(mic: ConnectedMic, registryID: UInt64, handle: UnsafeMutableRawPointer, controls: [mb_mute_control]) {
            self.mic = mic
            self.registryID = registryID
            self.handle = handle
            self.controls = controls
            self.last = Array(repeating: -1, count: controls.count)
        }
    }

    private final class HIDMic {
        let device: IOHIDDevice
        let mic: ConnectedMic
        let buffer: UnsafeMutablePointer<UInt8>
        var last: [UInt32: [UInt8]] = [:]

        init(device: IOHIDDevice, mic: ConnectedMic, bufferSize: Int) {
            self.device = device
            self.mic = mic
            buffer = .allocate(capacity: bufferSize)
        }

        deinit { buffer.deallocate() }
    }

    init(scope: Scope) {
        self.scope = scope
    }

    deinit { stop() }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {
            for o in opened.values { close(o) }
            opened.removeAll()
        }
        let closeHID = {
            self.stopped = true
            for h in self.hidDevices.values { Self.closeHID(h) }
            self.hidDevices.removeAll()
        }
        if Thread.isMainThread { closeHID() } else { DispatchQueue.main.sync(execute: closeHID) }
    }

    /// Puts UAC mute controls back to the given values where they differ now. Synchronous.
    /// Returns, for each control that needed it, whether the mic accepted the write.
    @discardableResult
    func restoreMutes(_ values: [SignalKey: Int]) -> [SignalKey: Bool] {
        queue.sync {
            var result: [SignalKey: Bool] = [:]
            for (key, value) in values {
                guard case let .uacMute(interface, unit, channel, version) = key.signal,
                      let o = opened[key.locationID] else { continue }
                let control = mb_mute_control(interfaceNumber: interface, unitID: unit, channel: channel, uacVersion: version)
                let now = Int(mb_get_mute(o.handle, control))
                guard now >= 0, now != value else { continue }
                mb_set_mute(o.handle, control, Int32(value))
                let after = Int(mb_get_mute(o.handle, control))
                log.info("restore unit \(unit) ch \(channel): \(now) -> \(value), reads \(after)")
                if let i = o.controls.firstIndex(where: { Self.same($0, control) }) { o.last[i] = after }
                result[key] = after == value
            }
            return result
        }
    }

    // MARK: Polling (queue)

    private func tick() {
        if Date().timeIntervalSince(lastScan) >= 1 {
            lastScan = Date()
            rescan()
        }
        let now = Date().timeIntervalSinceReferenceDate
        var dead: [UInt32] = []
        for o in opened.values {
            var anyRead = false
            for (i, c) in o.controls.enumerated() {
                let v = Int(mb_get_mute(o.handle, c))
                if v < 0 { continue }
                anyRead = true
                let key = SignalKey(locationID: o.mic.locationID,
                                    signal: .uacMute(interface: c.interfaceNumber, unit: c.unitID,
                                                     channel: c.channel, uacVersion: c.uacVersion))
                let old = o.last[i]
                o.last[i] = v
                if key.signal == holdSignal {
                    hold(key, value: v, first: old < 0, in: o, control: c, now: now)
                } else if old < 0 {
                    DispatchQueue.main.async { self.onInitialValue?(key, v) }
                } else if old != v {
                    log.info("uac change \(o.mic.device.name, privacy: .public) unit \(c.unitID) ch \(c.channel): \(old) -> \(v)")
                    emit(SignalEvent(key: key, device: o.mic.device, value: v, previous: old, time: now))
                }
            }
            o.failures = anyRead || o.controls.isEmpty ? 0 : o.failures + 1
            // The device stopped answering (e.g. it was reset): drop it so the next scan reopens it.
            if o.failures >= 10 { dead.append(o.mic.locationID) }
        }
        for loc in dead {
            if let o = opened.removeValue(forKey: loc) { close(o) }
        }
    }

    /// The learned button's control: keep it at rest and report each flip as a press.
    private func hold(_ key: SignalKey, value v: Int, first: Bool, in o: OpenMic, control c: mb_mute_control, now: TimeInterval) {
        if first || rest[key] == nil {
            rest[key] = v
            return
        }
        guard let r = rest[key] else { return }
        if let p = pending[key] {
            // Wait one more poll: macOS reports its own changes a moment after making them.
            guard now - p.since >= 0.08 else { return }
            pending[key] = nil
            if let changed = o.audio?.lastChange, changed >= p.since - 0.5 {
                log.info("unit \(c.unitID) changed by software: \(r) -> \(v), not a press")
                rest[key] = v
                return
            }
            if v != r {
                mb_set_mute(o.handle, c, Int32(r))
                let after = Int(mb_get_mute(o.handle, c))
                if let i = o.controls.firstIndex(where: { Self.same($0, c) }) { o.last[i] = after }
                // Some mics refuse certain writes (the NT-USB Mini won't let the host switch monitoring on);
                // then the new state becomes the resting one.
                if after >= 0 && after != r { rest[key] = after }
                log.info("press on unit \(c.unitID): put back \(v) -> \(r), reads \(after)")
            }
            emit(SignalEvent(key: key, device: o.mic.device, value: p.value, previous: r, time: p.since))
        } else if v != r {
            pending[key] = (v, now)
        }
    }

    private func emit(_ event: SignalEvent) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    private func rescan() {
        var buf = [mb_device_info](repeating: mb_device_info(), count: 32)
        let n = min(32, Int(mb_list_audio_devices(&buf, 32)))
        let all = buf.prefix(n).map { (mic: ConnectedMic(locationID: $0.locationID, device: Self.micDevice($0)),
                                       registryID: $0.registryID) }
        let found = select(all)

        let wanted = Dictionary(found.map { ($0.mic.locationID, $0.registryID) }, uniquingKeysWith: { a, _ in a })
        for (loc, o) in opened where wanted[loc] != o.registryID {
            close(o)
            opened[loc] = nil
        }
        for f in found where opened[f.mic.locationID] == nil {
            guard let h = mb_open(f.registryID) else { continue }
            var controls = [mb_mute_control](repeating: mb_mute_control(), count: 64)
            let count = Int(mb_list_mute_controls(h, &controls, 64))
            let o = OpenMic(mic: f.mic, registryID: f.registryID, handle: h, controls: Array(controls.prefix(count)))
            if holdSignal != nil { o.audio = CoreAudioWatch(mic: f.mic.device, queue: queue) }
            opened[f.mic.locationID] = o
        }

        let mics = found.map(\.mic)
        DispatchQueue.main.async {
            guard !self.stopped else { return }
            let changed = mics != self.mics
            self.mics = mics
            // HID interfaces can enumerate a moment after the audio ones, so sync on every scan.
            self.syncHID()
            if changed { self.onDevicesChanged?(mics) }
        }
    }

    /// Which connected devices to watch. For one learned mic, never more than one device:
    /// writes must not reach a different mic of the same model.
    private func select(_ all: [(mic: ConnectedMic, registryID: UInt64)]) -> [(mic: ConnectedMic, registryID: UInt64)] {
        switch scope {
        case .allMics:
            return all
        case .only(let target):
            let candidates = all.filter { target.matches($0.mic.device) }
            if candidates.count > 1, let loc = target.locationID,
               let same = candidates.first(where: { $0.mic.locationID == loc }) {
                return [same]
            }
            return Array(candidates.prefix(1))
        }
    }

    private func close(_ o: OpenMic) {
        o.audio?.stop()
        mb_close(o.handle)
        for key in rest.keys where key.locationID == o.mic.locationID { rest[key] = nil }
        for key in pending.keys where key.locationID == o.mic.locationID { pending[key] = nil }
    }

    // MARK: HID (main)

    private func syncHID() {
        var present = Set<UInt64>()
        for mic in mics {
            let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
            matching[kIOPropertyMatchKey] = [kIOHIDVendorIDKey: Int(mic.device.vendorID),
                                             kIOHIDProductIDKey: Int(mic.device.productID)]
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS else { continue }
            while case let service = IOIteratorNext(it), service != 0 {
                defer { IOObjectRelease(service) }
                // Same physical device as this audio function? (Two mics of one model share VID:PID.)
                let loc = IORegistryEntryCreateCFProperty(service, kIOHIDLocationIDKey as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber
                if let loc, loc.uint32Value != mic.locationID { continue }
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(service, &id)
                present.insert(id)
                if hidDevices[id] != nil || rejectedHID.contains(id) { continue }
                if let h = openHID(service, mic: mic) {
                    hidDevices[id] = h
                } else {
                    rejectedHID.insert(id)
                }
            }
            IOObjectRelease(it)
        }
        for (id, h) in hidDevices where !present.contains(id) {
            Self.closeHID(h)
            hidDevices[id] = nil
        }
        rejectedHID.formIntersection(present)
    }

    private static func closeHID(_ h: HIDMic) {
        IOHIDDeviceUnscheduleFromRunLoop(h.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(h.device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Only vendor-defined and telephony interfaces. Keyboards, pointers, media keys and anything
    /// else stay closed, so macOS never asks for Input Monitoring.
    private static func isButtonInterface(_ device: IOHIDDevice) -> Bool {
        var pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        if pairs.isEmpty,
           let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int,
           let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int {
            pairs = [[kIOHIDDeviceUsagePageKey: page, kIOHIDDeviceUsageKey: usage]]
        }
        guard !pairs.isEmpty else { return false }
        return pairs.allSatisfy { p in
            let page = p[kIOHIDDeviceUsagePageKey] ?? 0
            return page >= 0xFF00 || page == kHIDPage_Telephony
        }
    }

    private func openHID(_ service: io_service_t, mic: ConnectedMic) -> HIDMic? {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service), Self.isButtonInterface(device),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        let size = max(64, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64)
        let h = HIDMic(device: device, mic: mic, bufferSize: size)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, h.buffer, size, { context, _, sender, _, reportID, report, length in
            guard let context, let sender else { return }
            let hub = Unmanaged<SignalHub>.fromOpaque(context).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            hub.handleReport(device: device, reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return h
    }

    private func handleReport(device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
        guard !stopped, let h = hidDevices.values.first(where: { $0.device === device }) else { return }
        let old = h.last[reportID]
        h.last[reportID] = bytes
        let now = Date().timeIntervalSinceReferenceDate
        for (i, b) in bytes.enumerated() {
            let prev: Int? = old.map { i < $0.count ? Int($0[i]) : 0 }
            guard prev != Int(b) else { continue }
            log.debug("hid change report \(reportID) byte \(i): \(prev ?? -1) -> \(b)")
            let key = SignalKey(locationID: h.mic.locationID, signal: .hid(reportID: reportID, byteIndex: i))
            onEvent?(SignalEvent(key: key, device: h.mic.device, value: Int(b), previous: prev, time: now))
        }
    }

    // MARK: Helpers

    private static func micDevice(_ info: mb_device_info) -> MicDevice {
        var info = info
        let name = withUnsafeBytes(of: &info.name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let serial = withUnsafeBytes(of: &info.serial) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return MicDevice(vendorID: info.vendorID, productID: info.productID, serial: serial,
                         name: name.isEmpty ? String(format: "USB %04X:%04X", info.vendorID, info.productID) : name,
                         locationID: info.locationID)
    }

    private static func same(_ a: mb_mute_control, _ b: mb_mute_control) -> Bool {
        a.interfaceNumber == b.interfaceNumber && a.unitID == b.unitID && a.channel == b.channel
    }
}

/// Notices when macOS changes the mic's mute or monitoring itself (an app, Audio MIDI Setup).
/// A press on the mic's own button changes the hardware without CoreAudio knowing, so a CoreAudio
/// notification right around a flip means the flip came from software.
final class CoreAudioWatch {
    private(set) var lastChange: TimeInterval?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(mic: MicDevice, queue: DispatchQueue) {
        for id in Self.devices(matching: mic) {
            for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyPlayThru] {
                for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput, kAudioDevicePropertyScopePlayThrough] {
                    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                             mElement: kAudioObjectPropertyElementWildcard)
                    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                        self?.lastChange = Date().timeIntervalSinceReferenceDate
                    }
                    if AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr {
                        listeners.append((id, address, block))
                    }
                }
            }
        }
    }

    func stop() {
        for (id, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, nil, block)
        }
        listeners.removeAll()
    }

    private static func devices(matching mic: MicDevice) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            guard transport(id) == kAudioDeviceTransportTypeUSB else { return false }
            let uid = string(id, kAudioDevicePropertyDeviceUID) ?? ""
            let name = string(id, kAudioObjectPropertyName) ?? ""
            return (!mic.serial.isEmpty && uid.contains(mic.serial)) || name == mic.name
        }
    }

    private static func transport(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
