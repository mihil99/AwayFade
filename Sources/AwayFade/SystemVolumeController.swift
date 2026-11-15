@preconcurrency import CoreAudio
import Foundation

struct AudioOutputInfo: Equatable {
    let id: AudioDeviceID
    let name: String
    let volume: Float
}

@MainActor
final class SystemVolumeController {
    func defaultOutput() -> AudioOutputInfo? {
        guard let deviceID = defaultOutputDeviceID(),
              let volume = readVolume(deviceID: deviceID)
        else { return nil }

        return AudioOutputInfo(
            id: deviceID,
            name: deviceName(deviceID: deviceID) ?? "Unknown output",
            volume: volume
        )
    }

    func readVolume(deviceID: AudioDeviceID) -> Float? {
        if let master = readVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return master
        }

        let channels = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
            .compactMap { readVolume(deviceID: deviceID, element: $0) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    @discardableResult
    func setVolume(_ value: Float, deviceID: AudioDeviceID) -> Bool {
        let clamped = min(max(value, 0), 1)
        if isVolumeSettable(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return writeVolume(clamped, deviceID: deviceID, element: kAudioObjectPropertyElementMain)
        }

        var wroteAny = false
        for element in [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        where isVolumeSettable(deviceID: deviceID, element: element) {
            wroteAny = writeVolume(clamped, deviceID: deviceID, element: element) || wroteAny
        }
        return wroteAny
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func deviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func readVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func isVolumeSettable(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private func writeVolume(
        _ value: Float,
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = volumeAddress(element: element)
        var mutableValue = Float32(value)
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        )
        return status == noErr
    }
}
