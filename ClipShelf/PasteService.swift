import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteService {
    /// Puts the item on the pasteboard. Plain text drops RTF/HTML and pastes files and links as text.
    static func write(_ item: ClipItem, plainText: Bool, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let pbItem = NSPasteboardItem()
        pbItem.setData(Data(), forType: PasteboardReader.ownWriteType)

        switch item.kind {
        case .image where !plainText:
            if let data = item.imageData {
                pbItem.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation {
                    pbItem.setData(tiff, forType: .tiff)
                }
            }
        case .file where !plainText:
            let items = item.fileURLs.map { url in
                let fileItem = NSPasteboardItem()
                fileItem.setString(url.absoluteString, forType: .fileURL)
                fileItem.setString(url.path, forType: .string)
                return fileItem
            }
            items.first?.setData(Data(), forType: PasteboardReader.ownWriteType)
            pasteboard.writeObjects(items)
            return
        case .link where !plainText:
            if let text = item.text {
                pbItem.setString(text, forType: .string)
                pbItem.setString(text, forType: .URL)
            }
        default:
            if let text = item.text { pbItem.setString(text, forType: .string) }
            if !plainText {
                if let rtf = item.rtfData { pbItem.setData(rtf, forType: .rtf) }
                if let html = item.htmlData { pbItem.setData(html, forType: .html) }
            }
        }
        pasteboard.writeObjects([pbItem])
    }

    static func write(text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let pbItem = NSPasteboardItem()
        pbItem.setString(text, forType: .string)
        pbItem.setData(Data(), forType: PasteboardReader.ownWriteType)
        pasteboard.writeObjects([pbItem])
    }

    /// Synthesizes Cmd+V into the frontmost app. Needs Accessibility permission.
    static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Avoid modifiers the user is still holding (e.g. Shift from Shift+Return) leaking into the paste.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        let keyV = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to Privacy & Security > Accessibility.
    @discardableResult
    static func request() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
