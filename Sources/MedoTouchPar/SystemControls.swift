import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio
import IOKit.ps
import TBPrivate

/// Output volume of the default device through CoreAudio (no permission needed).
enum Volume {
    private static func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static var level: Float {
        get {
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioHardwareServiceGetPropertyData(defaultOutputDevice(), &volumeAddress, 0, nil, &size, &value)
            return value
        }
        set {
            var value = Float32(max(0, min(1, newValue)))
            let device = defaultOutputDevice()
            AudioHardwareServiceSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if value > 0 { setMuted(false, device: device) }
        }
    }

    private static func setMuted(_ muted: Bool, device: AudioDeviceID) {
        var value = UInt32(muted ? 1 : 0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

enum Brightness {
    static var isAvailable: Bool { TBGetBrightness() >= 0 }
    static var level: Float {
        get { max(0, TBGetBrightness()) }
        set { TBSetBrightness(newValue) }
    }
}

enum Battery {
    struct Status { var percent: Int; var charging: Bool; var onAC: Bool }

    static func status() -> Status? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return Status(percent: current * 100 / maxCap, charging: charging, onAC: onAC)
        }
        return nil
    }

    static func symbol(for s: Status) -> String {
        if s.charging { return "battery.100.bolt" }
        switch s.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Synthesised keyboard / media-key events. Posting requires Accessibility.
enum KeySender {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func cgFlags(from raw: UInt) -> CGEventFlags {
        let m = NSEvent.ModifierFlags(rawValue: raw)
        var f = CGEventFlags()
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.function) { f.insert(.maskSecondaryFn) }
        return f
    }

    static func press(keyCode: UInt16, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func press(_ shortcut: Shortcut) {
        press(keyCode: shortcut.keyCode, flags: cgFlags(from: shortcut.modifiers))
    }

    /// Same encoding the hardware media keys use (NSSystemDefined subtype 8).
    static func media(_ key: MediaKey) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int((key.keyType << 16) | Int32(state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
