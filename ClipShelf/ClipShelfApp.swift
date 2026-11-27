import AppKit
import ServiceManagement
import SwiftUI

@main
struct ClipShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and shelf panel are AppKit; SwiftUI needs at least one scene.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var shelf: ShelfController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var pruneTimer: Timer?
    private let preferences = Preferences.shared
    #if DEBUG
    private var debugHooks: DebugHooks?
    #endif

    private var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        store = HistoryStore()
        monitor = ClipboardMonitor(store: store)
        shelf = ShelfController(store: store, monitor: monitor)
        shelf.onOpenSettings = { [weak self] in self?.openSettings() }

        store.prune(retentionDays: preferences.retentionDays)
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.prune(retentionDays: self.preferences.retentionDays)
            }
        }

        ScriptRunner.seedExampleIfNeeded()
        monitor.start()
        hotKey = HotKey { [weak self] in self?.shelf.toggle() }
        setUpStatusItem()
        #if DEBUG
        debugHooks = DebugHooks(shelf: shelf)
        #endif

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipShelf")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openShelf() { shelf.show() }

    @objc private func togglePause() { preferences.isCapturePaused.toggle() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "ClipShelf Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store, preferences: preferences))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Items in pinboards are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { store.clearHistory() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open Shelf", action: #selector(openShelf), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(open)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: preferences.isCapturePaused ? "Resume Capturing" : "Pause Capturing",
                               action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pause)
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: ""))
        if !AccessibilityPermission.isGranted {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Grant Accessibility to Paste…", action: #selector(grantAccessibility), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit ClipShelf", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
    }

    @objc private func grantAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
