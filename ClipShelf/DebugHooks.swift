#if DEBUG
import AppKit

/// Debug builds only: lets scripts drive the shelf without screen recording or Accessibility, e.g.
/// `Scripts/debug-command.swift show`. Commands arrive as distributed notifications.
final class DebugHooks {
    static let notificationName = Notification.Name("io.github.rouveng.clipshelf.debug")

    private let shelf: ShelfController
    private var observer: NSObjectProtocol?

    init(shelf: ShelfController) {
        self.shelf = shelf
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { self?.handle(command) }
        }
    }

    private func handle(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        let model = shelf.model

        switch parts.first {
        case "show": shelf.show()
        case "hide": shelf.hide()
        case "type": model.activeQuery += argument
        case "key": sendKey(argument)
        case "snapshot": snapshot(to: argument)
        case "state": writeState(to: argument)
        default: NSLog("ClipShelf debug: unknown command \(command)")
        }
    }

    /// `key:<keyCode>[,cmd][,shift]`
    private func sendKey(_ spec: String) {
        let tokens = spec.split(separator: ",").map(String.init)
        guard let code = tokens.first.flatMap(UInt16.init) else { return }
        var flags: NSEvent.ModifierFlags = []
        if tokens.contains("cmd") { flags.insert(.command) }
        if tokens.contains("shift") { flags.insert(.shift) }
        let characters = tokens.first { $0.hasPrefix("char=") }.map { String($0.dropFirst(5)) } ?? ""
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: shelf.panel?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ) else { return }
        _ = shelf.model.handleKey(event)
    }

    private func snapshot(to path: String) {
        guard let view = shelf.panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func writeState(to path: String) {
        let model = shelf.model
        let state: [String: Any] = [
            "visible": shelf.isVisible,
            "mode": "\(model.mode)",
            "query": model.query,
            "filter": model.filter.rawValue,
            "tab": model.title(of: model.tab),
            "selectedIndex": model.selectedIndex,
            "items": model.visibleItems.prefix(12).map { "\($0.kind.rawValue): \(($0.text ?? "<image>").prefix(60))" },
            "menu": model.mode == .transforms ? model.visibleTransforms.map(\.name) : model.visibleBoards.map(\.name),
            "menuIndex": model.menuIndex,
            "status": model.status ?? "",
            "pasteboard": NSPasteboard.general.string(forType: .string) ?? "",
            "accessibility": AccessibilityPermission.isGranted,
            "pasteboardAccess": PasteboardAccess.description,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
