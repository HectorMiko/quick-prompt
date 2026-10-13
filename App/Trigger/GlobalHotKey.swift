import Carbon.HIToolbox

/// System-wide shortcut through `RegisterEventHotKey`. No extra permission needed.
@MainActor
final class GlobalHotKey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// `modifiers` uses Carbon flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    init(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.action = action
    }

    /// Returns `false` when the shortcut is already taken by another app.
    func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard handlerStatus == noErr else {
            Log.trigger.error("InstallEventHandler failed: \(handlerStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5150_5254), id: 1) // "QPRT"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            Log.trigger.error("RegisterEventHotKey failed: \(status)")
            return false
        }
        Log.trigger.info("Palette hot key registered")
        return true
    }
}
