#if canImport(Testing)
import Testing
import CoreAudio
@testable import JVoice

/// `redirectTarget` is the pure policy that keeps a Bluetooth headset in its
/// high-quality A2DP playback profile: recording follows the system default
/// input, and opening a Bluetooth device's mic forces the mono HFP/SCO call
/// profile that wrecks any music. These cases exercise that policy without
/// touching real audio hardware.
@Suite("AudioInputRouter redirect policy")
struct AudioInputRouterTests {
    private func device(_ id: AudioDeviceID, _ transport: UInt32) -> AudioInputRouter.InputDevice {
        AudioInputRouter.InputDevice(id: id, transport: transport)
    }

    @Test("A built-in default input is left untouched")
    func builtInDefaultIsLeftAlone() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeBuiltIn,
            inputDevices: [device(1, kAudioDeviceTransportTypeBuiltIn),
                           device(2, kAudioDeviceTransportTypeBluetooth)]
        )
        #expect(target == nil)
    }

    @Test("A wired/USB default input is left untouched")
    func usbDefaultIsLeftAlone() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeUSB,
            inputDevices: [device(1, kAudioDeviceTransportTypeUSB),
                           device(2, kAudioDeviceTransportTypeBuiltIn)]
        )
        #expect(target == nil)
    }

    @Test("A Bluetooth default input redirects to the built-in mic")
    func bluetoothDefaultPrefersBuiltIn() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeBluetooth,
            inputDevices: [device(10, kAudioDeviceTransportTypeBluetooth),
                           device(20, kAudioDeviceTransportTypeUSB),
                           device(30, kAudioDeviceTransportTypeBuiltIn)]
        )
        #expect(target == 30)
    }

    @Test("A Bluetooth default input falls back to any non-Bluetooth mic when no built-in exists")
    func bluetoothDefaultFallsBackToNonBluetooth() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeBluetooth,
            inputDevices: [device(10, kAudioDeviceTransportTypeBluetooth),
                           device(20, kAudioDeviceTransportTypeUSB)]
        )
        #expect(target == 20)
    }

    @Test("No redirect is possible when every input is Bluetooth")
    func allBluetoothCannotBeHelped() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeBluetooth,
            inputDevices: [device(10, kAudioDeviceTransportTypeBluetooth),
                           device(11, kAudioDeviceTransportTypeBluetoothLE)]
        )
        #expect(target == nil)
    }

    @Test("A Bluetooth LE default input is treated like classic Bluetooth")
    func bluetoothLEDefaultRedirects() {
        let target = AudioInputRouter.redirectTarget(
            defaultInputTransport: kAudioDeviceTransportTypeBluetoothLE,
            inputDevices: [device(10, kAudioDeviceTransportTypeBluetoothLE),
                           device(30, kAudioDeviceTransportTypeBuiltIn)]
        )
        #expect(target == 30)
    }
}
#endif
