import CoreAudio
import Foundation

/// Keeps recording from dragging a Bluetooth headset out of its high-quality
/// A2DP playback profile.
///
/// On macOS, opening *any* input stream on a Bluetooth audio device forces the
/// whole link into the bidirectional HFP/SCO telephony profile. SCO is mono and
/// low-bitrate in both directions, so music playing on the headset collapses to
/// a "louder, grainier, fades-away" mono signal the instant recording starts.
/// `AVAudioRecorder` records from the *system default input device*, so when
/// that default is the Bluetooth headset (macOS routinely auto-selects connected
/// AirPods as input), dictating wrecks the user's music.
///
/// The fix: while recording, temporarily point the default input at a
/// non-Bluetooth mic (preferring the built-in one), then restore it. The
/// headset's input is never opened, so it stays in A2DP and the music is
/// untouched. Non-Bluetooth defaults are left exactly as they were.
enum AudioInputRouter {
    struct InputDevice: Equatable {
        let id: AudioDeviceID
        let transport: UInt32
    }

    /// Classic Bluetooth and Bluetooth LE both suffer the A2DP↔SCO switch.
    static let bluetoothTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeBluetooth,
        kAudioDeviceTransportTypeBluetoothLE,
    ]

    /// The device capture should be redirected to, or `nil` when no redirect is
    /// needed (the default input isn't Bluetooth) or possible (there is no
    /// non-Bluetooth input to fall back to). Pure policy — unit-tested without
    /// audio hardware.
    static func redirectTarget(
        defaultInputTransport: UInt32,
        inputDevices: [InputDevice]
    ) -> AudioDeviceID? {
        guard bluetoothTransports.contains(defaultInputTransport) else { return nil }
        let nonBluetooth = inputDevices.filter { !bluetoothTransports.contains($0.transport) }
        if let builtIn = nonBluetooth.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) {
            return builtIn.id
        }
        return nonBluetooth.first?.id
    }

    // MARK: - Core Audio glue (needs the HAL; not unit-testable)

    /// If the current default input is a Bluetooth device, returns the
    /// non-Bluetooth device to switch to plus the original to restore later.
    /// `nil` means "leave the default input alone."
    static func bluetoothSafeRedirect() -> (target: AudioDeviceID, original: AudioDeviceID)? {
        guard let original = defaultInputDeviceID() else { return nil }
        guard let target = redirectTarget(
            defaultInputTransport: transportType(of: original),
            inputDevices: availableInputDevices()
        ) else { return nil }
        return (target, original)
    }

    @discardableResult
    static func setDefaultInputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &deviceID
        ) == noErr
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    static func availableInputDevices() -> [InputDevice] {
        allDeviceIDs()
            .filter { hasInputChannels($0) }
            .map { InputDevice(id: $0, transport: transportType(of: $0)) }
    }

    /// True when at least one usable microphone (input channel) exists. Used to
    /// surface a clear "no microphone" error before attempting to record.
    static func hasInputDevice() -> Bool {
        !availableInputDevices().isEmpty
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport)
        return status == noErr ? transport : kAudioDeviceTransportTypeUnknown
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// A device is a usable microphone only if it exposes at least one input
    /// channel (output-only devices report a zero-channel input configuration).
    private static func hasInputChannels(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
