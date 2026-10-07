import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// This matters: unlike `NSEvent.addGlobalMonitorForEvents`, the Carbon hot key
/// API needs **no Accessibility or Input Monitoring permission**, so Pookie can
/// offer an escape hatch ("hide the cat") without nagging you on first launch.
final class GlobalHotKey {
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var handlerInstalled = false
    private static var eventHandlerRef: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private let identifier: UInt32

    /// Carbon modifiers. `controlKey | optionKey` is a deliberately obscure
    /// combination that will not collide with anything you actually use.
    static let controlOption: UInt32 = UInt32(controlKey | optionKey)

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        let identifier = Self.nextIdentifier
        Self.nextIdentifier += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x504F4F4B), id: identifier) // 'POOK'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            Log.info("hotkey registration failed (keyCode \(keyCode), status \(status))")
            return nil
        }

        self.identifier = identifier
        self.hotKeyRef = ref
        Self.registry[identifier] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.registry[identifier] = nil
    }

    fileprivate static func action(for identifier: UInt32) -> (() -> Void)? {
        registry[identifier]
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            pookieHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            Log.info("failed to install hotkey event handler (status \(status))")
        }
    }
}

/// Carbon requires a bare C function pointer, so the dispatch table lives in
/// `GlobalHotKey.registry` and this trampoline has no captures.
private func pookieHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    if let action = GlobalHotKey.action(for: hotKeyID.id) {
        action()
    }
    return noErr
}

/// Virtual key codes, named so the call sites read like prose.
enum KeyCode {
    static let h: UInt32 = UInt32(kVK_ANSI_H)
    static let p: UInt32 = UInt32(kVK_ANSI_P)
    static let d: UInt32 = UInt32(kVK_ANSI_D)
    static let r: UInt32 = UInt32(kVK_ANSI_R)
    static let t: UInt32 = UInt32(kVK_ANSI_T)
    static let m: UInt32 = UInt32(kVK_ANSI_M)
}
