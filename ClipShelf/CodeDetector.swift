import Foundation

/// Cheap heuristic code detection. It only has to be good enough to pick a monospace card and a badge.
enum CodeDetector {
    private struct Rule {
        let language: String
        let patterns: [(regex: NSRegularExpression, weight: Int)]

        init(_ language: String, _ patterns: [(String, Int)]) {
            self.language = language
            self.patterns = patterns.map { (try! NSRegularExpression(pattern: $0.0, options: [.anchorsMatchLines]), $0.1) }
        }
    }

    private static let rules: [Rule] = [
        Rule("swift", [
            (#"^\s*import (SwiftUI|Foundation|AppKit|UIKit|SwiftData)\b"#, 4),
            (#"\bfunc \w+\("#, 2), (#"\bguard (let|var)?\b"#, 3), (#"\b(let|var) \w+(: [A-Z]\w*)? ="#, 1),
            (#"@(State|Observable|MainActor|Model|Published)\b"#, 3), (#"\bstruct \w+: View\b"#, 4),
            (#"\bfunc \w+\(.*\) (async )?(throws )?(-> .+ )?\{"#, 3), (#"#expect\(|\bdefer \{|\btry\? "#, 3),
        ]),
        Rule("typescript", [
            (#"^\s*import .+ from ['"]"#, 3), (#"\b(const|let) \w+(: [\w<>\[\]]+)? ="#, 1),
            (#"=>\s*[{(]?"#, 1), (#"\binterface \w+ \{"#, 3), (#":\s*(string|number|boolean)\b"#, 3),
            (#"\bexport (default |const |function |type )"#, 3), (#"\bconsole\.log\("#, 2),
        ]),
        Rule("python", [
            (#"^\s*def \w+\(.*\):\s*$"#, 4), (#"^\s*(from \w+(\.\w+)* )?import \w+"#, 1),
            (#"\bself\.\w+"#, 2), (#"^\s*(elif|except|with) .*:\s*$"#, 3), (#"\bprint\("#, 1),
            (#"^\s*class \w+(\(.*\))?:\s*$"#, 4),
        ]),
        Rule("go", [
            (#"^package \w+\s*$"#, 4), (#"\bfunc (\(\w+ \*?\w+\) )?\w+\("#, 2), (#"\w+ := "#, 3),
            (#"\bfmt\.\w+\("#, 3), (#"\bif err != nil\b"#, 4),
        ]),
        Rule("rust", [
            (#"\bfn \w+(<.*>)?\("#, 3), (#"\blet mut \w+"#, 4), (#"\bimpl(<.*>)? \w+"#, 3),
            (#"\b(pub|use) \w+(::\w+)+"#, 3), (#"\w+!\("#, 1),
        ]),
        Rule("sql", [
            (#"(?i)^\s*SELECT\b.+\bFROM\b"#, 5), (#"(?i)^\s*(INSERT INTO|UPDATE \w+ SET|DELETE FROM|CREATE (TABLE|INDEX))\b"#, 5),
            (#"(?i)\b(WHERE|JOIN|GROUP BY|ORDER BY)\b"#, 1),
        ]),
        Rule("shell", [
            (#"^#!/(usr/)?bin/(env )?(ba|z)?sh"#, 6), (#"^\s*\$ \w+"#, 3),
            (#"^\s*(sudo|brew|git|npm|pnpm|yarn|bun|deno|docker|kubectl|curl|cd|ls|mkdir|rm|export|xcodebuild|swift|make|ssh) [^\s]"#, 3),
            (#"\s--?[a-zA-Z][\w-]*"#, 1), (#"(\|\s*\w+|&&|\$\(|\$\{?\w+\}?)"#, 1),
        ]),
        Rule("html", [
            (#"<(!DOCTYPE|html|head|body|div|span|p|a|script|style|section)\b[^>]*>"#, 3), (#"</\w+>"#, 2),
        ]),
        Rule("css", [
            (#"^[ \t]*[.#]?[\w-]+([ \t]*[,>+~][ \t]*[.#]?[\w-]+|[ \t]+[.#]?[\w-]+)*[ \t]*\{[ \t]*$"#, 2),
            (#"^[ \t]*[\w-]+:[ \t]*[^;\n]+;[ \t]*$"#, 2),
        ]),
    ]

    static func displayName(of language: String) -> String {
        switch language {
        case "json": "JSON"
        case "sql": "SQL"
        case "html": "HTML"
        case "css": "CSS"
        case "typescript": "TypeScript"
        case "go": "Go"
        default: language.capitalized
        }
    }

    static func language(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 200_000 else { return nil }

        if isJSON(trimmed) { return "json" }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let sample = String(lines.prefix(200).joined(separator: "\n").prefix(20_000))
        let range = NSRange(sample.startIndex..., in: sample)

        var best: (language: String, score: Int)?
        for rule in rules {
            var score = 0
            for (regex, weight) in rule.patterns where regex.firstMatch(in: sample, range: range) != nil {
                score += weight
            }
            if score > (best?.score ?? 0) { best = (rule.language, score) }
        }

        guard let best else { return nil }
        let threshold = lines.count == 1 ? 3 : 4
        guard best.score >= threshold else { return nil }
        // Prose that merely mentions a keyword should not count: require some code punctuation.
        guard symbolDensity(sample) >= 0.02 || best.language == "shell" || best.language == "sql" else { return nil }
        return best.language
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func symbolDensity(_ text: String) -> Double {
        let symbols: Set<Character> = ["{", "}", "(", ")", "[", "]", ";", "=", "<", ">", ":", "\"", "'", "."]
        let count = text.reduce(0) { $0 + (symbols.contains($1) ? 1 : 0) }
        return Double(count) / Double(max(text.count, 1))
    }
}
