import AppKit
import Carbon.HIToolbox
import Observation

enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, images, links, files, code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .links: "Links"
        case .files: "Files"
        case .code: "Code"
        }
    }

    var shortcut: String {
        switch self {
        case .all: "⌘0"
        case .text: "⌘T"
        case .images: "⌘I"
        case .links: "⌘L"
        case .files: "⌘F"
        case .code: "⌘E"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: true
        case .text: (item.kind == .text || item.kind == .richText) && !item.isCode
        case .images: item.kind == .image
        case .links: item.kind == .link
        case .files: item.kind == .file
        case .code: item.isCode
        }
    }
}

enum ShelfTab: Hashable {
    case history
    case pinboard(UUID)
}

enum ShelfMode: Equatable {
    case browse
    case transforms
    case pinboardPicker
    case editing
}

@Observable
final class ShelfViewModel {
    let store: HistoryStore
    let preferences: Preferences

    var query = "" { didSet { selectedIndex = 0 } }
    var filter: ClipFilter = .all { didSet { selectedIndex = 0 } }
    var tab: ShelfTab = .history { didSet { selectedIndex = 0 } }
    var selectedIndex = 0
    var mode: ShelfMode = .browse

    var menuQuery = "" { didSet { menuIndex = 0 } }
    var menuIndex = 0
    var status: String?
    var isRunningScript = false

    private(set) var allItems: [ClipItem] = []
    private(set) var boards: [Pinboard] = []
    private(set) var transforms: [Transform] = []

    // Wired by ShelfController.
    var onPaste: (ClipItem, Bool) -> Void = { _, _ in }
    var onPasteText: (String, ClipItem) -> Void = { _, _ in }
    var onCopy: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    init(store: HistoryStore, preferences: Preferences = .shared) {
        self.store = store
        self.preferences = preferences
    }

    // MARK: Data

    func reload() {
        allItems = store.items()
        boards = store.pinboards()
        if case .pinboard(let id) = tab, !boards.contains(where: { $0.id == id }) { tab = .history }
        clampSelection()
    }

    func resetForShow() {
        mode = .browse
        tab = .history
        filter = .all
        query = ""
        draggedItemID = nil
        editingItemID = nil
        draft = ""
        draftName = ""
        menuQuery = ""
        status = nil
        selectedIndex = 0
        reload()
    }

    var visibleItems: [ClipItem] {
        let base: [ClipItem]
        switch tab {
        case .history:
            base = allItems
        case .pinboard(let id):
            base = (boards.first { $0.id == id }?.items ?? []).sorted { $0.lastUsedAt > $1.lastUsedAt }
        }
        return SearchQuery(query).rank(base.filter(filter.matches))
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    var tabs: [ShelfTab] { [.history] + boards.map { .pinboard($0.id) } }

    func title(of tab: ShelfTab) -> String {
        switch tab {
        case .history: "History"
        case .pinboard(let id): boards.first { $0.id == id }?.name ?? "Pinboard"
        }
    }

    private func clampSelection() {
        let count = visibleItems.count
        selectedIndex = count == 0 ? 0 : min(max(selectedIndex, 0), count - 1)
    }

    // MARK: Menus (transforms and pinboard picker)

    var visibleTransforms: [Transform] {
        let q = menuQuery.lowercased()
        guard !q.isEmpty else { return transforms }
        return transforms.filter { $0.name.lowercased().contains(q) || $0.detail.lowercased().contains(q) }
    }

    var visibleBoards: [Pinboard] {
        let q = menuQuery.lowercased()
        guard !q.isEmpty else { return boards }
        return boards.filter { $0.name.lowercased().contains(q) }
    }

    /// The text field binds to whichever query the current mode edits.
    var activeQuery: String {
        get { mode == .browse ? query : menuQuery }
        set { if mode == .browse { query = newValue } else { menuQuery = newValue } }
    }

    var placeholder: String {
        switch mode {
        case .browse: "Search, or name: app: is: lang: board:"
        case .transforms: "Filter transforms"
        case .pinboardPicker: "Pinboard name (Return creates it if new)"
        case .editing: "Editing"
        }
    }

    func openTransforms() {
        guard let item = selectedItem, item.text != nil, item.kind != .image else {
            status = "Transforms work on text items"
            return
        }
        transforms = BuiltinTransforms.all + ScriptRunner.scripts()
        menuQuery = ""
        mode = .transforms
    }

    func openPinboardPicker() {
        guard selectedItem != nil else { return }
        menuQuery = ""
        mode = .pinboardPicker
    }

    func apply(_ transform: Transform, to item: ClipItem) {
        guard let text = item.text else { return }
        switch transform.action {
        case .builtin(let function):
            do {
                onPasteText(try function(text), item)
            } catch {
                status = error.localizedDescription
            }
        case .script(let url):
            isRunningScript = true
            status = "Running \(transform.name)…"
            Task {
                defer { isRunningScript = false }
                do {
                    let output = try await ScriptRunner.run(
                        script: url, input: text, sourceApp: item.sourceAppName, runtimePath: preferences.scriptRuntimePath)
                    onPasteText(output, item)
                } catch {
                    status = error.localizedDescription
                }
            }
        }
    }

    func choosePinboard(at index: Int) {
        guard let item = selectedItem else { return }
        let options = visibleBoards
        if options.indices.contains(index) {
            let board = options[index]
            store.toggle(item, in: board)
            status = board.items.contains(where: { $0.id == item.id }) ? "Added to \(board.name)" : "Removed from \(board.name)"
        } else {
            let name = menuQuery.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let board = store.createPinboard(named: name)
            store.toggle(item, in: board)
            status = "Added to \(board.name)"
        }
        mode = .browse
        reload()
    }

    // MARK: Editing

    enum EditFocus: Hashable { case name, text }

    private(set) var editingItemID: UUID?
    private(set) var editFocus: EditFocus = .text
    var draft = ""
    var draftName = ""

    var editingItem: ClipItem? { editingItemID.flatMap { id in allItems.first { $0.id == id } } }

    /// Every clip can be named; only text and links have editable content.
    static func canEditText(_ item: ClipItem) -> Bool {
        item.kind == .text || item.kind == .richText || item.kind == .link
    }

    /// ⌘O starts in the text, ⌘R (rename) in the name field. Images and files only have a name.
    func startEditing(_ item: ClipItem? = nil, focus: EditFocus = .text) {
        guard let item = item ?? selectedItem else { return }
        if let index = visibleItems.firstIndex(where: { $0.id == item.id }) { selectedIndex = index }
        editingItemID = item.id
        editFocus = Self.canEditText(item) ? focus : .name
        draft = item.text ?? ""
        draftName = item.title ?? ""
        status = nil
        mode = .editing
    }

    func cancelEditing() {
        editingItemID = nil
        draft = ""
        draftName = ""
        mode = .browse
    }

    func saveEditing() {
        guard let item = editingItem else { return cancelEditing() }
        let textResult = Self.canEditText(item) ? store.updateText(of: item, to: draft) : .unchanged
        if textResult == .empty {
            status = "A clip can't be empty. Delete it with ⌘⌫ instead."
            return
        }
        let renamed = store.setName(of: item, to: draftName)
        if textResult == .saved {
            status = item.kind == .link ? "Saved as link" : "Saved"
        } else {
            status = renamed ? (item.title.map { "Named \"\($0)\"" } ?? "Name removed") : "No changes"
        }
        let id = item.id
        cancelEditing()
        reload()
        if let index = visibleItems.firstIndex(where: { $0.id == id }) { selectedIndex = index }
    }

    // MARK: Drag and drop

    /// The card being dragged inside the shelf. Set when a drag starts, cleared on drop or when the shelf hides.
    var draggedItemID: UUID?

    private func board(for tab: ShelfTab) -> Pinboard? {
        guard case .pinboard(let id) = tab else { return nil }
        return boards.first { $0.id == id }
    }

    /// Drops the dragged card on a tab: moves it out of the current pinboard into the target one.
    /// History as target takes it off the current pinboard. `copy` (⌥ held) keeps it in the current pinboard.
    @discardableResult
    func dropDraggedItem(on target: ShelfTab, copy: Bool) -> Bool {
        defer { draggedItemID = nil }
        guard let id = draggedItemID, let item = allItems.first(where: { $0.id == id }) else { return false }
        let source = board(for: tab)
        let destination = board(for: target)
        if case .pinboard = target, destination == nil { return false }

        let result = store.move(item, from: source, to: destination, keepInSource: copy)
        switch result {
        case .moved: status = "Moved to \(title(of: target))"
        case .added: status = "Added to \(title(of: target))"
        case .removed: status = "Removed from \(source?.name ?? "pinboard")"
        case .unchanged: status = destination.map { "Already in \($0.name)" } ?? "Already in History"
        }
        reload()
        return result != .unchanged
    }

    // MARK: Keyboard

    /// Returns true when the key was handled and must not reach the search field.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = Int(event.keyCode)

        switch mode {
        case .browse: return handleBrowseKey(key: key, command: command, shift: shift, characters: event.charactersIgnoringModifiers)
        case .transforms, .pinboardPicker: return handleMenuKey(key: key, shift: shift)
        case .editing: return handleEditKey(key: key, command: command, shift: shift, characters: event.charactersIgnoringModifiers)
        }
    }

    /// Everything not handled here goes to the text editor. The menu bar app has no Edit menu, so the
    /// standard editing shortcuts are routed to the editor by hand.
    private func handleEditKey(key: Int, command: Bool, shift: Bool, characters: String?) -> Bool {
        if key == kVK_Escape {
            cancelEditing()
            return true
        }
        guard command else { return false }
        if key == kVK_Return || key == kVK_ANSI_KeypadEnter {
            saveEditing()
            return true
        }
        let action: String
        switch characters?.lowercased() {
        case "s": saveEditing(); return true
        case "x": action = "cut:"
        case "c": action = "copy:"
        case "v": action = "paste:"
        case "a": action = "selectAll:"
        case "z": action = shift ? "redo:" : "undo:"
        default: return false
        }
        return NSApp.sendAction(Selector(action), to: nil, from: nil)
    }

    private func handleBrowseKey(key: Int, command: Bool, shift: Bool, characters: String?) -> Bool {
        let count = visibleItems.count
        switch key {
        case kVK_Escape:
            if !query.isEmpty { query = "" } else if filter != .all { filter = .all } else { onClose() }
            return true
        case kVK_LeftArrow:
            selectedIndex = max(selectedIndex - 1, 0)
            return true
        case kVK_RightArrow:
            selectedIndex = min(selectedIndex + 1, max(count - 1, 0))
            return true
        case kVK_Home where command, kVK_UpArrow where command:
            selectedIndex = 0
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = selectedItem { onPaste(item, shift) }
            return true
        case kVK_Tab:
            cycleTab(forward: !shift)
            return true
        case kVK_Delete where command, kVK_ForwardDelete where command:
            if let item = selectedItem {
                store.delete(item)
                reload()
            }
            return true
        default:
            break
        }

        guard command, let characters = characters?.lowercased() else { return false }

        if let digit = Int(characters), (1...9).contains(digit) {
            let items = visibleItems
            if items.indices.contains(digit - 1) { onPaste(items[digit - 1], shift) }
            return true
        }

        switch characters {
        case "k": openTransforms()
        case "o": startEditing()
        case "r": startEditing(focus: .name)
        case "p": openPinboardPicker()
        case "c": if let item = selectedItem { onCopy(item) }
        case ",": onOpenSettings()
        case "0": filter = .all
        case "t": toggleFilter(.text)
        case "i": toggleFilter(.images)
        case "l": toggleFilter(.links)
        case "f": toggleFilter(.files)
        case "e": toggleFilter(.code)
        default: return false
        }
        return true
    }

    private func handleMenuKey(key: Int, shift: Bool) -> Bool {
        let count = mode == .transforms ? visibleTransforms.count : visibleBoards.count + 1
        switch key {
        case kVK_Escape:
            mode = .browse
            return true
        case kVK_UpArrow:
            menuIndex = max(menuIndex - 1, 0)
            return true
        case kVK_DownArrow, kVK_Tab:
            menuIndex = min(menuIndex + 1, max(count - 1, 0))
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard !isRunningScript else { return true }
            if mode == .transforms {
                let options = visibleTransforms
                if let item = selectedItem, options.indices.contains(menuIndex) { apply(options[menuIndex], to: item) }
            } else {
                choosePinboard(at: menuIndex)
            }
            return true
        default:
            return false
        }
    }

    private func toggleFilter(_ value: ClipFilter) {
        filter = filter == value ? .all : value
    }

    private func cycleTab(forward: Bool) {
        let all = tabs
        guard let index = all.firstIndex(of: tab) else { tab = .history; return }
        tab = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }
}
