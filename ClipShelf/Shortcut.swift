import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags (what `RegisterEventHotKey` takes).
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    static let shelfDefault = Shortcut(keyCode: kVK_ANSI_V, modifiers: cmdKey | optionKey)

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        self.init(keyCode: Int(keyCode), modifiers: modifiers)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// Needs ⌘, ⌥ or ⌃ so it can't swallow normal typing. Function keys work on their own.
    var isValid: Bool {
        let hasModifier = modifiers & (cmdKey | optionKey | controlKey) != 0
        return hasModifier || Self.functionKeys[keyCode] != nil
    }

    var displayString: String { Self.modifierSymbols(modifierFlags) + keyName }

    var keyName: String {
        if let name = Self.specialKeys[keyCode] ?? Self.functionKeys[keyCode] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// For `NSMenuItem.keyEquivalent`; empty when the key has no menu representation.
    var menuKeyEquivalent: String {
        if let scalar = Self.menuKeys[keyCode] { return String(Character(UnicodeScalar(scalar)!)) }
        if Self.specialKeys[keyCode] != nil || Self.functionKeys[keyCode] != nil { return "" }
        return Self.character(for: keyCode)?.lowercased() ?? ""
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let menuKeys: [Int: Int] = [
        kVK_Space: 0x20, kVK_Return: 0x0D, kVK_Tab: 0x09, kVK_Delete: 0x08,
        kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
        kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
        kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
        kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
        kVK_F9: NSF9FunctionKey, kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
    ]

    /// The character the key types in the current keyboard layout, so Z shows as Y on a German layout.
    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { raw in
            UCKeyTranslate(
                raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }
}
