import Carbon.HIToolbox

/// System-wide hotkey via Carbon `RegisterEventHotKey`, which needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    private(set) var shortcut: Shortcut?

    init(action: @escaping () -> Void) {
        self.id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.actions[id]?() }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }

    /// Replaces the current registration. Returns false (and registers nothing) when macOS refuses it, e.g. when
    /// this app already holds it. Clashes with other apps go unreported: whichever registered it may win.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5348), id: id) // "CLSH"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("ClipShelf: could not register \(shortcut.displayString) (\(status))")
            hotKeyRef = nil
            return false
        }
        self.shortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        shortcut = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
