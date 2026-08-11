// Port of Util/Lexer.pas — a simple anchored-regex tokenizer.

import Foundation

/// One lexer rule: a regex and its token type (Delphi `TTokenRuleDef`).
struct TokenRuleDef {
    let regex: String
    let tokenType: Int
}

/// A token produced by the lexer (Delphi `TExchToken`).
struct ExchToken {
    var tokenType = -1
    var value = ""
    var pos = 0
}

/// Error thrown on unmatched input (Delphi `EInvalidData`).
struct InvalidDataError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Regex-based tokenizer with anchored rules (port of `TLexer`).
/// Each rule must match at the current position; whitespace is skipped
/// when `skipWhitespace` is true.
class Lexer {
    private var rules: [(regex: NSRegularExpression, tokenType: Int)] = []
    private let skipWhitespace: Bool
    private var pos = 0
    private(set) var buf = ""

    init(rules: [TokenRuleDef], skipWhitespace: Bool = true) {
        self.skipWhitespace = skipWhitespace
        for def in rules {
            if let regex = try? NSRegularExpression(pattern: "^(?:\(def.regex))") {
                self.rules.append((regex, def.tokenType))
            }
        }
    }

    /// Begin lexing a new buffer (Delphi `Input`).
    func input(_ abuf: String) {
        buf = abuf
        pos = 0
    }

    /// Next token; nil at end of input; throws on unmatched data
    /// (Delphi `NextToken`, `EInvalidData`).
    func nextToken() throws -> ExchToken? {
        // Delphi: Pos 1..Length, EOF when Pos = Length+1; 0-indexed: pos >= count
        guard pos < buf.count else {
            return nil
        }

        if skipWhitespace {
            // skip whitespace at the current position
            let remaining = String(buf.dropFirst(pos))
            let wsRange = NSRange(location: 0, length: remaining.utf16.count)
            let wsRegex = try! NSRegularExpression(pattern: "^\\s*")
            if let m = wsRegex.firstMatch(in: remaining, range: wsRange) {
                pos += (remaining as NSString).substring(with: m.range).count
            }
            guard pos < buf.count else {
                return nil
            }
        }

        let remaining = String(buf.dropFirst(pos))
        let searchRange = NSRange(location: 0, length: remaining.utf16.count)
        for (regex, tokenType) in rules {
            if let m = regex.firstMatch(in: remaining, range: searchRange) {
                let value = (remaining as NSString).substring(with: m.range)
                let token = ExchToken(tokenType: tokenType, value: value, pos: pos)
                pos += value.count
                return token
            }
        }

        // no rule matched
        let ch = buf.dropFirst(pos).prefix(1)
        throw InvalidDataError(message: "Invalid data (\(ch)) at position \(pos + 1)")
    }
}
