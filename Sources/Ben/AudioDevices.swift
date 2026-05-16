import CoreAudio
import Foundation

struct InputDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

/// Live list of available audio input devices, with a system-default reading.
/// Updates automatically when the user plugs in / removes / switches devices.
@MainActor
@Observable
final class AudioDevices {
    private(set) var inputs: [InputDevice] = []
    private(set) var systemDefault: AudioDeviceID = 0

    init() {
        refresh()
        startListening()
    }

    func refresh() {
        inputs = Self.enumerateInputs()
        systemDefault = Self.defaultInputID() ?? 0
    }

    var systemDefaultName: String {
        inputs.first(where: { $0.id == systemDefault })?.name ?? "Default"
    }

    // MARK: - Enumeration

    private static func enumerateInputs() -> [InputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInputStreams(id) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "Unknown"
            let uid  = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? ""
            return InputDevice(id: id, name: name, uid: uid)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name as String
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        return AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &size, &id) == noErr ? id : nil
    }

    // MARK: - Volume (hardware input gain, persists in system settings)

    static func inputVolume(for deviceID: AudioDeviceID) -> Float? {
        if let v = readVolume(deviceID, element: kAudioObjectPropertyElementMain) { return v }
        // Some devices don't expose master; fall back to channel 1.
        return readVolume(deviceID, element: 1)
    }

    static func setInputVolume(_ volume: Float, for deviceID: AudioDeviceID) {
        let clamped = max(0, min(1, volume))
        if writeVolume(deviceID, element: kAudioObjectPropertyElementMain, value: clamped) { return }
        _ = writeVolume(deviceID, element: 1, value: clamped)
        _ = writeVolume(deviceID, element: 2, value: clamped)
    }

    private static func readVolume(_ id: AudioDeviceID, element: UInt32) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  element
        )
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func writeVolume(_ id: AudioDeviceID, element: UInt32, value: Float) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  element
        )
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = value
        let size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, size, &v) == noErr
    }

    // MARK: - Listener (device list changes)

    private func startListening() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block)
    }
}
