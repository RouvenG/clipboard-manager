import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text
    case richText
    case link
    case image
    case file
}

@Model
final class ClipItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()
    var kindRaw: String = ClipKind.text.rawValue
    var contentHash: String = ""

    /// Optional name the user gives the clip. Searched first.
    var title: String?

    /// Plain text representation. Set for text, rich text, links and files (paths).
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var fileURLStrings: [String] = []

    var sourceBundleID: String?
    var sourceAppName: String?

    /// Detected programming language for code snippets, nil for prose.
    var codeLanguage: String?

    @Relationship(inverse: \Pinboard.items) var pinboards: [Pinboard] = []

    init(kind: ClipKind, contentHash: String) {
        self.kindRaw = kind.rawValue
        self.contentHash = contentHash
    }

    var kind: ClipKind {
        get { ClipKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var isCode: Bool { codeLanguage != nil }

    var fileURLs: [URL] { fileURLStrings.compactMap(URL.init(string:)) }
}

@Model
final class Pinboard {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var items: [ClipItem] = []

    init(name: String, sortIndex: Int) {
        self.name = name
        self.sortIndex = sortIndex
    }
}
