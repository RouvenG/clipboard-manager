import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: HistoryStore
    let hotKey: HotKey
    @Bindable var preferences: Preferences

    var body: some View {
        TabView {
            GeneralSettings(preferences: preferences, hotKey: hotKey)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings(preferences: preferences)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            PinboardSettings(store: store)
                .tabItem { Label("Pinboards", systemImage: "pin") }
            ScriptSettings(preferences: preferences)
                .tabItem { Label("Scripts", systemImage: "curlybraces") }
        }
        .padding()
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let hotKey: HotKey
    @State private var shortcutError: String?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    private let retentionOptions: [(String, Int)] = [
        ("1 day", 1), ("7 days", 7), ("30 days", 30), ("90 days", 90), ("1 year", 365), ("Forever", 0),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError { Text(launchError).foregroundStyle(.red).font(.caption) }
                LabeledContent("Open shelf") {
                    HStack {
                        ShortcutRecorder(
                            shortcut: preferences.shelfShortcut,
                            onBegin: { hotKey.unregister() },
                            onEnd: apply)
                        if preferences.shelfShortcut != .shelfDefault {
                            Button("Reset") { apply(.shelfDefault) }
                        }
                    }
                }
                if let shortcutError { Text(shortcutError).foregroundStyle(.red).font(.caption) }
            }
            Section("History") {
                Picker("Keep history for", selection: $preferences.retentionDays) {
                    ForEach(retentionOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                Text("Items in pinboards never expire.").font(.caption).foregroundStyle(.secondary)
                Toggle("Pause capturing", isOn: $preferences.isCapturePaused)
            }
            Section("Permissions") {
                LabeledContent("Accessibility (to paste)") {
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Granted" : "Not granted")
                        if !accessibilityGranted {
                            Button("Open Settings") {
                                AccessibilityPermission.request()
                                AccessibilityPermission.openSettings()
                            }
                        }
                    }
                }
                LabeledContent("Clipboard access", value: PasteboardAccess.description)
                Text("After rebuilding the app, remove and re-add ClipShelf under Accessibility: ad hoc signed builds get a new identity each time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = AccessibilityPermission.isGranted
        }
    }

    /// Registers the recorded shortcut, or restores the previous one when it is nil (cancelled) or refused.
    private func apply(_ shortcut: Shortcut?) {
        let previous = preferences.shelfShortcut
        guard let shortcut, shortcut != previous else {
            hotKey.register(previous)
            shortcutError = nil
            return
        }
        if hotKey.register(shortcut) {
            preferences.shelfShortcut = shortcut
            shortcutError = nil
        } else {
            hotKey.register(previous)
            shortcutError = "macOS refused \(shortcut.displayString). Kept \(previous.displayString)."
        }
    }
}

/// Click, then press the new shortcut. Esc cancels.
private struct ShortcutRecorder: View {
    let shortcut: Shortcut
    let onBegin: () -> Void
    let onEnd: (Shortcut?) -> Void

    @State private var isRecording = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(action: { isRecording ? finish(nil) : start() }) {
                Text(label)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to change")
            if let hint { Text(hint).font(.caption).foregroundStyle(.orange) }
        }
        .onDisappear { if isRecording { finish(nil) } }
    }

    private var label: String {
        guard isRecording else { return shortcut.displayString }
        return heldModifiers.isEmpty ? "Type shortcut…" : Shortcut.modifierSymbols(heldModifiers) + "…"
    }

    private func start() {
        isRecording = true
        hint = nil
        heldModifiers = []
        onBegin()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.type == .flagsChanged {
            heldModifiers = flags
            return
        }
        if Int(event.keyCode) == kVK_Escape && flags.isEmpty {
            finish(nil)
            return
        }
        let candidate = Shortcut(keyCode: event.keyCode, flags: flags)
        if candidate.isValid {
            finish(candidate)
        } else {
            hint = "Add ⌘, ⌥ or ⌃"
        }
    }

    private func finish(_ result: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        heldModifiers = []
        hint = nil
        onEnd(result)
    }
}

enum PasteboardAccess {
    static var description: String {
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: "Always allowed"
        case .alwaysDeny: "Denied: allow ClipShelf in Privacy & Security"
        case .ask: "Asks each time: choose Always Allow"
        default: "Allowed (no privacy prompt active)"
        }
    }
}

private struct PrivacySettings: View {
    @Bindable var preferences: Preferences
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Text("ClipShelf has no network code. History lives in ~/Library/Application Support/ClipShelf. Items that apps mark as concealed or transient (passwords, one-time codes) are never recorded.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Never record copies from these apps") {
                List(preferences.excludedBundleIDs, id: \.self, selection: $selection) { bundleID in
                    HStack {
                        if let icon = AppIconCache.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(appName(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 200)
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove") {
                        preferences.excludedBundleIDs.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Restore Defaults") { preferences.excludedBundleIDs = Preferences.defaultExcludedBundleIDs }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !preferences.excludedBundleIDs.contains(id) {
                preferences.excludedBundleIDs.append(id)
            }
        }
    }
}

private struct PinboardSettings: View {
    let store: HistoryStore
    @State private var boards: [Pinboard] = []
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Pinboards") {
                ForEach(boards) { board in
                    HStack {
                        TextField("Name", text: Binding(
                            get: { board.name },
                            set: { store.rename(board, to: $0) }))
                        Text("\(board.items.count) items").foregroundStyle(.secondary).font(.caption)
                        Button(role: .destructive) {
                            store.delete(board)
                            reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New pinboard", text: $newName).onSubmit(create)
                    Button("Add", action: create).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text("In the shelf: ⌘P adds the selected card to a pinboard, Tab switches between History and pinboards. Deleting a pinboard keeps its items in History.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createPinboard(named: name)
        newName = ""
        reload()
    }

    private func reload() { boards = store.pinboards() }
}

private struct ScriptSettings: View {
    @Bindable var preferences: Preferences
    @State private var scripts: [Transform] = []

    private var detected: String {
        ScriptRunner.resolveRuntime(preferredPath: preferences.scriptRuntimePath)?.path ?? "None found"
    }

    var body: some View {
        Form {
            Section("Scripts folder") {
                LabeledContent("Location", value: AppPaths.scriptsDirectory.path)
                HStack {
                    Button("Open in Finder") { NSWorkspace.shared.open(AppPaths.scriptsDirectory) }
                    Button("Reload") { reload() }
                }
                Text("Each .ts, .js or .mjs file must `export default (input: string, context) => string`. Optional header comments: `// @name …` and `// @description …`. Scripts appear in the shelf under ⌘K.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Runtime") {
                TextField("Path to bun, deno or node (empty = auto-detect)", text: $preferences.scriptRuntimePath)
                LabeledContent("Using", value: detected)
                Text("Deno runs scripts sandboxed (no network). Bun and Node run them with your user's permissions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Installed scripts") {
                if scripts.isEmpty {
                    Text("No scripts yet").foregroundStyle(.secondary)
                }
                ForEach(scripts) { script in
                    LabeledContent(script.name, value: script.detail)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func reload() { scripts = ScriptRunner.scripts() }
}
