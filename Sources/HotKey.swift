import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's RegisterEventHotKey rather than an event tap: this is the one
/// mechanism that works for a background app **without** Accessibility permission,
/// so the shortcut costs the user no system prompt. The trade is that the shortcut is
/// claimed exclusively — while the card is running, no other app receives that combo.
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var sequence: UInt32 = 0

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let identifier: UInt32

    private init(identifier: UInt32) {
        self.identifier = identifier
    }

    /// Registers the shortcut. Returns nil when the system refuses it.
    static func register(keyCode: UInt32,
                         modifiers: UInt32,
                         action: @escaping () -> Void) -> GlobalHotKey? {
        sequence += 1
        let identifier = sequence
        let hotKey = GlobalHotKey(identifier: identifier)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                hotKeyCallback,
                                                1,
                                                &eventType,
                                                nil,
                                                &hotKey.handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: GlobalHotKey.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(keyCode,
                                                modifiers,
                                                hotKeyID,
                                                GetApplicationEventTarget(),
                                                0,
                                                &hotKey.hotKeyRef)
        guard registerStatus == noErr else {
            if let handler = hotKey.handlerRef { RemoveEventHandler(handler) }
            return nil
        }

        actions[identifier] = action
        return hotKey
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        GlobalHotKey.actions[identifier] = nil
    }

    private static let signature: OSType = {
        // 'DKY1'
        let chars: [UInt8] = [0x44, 0x4B, 0x59, 0x31]
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()
}

/// C callback: no captures allowed, so it looks the action up by hot key id.
private let hotKeyCallback: EventHandlerUPP = { _, event, _ in
    guard let event else { return noErr }
    var pressed = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &pressed)
    guard status == noErr, let action = GlobalHotKey.action(for: pressed.id) else { return noErr }
    DispatchQueue.main.async(execute: action)
    return noErr
}

extension GlobalHotKey {
    fileprivate static func action(for identifier: UInt32) -> (() -> Void)? {
        actions[identifier]
    }
}

/// The combo the card uses, named in one place.
enum CardShortcut {
    static let keyCode = UInt32(kVK_ANSI_T)
    static let modifiers = UInt32(cmdKey | optionKey)
    static let description = "⌥⌘T"
}
