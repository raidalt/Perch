import AppKit
import Carbon

var _perchHotkeyAction: (() -> Void)?

private let _perchEventHandlerUPP: EventHandlerUPP = { _, _, _ -> OSStatus in
    _perchHotkeyAction?()
    return noErr
}

final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(action: @escaping () -> Void) {
        unregister()
        _perchHotkeyAction = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            _perchEventHandlerUPP,
            1,
            &eventType,
            UnsafeMutableRawPointer(bitPattern: 0),
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: 0x50524348, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        _perchHotkeyAction = nil
    }
}
