import Foundation

/// The shelf's search language. Every term must match, matches are ranked (names first), and case and
/// accents are ignored.
///
/// - `deploy notes`: each word matches the name, text, source app, language or kind
/// - `"exact phrase"`: matches as a whole
/// - `-word`: excludes clips that match it
/// - `name:` `app:` `is:` `lang:` `board:` narrow to one field, e.g. `app:slack is:code lang:swift board:work`
/// - `is:` takes text, rich, link, image, file, code, named or pinned
/// - Names also match loosely: `dpn` finds "Deploy notes"
struct SearchQuery: Equatable {
    enum Field: String { case name, app, type, lang, board }

    struct Term: Equatable {
        var text: String
        var field: Field?
        var negated = false
    }

    let terms: [Term]

    var isEmpty: Bool { terms.isEmpty }

    private static let fieldAliases: [String: Field] = [
        "name": .name, "title": .name, "app": .app, "from": .app, "is": .type, "type": .type, "kind": .type,
        "lang": .lang, "language": .lang, "board": .board, "in": .board, "pinboard": .board,
    ]

    init(_ raw: String) {
        terms = Self.tokens(in: raw).compactMap { token in
            var token = token
            var term = Term(text: "")
            if token.count > 1, token.hasPrefix("-") {
                term.negated = true
                token.removeFirst()
            }
            if let colon = token.firstIndex(of: ":"),
               let field = Self.fieldAliases[token[..<colon].lowercased()], token.index(after: colon) < token.endIndex {
                term.field = field
                token = String(token[token.index(after: colon)...])
            }
            term.text = token.replacingOccurrences(of: "\"", with: "")
            return term.text.isEmpty ? nil : term
        }
    }

    /// Splits on whitespace outside double quotes.
    private static func tokens(in raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in raw {
            if character == "\"" { inQuotes.toggle() }
            if character.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Nil when the clip doesn't match. Higher is a better match.
    func score(_ item: ClipItem) -> Int? {
        var total = 0
        for term in terms {
            let score = Self.score(term, item)
            if term.negated {
                if score > 0 { return nil }
            } else {
                if score == 0 { return nil }
                total += score
            }
        }
        return total
    }

    /// Sorts best matches first, keeping the incoming (most recent first) order among equal scores.
    func rank(_ items: [ClipItem]) -> [ClipItem] {
        guard !isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in score(item).map { (item, $0, offset) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    private static func score(_ term: Term, _ item: ClipItem) -> Int {
        let needle = term.text
        switch term.field {
        case .name: return nameScore(needle, item.title)
        case .app: return max(contains(item.sourceAppName, needle) ? 4 : 0, contains(item.sourceBundleID, needle) ? 3 : 0)
        case .type: return matchesType(needle.lowercased(), item) ? 1 : 0
        case .lang: return languageScore(needle, item)
        case .board: return item.pinboards.contains { contains($0.name, needle) } ? 1 : 0
        case nil:
            return max(
                nameScore(needle, item.title),
                textScore(needle, item.text),
                contains(item.sourceAppName, needle) ? 4 : 0,
                languageScore(needle, item),
                contains(kindName(of: item), needle) ? 2 : 0)
        }
    }

    private static func nameScore(_ needle: String, _ name: String?) -> Int {
        guard let name, !name.isEmpty else { return 0 }
        let folded = fold(name), target = fold(needle)
        if folded == target { return 100 }
        if folded.hasPrefix(target) { return 70 }
        if let range = folded.range(of: target) {
            return isWordStart(range.lowerBound, in: folded) ? 50 : 35
        }
        return target.count >= 2 && isSubsequence(target, of: folded) ? 15 : 0
    }

    private static func textScore(_ needle: String, _ text: String?) -> Int {
        guard let text, let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return 0 }
        return isWordStart(range.lowerBound, in: text) ? 10 : 6
    }

    private static func languageScore(_ needle: String, _ item: ClipItem) -> Int {
        guard let language = item.codeLanguage else { return 0 }
        return contains(language, needle) || contains(CodeDetector.displayName(of: language), needle) ? 4 : 0
    }

    private static func matchesType(_ value: String, _ item: ClipItem) -> Bool {
        switch value {
        case "text", "plain": (item.kind == .text || item.kind == .richText) && !item.isCode
        case "rich", "richtext": item.kind == .richText
        case "link", "url": item.kind == .link
        case "image", "img", "picture": item.kind == .image
        case "file", "files": item.kind == .file
        case "code", "snippet": item.isCode
        case "named", "titled": !(item.title ?? "").isEmpty
        case "pinned": !item.pinboards.isEmpty
        default: false
        }
    }

    private static func kindName(of item: ClipItem) -> String {
        item.isCode ? "code" : item.kind == .richText ? "text" : item.kind.rawValue
    }

    private static func contains(_ haystack: String?, _ needle: String) -> Bool {
        haystack?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    private static func isWordStart(_ index: String.Index, in string: String) -> Bool {
        guard index > string.startIndex else { return true }
        let previous = string[string.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle.makeIterator()
        var next = remaining.next()
        for character in haystack where character == next {
            next = remaining.next()
            if next == nil { return true }
        }
        return next == nil
    }
}
