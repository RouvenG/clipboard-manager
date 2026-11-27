import AppKit
import SwiftUI

/// Borderless panels refuse key status by default; the shelf needs it for the search field.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ShelfController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    let model: ShelfViewModel
    private(set) var panel: ShelfPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    var onOpenSettings: () -> Void = {}
    var isVisible: Bool { panel?.isVisible ?? false }

    static let height: CGFloat = 340

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.model = ShelfViewModel(store: store)
        super.init()
        model.onPaste = { [weak self] item, plain in self?.paste(item, plainText: plain) }
        model.onPasteText = { [weak self] text, item in self?.paste(text: text, derivedFrom: item) }
        model.onCopy = { [weak self] item in self?.copy(item) }
        model.onClose = { [weak self] in self?.hide() }
        model.onOpenSettings = { [weak self] in
            self?.hide()
            self?.onOpenSettings()
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }
        model.resetForShow()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let inset: CGFloat = 8
            panel.setFrame(NSRect(x: visible.minX + inset, y: visible.minY + inset,
                                  width: visible.width - inset * 2, height: Self.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: Actions

    private func paste(_ item: ClipItem, plainText: Bool) {
        PasteService.write(item, plainText: plainText)
        monitor.skipCurrentChange()
        store.markUsed(item)
        hide()
        sendPaste()
    }

    private func paste(text: String, derivedFrom item: ClipItem) {
        PasteService.write(text: text)
        monitor.skipCurrentChange()
        let snapshot = ClipSnapshot(kind: LinkDetector.link(in: text) != nil ? .link : .text,
                                    text: text, codeLanguage: CodeDetector.language(of: text))
        store.record(snapshot, sourceBundleID: item.sourceBundleID, sourceAppName: item.sourceAppName)
        hide()
        sendPaste()
    }

    private func copy(_ item: ClipItem) {
        PasteService.write(item, plainText: false)
        monitor.skipCurrentChange()
        store.markUsed(item)
        hide()
    }

    private func sendPaste() {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            return
        }
        // Only re-activate when the target app lost focus (e.g. Settings was open); the non-activating
        // panel normally leaves it frontmost.
        if let previousApp, NSWorkspace.shared.frontmostApplication?.processIdentifier != previousApp.processIdentifier {
            previousApp.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PasteService.postPasteKeystroke()
        }
    }

    // MARK: Panel

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: Self.height),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let hosting = NSHostingView(rootView: ShelfView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        #if DEBUG
        NSLog("ClipShelf: shelf resigned key, frontmost app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        #endif
        hide()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
