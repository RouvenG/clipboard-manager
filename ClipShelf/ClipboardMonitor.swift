import AppKit

/// Polls `NSPasteboard.general.changeCount` (there is no change notification) and records new clips.
/// Reading `changeCount` and `types` does not read contents, so it never triggers the macOS pasteboard privacy alert.
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let preferences: Preferences
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general, store: HistoryStore, preferences: Preferences = .shared) {
        self.pasteboard = pasteboard
        self.store = store
        self.preferences = preferences
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after ClipShelf writes to the pasteboard itself.
    func skipCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard !preferences.isCapturePaused else { return }

        let source = sourceApplication()
        if let bundleID = source.bundleID, preferences.excludedBundleIDs.contains(bundleID) { return }

        guard let snapshot = PasteboardReader.snapshot(from: pasteboard) else { return }
        store.record(snapshot, sourceBundleID: source.bundleID, sourceAppName: source.name)
    }

    private func sourceApplication() -> (bundleID: String?, name: String?) {
        // nspasteboard.org convention: apps may name themselves as the source.
        if let declared = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")), !declared.isEmpty {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: declared)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            return (declared, name)
        }
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
