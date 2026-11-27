import Foundation
import Observation
import SwiftData

@Observable
final class HistoryStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    /// Bumped on every mutation so views can refetch.
    private(set) var revision = 0

    init(inMemory: Bool = false) {
        let schema = Schema([ClipItem.self, Pinboard.self])
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: AppPaths.storeURL, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open history store: \(error)")
        }
    }

    @discardableResult
    func record(_ snapshot: ClipSnapshot, sourceBundleID: String?, sourceAppName: String?, at date: Date = Date()) -> ClipItem {
        let hash = snapshot.contentHash
        if let existing = item(withHash: hash) {
            existing.lastUsedAt = date
            existing.sourceBundleID = sourceBundleID ?? existing.sourceBundleID
            existing.sourceAppName = sourceAppName ?? existing.sourceAppName
            save()
            return existing
        }

        let item = ClipItem(kind: snapshot.kind, contentHash: hash)
        item.createdAt = date
        item.lastUsedAt = date
        item.text = snapshot.text
        item.rtfData = snapshot.rtfData
        item.htmlData = snapshot.htmlData
        item.imageData = snapshot.imageData
        item.fileURLStrings = snapshot.fileURLStrings
        item.codeLanguage = snapshot.codeLanguage
        item.sourceBundleID = sourceBundleID
        item.sourceAppName = sourceAppName
        context.insert(item)
        save()
        return item
    }

    func items(limit: Int = 5000) -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func item(withHash hash: String) -> ClipItem? {
        var descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func markUsed(_ item: ClipItem, at date: Date = Date()) {
        item.lastUsedAt = date
        save()
    }

    func delete(_ item: ClipItem) {
        context.delete(item)
        save()
    }

    func clearHistory() {
        for item in items(limit: Int.max) where item.pinboards.isEmpty {
            context.delete(item)
        }
        save()
    }

    /// Removes unpinned items not used within the retention window. `days == 0` keeps everything.
    func prune(retentionDays days: Int, now: Date = Date()) {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.lastUsedAt < cutoff })
        let stale = (try? context.fetch(descriptor)) ?? []
        var removed = false
        for item in stale where item.pinboards.isEmpty {
            context.delete(item)
            removed = true
        }
        if removed { save() }
    }

    // MARK: Pinboards

    func pinboards() -> [Pinboard] {
        let descriptor = FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createPinboard(named name: String) -> Pinboard {
        let board = Pinboard(name: name, sortIndex: (pinboards().map(\.sortIndex).max() ?? -1) + 1)
        context.insert(board)
        save()
        return board
    }

    func rename(_ board: Pinboard, to name: String) {
        board.name = name
        save()
    }

    func delete(_ board: Pinboard) {
        context.delete(board)
        save()
    }

    func toggle(_ item: ClipItem, in board: Pinboard) {
        if let index = board.items.firstIndex(where: { $0.id == item.id }) {
            board.items.remove(at: index)
        } else {
            board.items.append(item)
        }
        save()
    }

    enum MoveResult: Equatable {
        case moved, added, removed, unchanged
    }

    /// Moves an item between boards. `nil` stands for History, which holds every item, so moving to it only
    /// takes the item off `source`. With `keepInSource` the item is added to `target` and stays in `source`.
    @discardableResult
    func move(_ item: ClipItem, from source: Pinboard?, to target: Pinboard?, keepInSource: Bool = false) -> MoveResult {
        if let source, let target, source.id == target.id { return .unchanged }

        var added = false
        if let target, !target.items.contains(where: { $0.id == item.id }) {
            target.items.append(item)
            added = true
        }
        var removed = false
        if let source, !keepInSource, let index = source.items.firstIndex(where: { $0.id == item.id }) {
            source.items.remove(at: index)
            removed = true
        }
        guard added || removed else { return .unchanged }
        save()
        if removed { return target == nil ? .removed : .moved }
        return .added
    }

    private func save() {
        do {
            try context.save()
        } catch {
            NSLog("ClipShelf: save failed: \(error)")
        }
        revision += 1
    }
}
