import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipShelf

struct TransformTests {
    @Test func jsonPrettyKeepsKeyOrder() throws {
        let output = try JSONFormatter.pretty(#"{"b":1,"a":[1,2],"s":"x, y: {z}","e":{}}"#)
        #expect(output == """
        {
          "b": 1,
          "a": [
            1,
            2
          ],
          "s": "x, y: {z}",
          "e": {}
        }
        """)
    }

    @Test func jsonMinifyKeepsStringWhitespace() throws {
        #expect(try JSONFormatter.minify("{ \"a b\" : [ 1, 2 ] }") == #"{"a b":[1,2]}"#)
    }

    @Test func jsonRejectsInvalid() {
        #expect(throws: TransformError.self) { try JSONFormatter.pretty("{nope") }
    }

    @Test func whitespace() {
        #expect(Whitespace.trim("  a  \n b \t\n\n") == "a\n b")
        #expect(Whitespace.collapseBlankLines("a\n\n\n  \nb") == "a\n\nb")
        #expect(Whitespace.singleLine("a\n  b\tc") == "a b c")
    }

    @Test func caseConversion() {
        #expect(CaseConverter.words("parseHTTPResponse_v2-final") == ["parse", "HTTP", "Response", "v2", "final"])
        #expect(CaseConverter.camel("Hello world again") == "helloWorldAgain")
        #expect(CaseConverter.pascal("hello_world") == "HelloWorld")
        #expect(CaseConverter.snake("helloWorld HTTPServer") == "hello_world_http_server")
        #expect(CaseConverter.kebab("Hello World") == "hello-world")
        #expect(CaseConverter.title("hello wORLD") == "Hello World")
    }

    @Test func encoding() throws {
        #expect(Encoding.base64Encode("hä") == "aMOk")
        #expect(try Encoding.base64Decode("aMOk") == "hä")
        #expect(try Encoding.base64Decode("aGk") == "hi")
        #expect(Encoding.urlEncode("a b&c=d/é") == "a%20b%26c%3Dd%2F%C3%A9")
        #expect(try Encoding.urlDecode("a+b%26c") == "a b&c")
    }
}

struct DetectionTests {
    @Test func links() {
        #expect(LinkDetector.link(in: "  https://pasteapp.io/help \n") == "https://pasteapp.io/help")
        #expect(LinkDetector.link(in: "mailto:a@b.c") == "mailto:a@b.c")
        #expect(LinkDetector.link(in: "see https://x.com") == nil)
        #expect(LinkDetector.link(in: "http://nohost") == nil)
        #expect(LinkDetector.link(in: "just words") == nil)
    }

    @Test(arguments: [
        ("{\"a\": 1}", "json"),
        ("import SwiftUI\n\nstruct A: View {\n  var body: some View { Text(\"x\") }\n}", "swift"),
        ("export const add = (a: number, b: number): number => a + b;", "typescript"),
        ("def main():\n    print(\"hi\")\n", "python"),
        ("package main\n\nfunc main() {\n  x := 1\n}", "go"),
        ("func parsesHeader() throws {\n    let url = URL(fileURLWithPath: \"/tmp\")\n    defer { cleanup() }\n}", "swift"),
        ("SELECT id, name FROM users WHERE id = 1", "sql"),
        ("git commit -m \"fix: thing\" --amend", "shell"),
    ])
    func detectsCode(_ sample: String, _ language: String) {
        #expect(CodeDetector.language(of: sample) == language)
    }

    @Test(arguments: [
        "Let me know if you can make it to the meeting tomorrow.",
        "Import the file, then select the rows you need from the list.",
        "Buy milk",
    ])
    func ignoresProse(_ sample: String) {
        #expect(CodeDetector.language(of: sample) == nil)
    }
}

struct PasteboardReaderTests {
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("clipshelf.tests.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func readsPlainText() throws {
        let board = pasteboard()
        board.setString("hello world", forType: .string)
        let snapshot = try #require(PasteboardReader.snapshot(from: board))
        #expect(snapshot.kind == .text)
        #expect(snapshot.text == "hello world")
    }

    @Test func readsLink() throws {
        let board = pasteboard()
        board.setString("https://example.com/a", forType: .string)
        #expect(try #require(PasteboardReader.snapshot(from: board)).kind == .link)
    }

    @Test func readsRichText() throws {
        let board = pasteboard()
        let item = NSPasteboardItem()
        item.setString("bold", forType: .string)
        item.setData(Data("{\\rtf1 \\b bold}".utf8), forType: .rtf)
        board.writeObjects([item])
        let snapshot = try #require(PasteboardReader.snapshot(from: board))
        #expect(snapshot.kind == .richText)
        #expect(snapshot.rtfData != nil)
    }

    @Test func readsFiles() throws {
        let board = pasteboard()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(fileURLWithPath: "/tmp/b.txt") as NSURL])
        let snapshot = try #require(PasteboardReader.snapshot(from: board))
        #expect(snapshot.kind == .file)
        #expect(snapshot.fileURLStrings.count == 2)
    }

    @Test func readsImage() throws {
        let board = pasteboard()
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        board.writeObjects([image])
        let snapshot = try #require(PasteboardReader.snapshot(from: board))
        #expect(snapshot.kind == .image)
        #expect(snapshot.imageData.flatMap(NSImage.init(data:)) != nil)
    }

    @Test(arguments: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"])
    func skipsMarkedTypes(_ type: String) {
        let board = pasteboard()
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType(type))
        board.writeObjects([item])
        #expect(PasteboardReader.snapshot(from: board) == nil)
    }

    @Test func skipsOwnWrites() {
        let board = pasteboard()
        PasteService.write(text: "from clipshelf", to: board)
        #expect(PasteboardReader.snapshot(from: board) == nil)
        #expect(board.string(forType: .string) == "from clipshelf")
    }
}

struct HistoryStoreTests {
    @Test func dedupesAndBumps() {
        let store = HistoryStore(inMemory: true)
        let snapshot = ClipSnapshot(kind: .text, text: "same")
        store.record(snapshot, sourceBundleID: "a", sourceAppName: "A", at: Date(timeIntervalSince1970: 1))
        store.record(ClipSnapshot(kind: .text, text: "other"), sourceBundleID: nil, sourceAppName: nil, at: Date(timeIntervalSince1970: 2))
        store.record(snapshot, sourceBundleID: "b", sourceAppName: "B", at: Date(timeIntervalSince1970: 3))
        let items = store.items()
        #expect(items.count == 2)
        #expect(items.first?.text == "same")
        #expect(items.first?.sourceAppName == "B")
    }

    @Test func pruneKeepsPinnedAndRecent() {
        let store = HistoryStore(inMemory: true)
        let now = Date()
        let old = store.record(ClipSnapshot(kind: .text, text: "old"), sourceBundleID: nil, sourceAppName: nil,
                               at: now.addingTimeInterval(-40 * 86_400))
        let pinned = store.record(ClipSnapshot(kind: .text, text: "pinned"), sourceBundleID: nil, sourceAppName: nil,
                                  at: now.addingTimeInterval(-40 * 86_400))
        store.record(ClipSnapshot(kind: .text, text: "new"), sourceBundleID: nil, sourceAppName: nil, at: now)
        let board = store.createPinboard(named: "Keep")
        store.toggle(pinned, in: board)

        store.prune(retentionDays: 30, now: now)
        let texts = Set(store.items().compactMap(\.text))
        #expect(texts == ["pinned", "new"])
        _ = old
    }

    @Test func foreverRetentionKeepsAll() {
        let store = HistoryStore(inMemory: true)
        store.record(ClipSnapshot(kind: .text, text: "ancient"), sourceBundleID: nil, sourceAppName: nil, at: .distantPast)
        store.prune(retentionDays: 0)
        #expect(store.items().count == 1)
    }

    @Test func pinboardToggle() {
        let store = HistoryStore(inMemory: true)
        let item = store.record(ClipSnapshot(kind: .text, text: "x"), sourceBundleID: nil, sourceAppName: nil)
        let board = store.createPinboard(named: "Snippets")
        store.toggle(item, in: board)
        #expect(board.items.count == 1)
        store.toggle(item, in: board)
        #expect(board.items.isEmpty)
    }
}

struct ScriptRunnerTests {
    @Test func parsesHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString).ts")
        try "// @name Reverse\n// @description Reverse lines\nexport default (s: string) => s\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let header = ScriptRunner.parseHeader(of: url)
        #expect(header.name == "Reverse")
        #expect(header.description == "Reverse lines")
    }

    @Test(arguments: ["bun", "deno", "node"])
    func runsTypeScriptWith(_ runtimeName: String) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.bun/bin/\(runtimeName)", "/opt/homebrew/bin/\(runtimeName)", "/usr/local/bin/\(runtimeName)"]
            + ((try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node")) ?? [])
            .map { "\(home)/.nvm/versions/node/\($0)/bin/\(runtimeName)" }
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("upper.ts")
        try """
        export default (input: string, ctx: { sourceApp?: string }): string =>
          `${input.toUpperCase()}|${ctx.sourceApp}`;
        """.write(to: script, atomically: true, encoding: .utf8)

        let output = try await ScriptRunner.run(script: script, input: "héllo", sourceApp: "Notes", runtimePath: path)
        #expect(output == "HÉLLO|Notes")
    }

    @Test func reportsScriptErrors() async throws {
        guard let runtime = ScriptRunner.resolveRuntime(preferredPath: "") else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("boom.ts")
        try "export default (_: string): string => { throw new Error(\"boom\"); };".write(to: script, atomically: true, encoding: .utf8)

        await #expect(throws: TransformError.self) {
            try await ScriptRunner.run(script: script, input: "x", sourceApp: nil, runtimePath: runtime.path)
        }
    }
}

struct DragAndDropTests {
    private func setUp() -> (HistoryStore, ShelfViewModel, ClipItem, Pinboard, Pinboard) {
        let store = HistoryStore(inMemory: true)
        let item = store.record(ClipSnapshot(kind: .text, text: "drag me"), sourceBundleID: nil, sourceAppName: nil)
        let work = store.createPinboard(named: "Work")
        let snippets = store.createPinboard(named: "Snippets")
        let model = ShelfViewModel(store: store)
        model.reload()
        return (store, model, item, work, snippets)
    }

    @Test func storeMoveBetweenBoards() {
        let (store, _, item, work, snippets) = setUp()
        store.toggle(item, in: work)
        #expect(store.move(item, from: work, to: snippets) == .moved)
        #expect(work.items.isEmpty)
        #expect(snippets.items.map(\.id) == [item.id])
        #expect(store.move(item, from: snippets, to: snippets) == .unchanged)
    }

    @Test func storeMoveKeepsSourceWhenCopying() {
        let (store, _, item, work, snippets) = setUp()
        store.toggle(item, in: work)
        #expect(store.move(item, from: work, to: snippets, keepInSource: true) == .added)
        #expect(work.items.count == 1)
        #expect(snippets.items.count == 1)
    }

    @Test func storeMoveIntoBoardThatAlreadyHasItem() {
        let (store, _, item, work, snippets) = setUp()
        store.toggle(item, in: work)
        store.toggle(item, in: snippets)
        #expect(store.move(item, from: work, to: snippets) == .moved)
        #expect(work.items.isEmpty)
        #expect(snippets.items.count == 1)
    }

    @Test func dropFromHistoryAddsToBoard() {
        let (_, model, item, work, _) = setUp()
        model.draggedItemID = item.id
        #expect(model.dropDraggedItem(on: .pinboard(work.id), copy: false))
        #expect(work.items.map(\.id) == [item.id])
        #expect(model.status == "Added to Work")
        #expect(model.draggedItemID == nil)
        #expect(model.allItems.count == 1)
    }

    @Test func dropBetweenBoardsMoves() {
        let (store, model, item, work, snippets) = setUp()
        store.toggle(item, in: work)
        model.reload()
        model.tab = .pinboard(work.id)
        model.draggedItemID = item.id
        #expect(model.dropDraggedItem(on: .pinboard(snippets.id), copy: false))
        #expect(work.items.isEmpty)
        #expect(snippets.items.count == 1)
        #expect(model.status == "Moved to Snippets")
        #expect(model.visibleItems.isEmpty)
    }

    @Test func dropOnHistoryUnpins() {
        let (store, model, item, work, _) = setUp()
        store.toggle(item, in: work)
        model.reload()
        model.tab = .pinboard(work.id)
        model.draggedItemID = item.id
        #expect(model.dropDraggedItem(on: .history, copy: false))
        #expect(work.items.isEmpty)
        #expect(model.status == "Removed from Work")
        #expect(store.items().count == 1)
    }

    @Test func dropWithoutDragDoesNothing() {
        let (_, model, _, work, _) = setUp()
        #expect(!model.dropDraggedItem(on: .pinboard(work.id), copy: false))
        #expect(work.items.isEmpty)
    }
}

struct ShortcutTests {
    @Test func defaultIsOptionCommandV() {
        #expect(Shortcut.shelfDefault.displayString == "⌥⌘V")
        #expect(Shortcut.shelfDefault.modifierFlags == [.option, .command])
    }

    @Test func convertsEventFlagsToCarbonModifiers() {
        let shortcut = Shortcut(keyCode: UInt16(kVK_Space), flags: [.control, .shift, .capsLock])
        #expect(shortcut.modifiers == controlKey | shiftKey)
        #expect(shortcut.displayString == "⌃⇧Space")
        #expect(shortcut.menuKeyEquivalent == " ")
    }

    @Test func requiresARealModifierUnlessFunctionKey() {
        #expect(!Shortcut(keyCode: kVK_ANSI_V, modifiers: 0).isValid)
        #expect(!Shortcut(keyCode: kVK_ANSI_V, modifiers: shiftKey).isValid)
        #expect(Shortcut(keyCode: kVK_ANSI_V, modifiers: controlKey).isValid)
        #expect(Shortcut(keyCode: kVK_F5, modifiers: 0).isValid)
        #expect(Shortcut(keyCode: kVK_F5, modifiers: 0).displayString == "F5")
    }

    @Test func persistsInPreferences() throws {
        let suite = "clipshelf.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences(defaults: defaults).shelfShortcut == .shelfDefault)
        let custom = Shortcut(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey)
        Preferences(defaults: defaults).shelfShortcut = custom
        #expect(Preferences(defaults: defaults).shelfShortcut == custom)
    }

    @Test func ignoresInvalidStoredShortcut() throws {
        let suite = "clipshelf.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(try JSONEncoder().encode(Shortcut(keyCode: kVK_ANSI_A, modifiers: 0)), forKey: "shelfShortcut")
        #expect(Preferences(defaults: defaults).shelfShortcut == .shelfDefault)
    }

    @Test func hotKeyReRegistersAndReportsConflicts() {
        // Obscure combo so the test never collides with a running ClipShelf.
        let first = Shortcut(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey | cmdKey)
        let second = Shortcut(keyCode: kVK_F18, modifiers: controlKey | optionKey | shiftKey | cmdKey)
        let hotKey = HotKey {}
        let other = HotKey {}
        defer { hotKey.unregister(); other.unregister() }

        #expect(hotKey.register(first))
        #expect(hotKey.shortcut == first)
        #expect(!other.register(first))
        #expect(other.shortcut == nil)

        #expect(hotKey.register(second))
        #expect(other.register(first))
    }
}

struct EditTests {
    private func record(_ store: HistoryStore, _ snapshot: ClipSnapshot) -> ClipItem {
        store.record(snapshot, sourceBundleID: nil, sourceAppName: nil)
    }

    @Test func updatesTextAndHash() {
        let store = HistoryStore(inMemory: true)
        let item = record(store, ClipSnapshot(kind: .text, text: "helo world"))
        #expect(store.updateText(of: item, to: "hello world") == .saved)
        #expect(item.text == "hello world")
        #expect(item.contentHash == ClipSnapshot(kind: .text, text: "hello world").contentHash)
        #expect(store.item(withHash: item.contentHash)?.id == item.id)
    }

    @Test func redetectsKindAndCode() {
        let store = HistoryStore(inMemory: true)
        let item = record(store, ClipSnapshot(kind: .richText, text: "notes", rtfData: Data("{\\rtf1 notes}".utf8)))
        #expect(store.updateText(of: item, to: #"{"name": "clipshelf", "tags": [1, 2]}"#) == .saved)
        #expect(item.kind == .text)
        #expect(item.rtfData == nil)
        #expect(item.codeLanguage == "json")

        #expect(store.updateText(of: item, to: "https://example.com/docs") == .saved)
        #expect(item.kind == .link)
        #expect(item.codeLanguage == nil)
    }

    @Test func rejectsEmptyUnchangedAndNonText() {
        let store = HistoryStore(inMemory: true)
        let item = record(store, ClipSnapshot(kind: .text, text: "keep"))
        #expect(store.updateText(of: item, to: "  \n") == .empty)
        #expect(store.updateText(of: item, to: "keep") == .unchanged)
        #expect(item.text == "keep")
        let image = record(store, ClipSnapshot(kind: .image, imageData: Data([1, 2, 3])))
        #expect(store.updateText(of: image, to: "text") == .notText)
    }

    @Test func mergesIntoExistingDuplicate() {
        let store = HistoryStore(inMemory: true)
        let edited = record(store, ClipSnapshot(kind: .text, text: "draft"))
        let duplicate = record(store, ClipSnapshot(kind: .text, text: "final"))
        let board = store.createPinboard(named: "Work")
        store.toggle(duplicate, in: board)

        #expect(store.updateText(of: edited, to: "final") == .saved)
        #expect(store.items().map(\.id) == [edited.id])
        #expect(board.items.map(\.id) == [edited.id])
    }

    @Test func modelEditFlowWithShortcuts() {
        let store = HistoryStore(inMemory: true)
        let item = record(store, ClipSnapshot(kind: .text, text: "before"))
        let model = ShelfViewModel(store: store)
        model.reload()

        #expect(model.handleKey(Self.key(kVK_ANSI_O, "o", [.command])))
        #expect(model.mode == .editing)
        #expect(model.draft == "before")
        #expect(!model.handleKey(Self.key(kVK_ANSI_A, "a", [])), "plain typing must reach the editor")
        #expect(!model.handleKey(Self.key(kVK_Return, "\r", [])), "Return must insert a newline")

        model.draft = "after"
        #expect(model.handleKey(Self.key(kVK_Escape, "\u{1b}", [])))
        #expect(model.mode == .browse)
        #expect(item.text == "before")

        model.startEditing(item)
        model.draft = "after"
        #expect(model.handleKey(Self.key(kVK_Return, "\r", [.command])))
        #expect(model.mode == .browse)
        #expect(item.text == "after")
        #expect(model.status == "Saved")
    }

    @Test func imagesCanOnlyBeNamed() {
        let store = HistoryStore(inMemory: true)
        let image = record(store, ClipSnapshot(kind: .image, imageData: Data([1, 2, 3])))
        let model = ShelfViewModel(store: store)
        model.reload()
        model.startEditing(image)
        #expect(model.mode == .editing)
        #expect(model.editFocus == .name)
        model.draftName = "  Logo draft "
        model.saveEditing()
        #expect(image.title == "Logo draft")
        #expect(image.imageData == Data([1, 2, 3]))
        #expect(model.status == "Named \"Logo draft\"")
    }

    @Test func renamingKeepsRichTextFormatting() {
        let store = HistoryStore(inMemory: true)
        let rtf = Data("{\\rtf1 notes}".utf8)
        let item = record(store, ClipSnapshot(kind: .richText, text: "notes", rtfData: rtf))
        let model = ShelfViewModel(store: store)
        model.reload()
        model.startEditing(item, focus: .name)
        model.draftName = "Meeting"
        model.saveEditing()
        #expect(item.kind == .richText)
        #expect(item.rtfData == rtf)
        #expect(item.title == "Meeting")
    }

    @Test func renameShortcutAndClearingName() {
        let store = HistoryStore(inMemory: true)
        let item = record(store, ClipSnapshot(kind: .text, text: "ssh deploy@host"))
        let model = ShelfViewModel(store: store)
        model.reload()

        #expect(model.handleKey(Self.key(kVK_ANSI_R, "r", [.command])))
        #expect(model.editFocus == .name)
        model.draftName = "Deploy login"
        model.saveEditing()
        #expect(item.title == "Deploy login")
        #expect(item.text == "ssh deploy@host")

        model.startEditing(item, focus: .name)
        #expect(model.draftName == "Deploy login")
        model.draftName = ""
        model.saveEditing()
        #expect(item.title == nil)
        #expect(model.status == "Name removed")
    }

    private static func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: UInt16(code))!
    }
}
