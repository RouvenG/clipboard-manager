import Foundation
import Observation

@Observable
final class Preferences {
    static let shared = Preferences()

    static let defaultExcludedBundleIDs: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal",
    ]

    /// 0 means keep forever.
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }

    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }

    var isCapturePaused: Bool {
        didSet { defaults.set(isCapturePaused, forKey: Keys.isCapturePaused) }
    }

    /// Absolute path to bun, deno or node. Empty means auto-detect.
    var scriptRuntimePath: String {
        didSet { defaults.set(scriptRuntimePath, forKey: Keys.scriptRuntimePath) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.retentionDays: 30,
            Keys.excludedBundleIDs: Self.defaultExcludedBundleIDs,
            Keys.isCapturePaused: false,
            Keys.scriptRuntimePath: "",
        ])
        retentionDays = defaults.integer(forKey: Keys.retentionDays)
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? Self.defaultExcludedBundleIDs
        isCapturePaused = defaults.bool(forKey: Keys.isCapturePaused)
        scriptRuntimePath = defaults.string(forKey: Keys.scriptRuntimePath) ?? ""
    }

    private enum Keys {
        static let retentionDays = "retentionDays"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let isCapturePaused = "isCapturePaused"
        static let scriptRuntimePath = "scriptRuntimePath"
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ClipShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var scriptsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { supportDirectory.appendingPathComponent("History.store") }
}
