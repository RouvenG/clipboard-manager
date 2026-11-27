import Foundation

enum TransformError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

struct Transform: Identifiable {
    enum Action {
        case builtin((String) throws -> String)
        case script(URL)
    }

    let id: String
    let name: String
    let detail: String
    let action: Action
}

enum BuiltinTransforms {
    static let all: [Transform] = [
        Transform(id: "json.pretty", name: "JSON: Pretty", detail: "Indent JSON, keep key order", action: .builtin(JSONFormatter.pretty)),
        Transform(id: "json.minify", name: "JSON: Minify", detail: "Strip JSON whitespace", action: .builtin(JSONFormatter.minify)),
        Transform(id: "ws.trim", name: "Trim whitespace", detail: "Trim ends and trailing spaces per line", action: .builtin(Whitespace.trim)),
        Transform(id: "ws.blank", name: "Collapse blank lines", detail: "Squeeze runs of empty lines into one", action: .builtin(Whitespace.collapseBlankLines)),
        Transform(id: "ws.oneline", name: "Join into one line", detail: "Replace newlines and runs of spaces with one space", action: .builtin(Whitespace.singleLine)),
        Transform(id: "case.upper", name: "UPPERCASE", detail: "", action: .builtin { $0.uppercased() }),
        Transform(id: "case.lower", name: "lowercase", detail: "", action: .builtin { $0.lowercased() }),
        Transform(id: "case.title", name: "Title Case", detail: "", action: .builtin(CaseConverter.title)),
        Transform(id: "case.camel", name: "camelCase", detail: "", action: .builtin(CaseConverter.camel)),
        Transform(id: "case.pascal", name: "PascalCase", detail: "", action: .builtin(CaseConverter.pascal)),
        Transform(id: "case.snake", name: "snake_case", detail: "", action: .builtin(CaseConverter.snake)),
        Transform(id: "case.kebab", name: "kebab-case", detail: "", action: .builtin(CaseConverter.kebab)),
        Transform(id: "b64.encode", name: "Base64: Encode", detail: "UTF-8 to Base64", action: .builtin(Encoding.base64Encode)),
        Transform(id: "b64.decode", name: "Base64: Decode", detail: "Base64 to UTF-8", action: .builtin(Encoding.base64Decode)),
        Transform(id: "url.encode", name: "URL: Encode", detail: "Percent-encode for a query value", action: .builtin(Encoding.urlEncode)),
        Transform(id: "url.decode", name: "URL: Decode", detail: "Remove percent-encoding", action: .builtin(Encoding.urlDecode)),
    ]
}

nonisolated enum JSONFormatter {
    /// Re-indents without a parse/serialize round trip, so key order and number formatting survive.
    static func pretty(_ input: String) throws -> String {
        try validate(input)
        var out = ""
        var depth = 0
        var inString = false
        var escaped = false
        let indent = "  "
        let chars = Array(minifyUnchecked(input))
        for (index, char) in chars.enumerated() {
            if inString {
                out.append(char)
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
                continue
            }
            switch char {
            case "\"":
                inString = true
                out.append(char)
            case "{", "[":
                out.append(char)
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if next == "}" || next == "]" { continue }
                depth += 1
                out += "\n" + String(repeating: indent, count: depth)
            case "}", "]":
                let previous = index > 0 ? chars[index - 1] : nil
                if previous != "{" && previous != "[" {
                    depth -= 1
                    out += "\n" + String(repeating: indent, count: depth)
                }
                out.append(char)
            case ",":
                out += ",\n" + String(repeating: indent, count: depth)
            case ":":
                out += ": "
            default:
                out.append(char)
            }
        }
        return out
    }

    static func minify(_ input: String) throws -> String {
        try validate(input)
        return minifyUnchecked(input)
    }

    private static func minifyUnchecked(_ input: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for char in input {
            if inString {
                out.append(char)
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
                out.append(char)
            } else if !char.isWhitespace {
                out.append(char)
            }
        }
        return out
    }

    private static func validate(_ input: String) throws {
        guard let data = input.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            throw TransformError.failed("Not valid JSON")
        }
    }
}

nonisolated enum Whitespace {
    static func trim(_ input: String) -> String {
        input.components(separatedBy: "\n")
            .map { line in
                var line = line
                while let last = line.last, last == " " || last == "\t" || last == "\r" { line.removeLast() }
                return line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func collapseBlankLines(_ input: String) -> String {
        var out: [String] = []
        for line in input.components(separatedBy: "\n") {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank, let last = out.last, last.isEmpty { continue }
            out.append(blank ? "" : line)
        }
        return out.joined(separator: "\n")
    }

    static func singleLine(_ input: String) -> String {
        input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

nonisolated enum CaseConverter {
    /// Splits on separators and on lower-to-upper / acronym boundaries ("parseHTTPResponse" -> parse, HTTP, Response).
    static func words(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(input)
        for (index, char) in chars.enumerated() {
            guard char.isLetter || char.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            if let last = current.last, char.isUppercase {
                let nextIsLower = index + 1 < chars.count && chars[index + 1].isLowercase
                if last.isLowercase || last.isNumber || (last.isUppercase && nextIsLower) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(char)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    static func title(_ input: String) -> String {
        input.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    static func camel(_ input: String) -> String {
        let parts = words(input)
        guard let first = parts.first else { return input }
        return first.lowercased() + parts.dropFirst().map(capitalized).joined()
    }

    static func pascal(_ input: String) -> String {
        words(input).map(capitalized).joined()
    }

    static func snake(_ input: String) -> String {
        words(input).map { $0.lowercased() }.joined(separator: "_")
    }

    static func kebab(_ input: String) -> String {
        words(input).map { $0.lowercased() }.joined(separator: "-")
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}

nonisolated enum Encoding {
    static func base64Encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    static func base64Decode(_ input: String) throws -> String {
        var cleaned = input.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while cleaned.count % 4 != 0 { cleaned += "=" }
        guard let data = Data(base64Encoded: cleaned), let string = String(data: data, encoding: .utf8) else {
            throw TransformError.failed("Not Base64-encoded UTF-8 text")
        }
        return string
    }

    static func urlEncode(_ input: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
    }

    static func urlDecode(_ input: String) throws -> String {
        guard let decoded = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
            throw TransformError.failed("Invalid percent-encoding")
        }
        return decoded
    }
}
