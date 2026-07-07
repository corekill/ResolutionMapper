import AppKit
import IOKit.hidsystem

enum RemoteMediaAction: String {
    case playPause
    case next
    case previous
    case mute
    case volumeUp
    case volumeDown
}

enum MediaKeyController {
    static func perform(_ action: RemoteMediaAction) {
        switch action {
        case .playPause:
            postAuxiliaryKey(NX_KEYTYPE_PLAY)
        case .next:
            postAuxiliaryKey(NX_KEYTYPE_NEXT)
        case .previous:
            postAuxiliaryKey(NX_KEYTYPE_PREVIOUS)
        case .mute:
            postAuxiliaryKey(NX_KEYTYPE_MUTE)
        case .volumeUp:
            postAuxiliaryKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            postAuxiliaryKey(NX_KEYTYPE_SOUND_DOWN)
        }
    }

    private static func postAuxiliaryKey(_ key: Int32) {
        postAuxiliaryKey(key, isDown: true)
        postAuxiliaryKey(key, isDown: false)
    }

    private static func postAuxiliaryKey(_ key: Int32, isDown: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let state = isDown ? 0xA : 0xB
        let data1 = (Int(key) << 16) | (state << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
