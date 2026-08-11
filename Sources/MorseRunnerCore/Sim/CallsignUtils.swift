// Port of Util/CallsignUtils.pas — callsign extraction helpers.

import Foundation

enum CallsignUtils {
    /// Extract a callsign from free text (Code by BG4FQD).
    /// Regex: `(([0-9][A-Z])|([A-Z]{1,2}))[0-9][A-Z0-9]*[A-Z]`, accepted only
    /// at position 1 or preceded by '/'.
    static let callsignRegex = try! NSRegularExpression(pattern: "(([0-9][A-Z])|([A-Z]{1,2}))[0-9][A-Z0-9]*[A-Z]")

    static func extractCallsign(_ call: String) -> String {
        let range = NSRange(call.startIndex..., in: call)
        guard let match = callsignRegex.firstMatch(in: call, range: range) else { return "" }
        let offset = match.range.location
        if offset > 0 {
            let charBefore = call[call.index(call.startIndex, offsetBy: offset - 1)]
            guard charBefore == "/" else { return "" }
        }
        guard let r = Range(match.range, in: call) else { return "" }
        return String(call[r])
    }

    /// Extract the prefix from a callsign.
    /// - `deleteTrailingLetters: true` — WPX contest prefix with district
    ///   number (e.g. 'DL8').
    /// - `deleteTrailingLetters: false` — DXCC lookup prefix, keeps all
    ///   trailing characters ("longest match first", e.g. RC2F = Kaliningrad).
    static func extractPrefix(_ call: String, deleteTrailingLetters: Bool = true) -> String {
        // kill modifiers
        var c = call + "|"
        c = c.replacingOccurrences(of: "/QRP|", with: "")
        c = c.replacingOccurrences(of: "/MM|", with: "")
        c = c.replacingOccurrences(of: "/M|", with: "")
        c = c.replacingOccurrences(of: "/P|", with: "")
        c = c.replacingOccurrences(of: "|", with: "")
        c = c.replacingOccurrences(of: "//", with: "/")
        if c.count < 2 {
            return ""
        }

        var dig = ""
        var result: String

        // select the shorter piece
        if let p = c.firstIndex(of: "/") {
            let pos = c.distance(from: c.startIndex, to: p)
            if pos == 0 {
                result = String(c[c.index(after: p)...])
            } else if pos == c.count - 1 {
                result = String(c[c.startIndex..<p])
            } else {
                let s1 = String(c[c.startIndex..<p])
                let s2 = String(c[c.index(after: p)...])
                if s1.count == 1, let d = s1.first, d.isNumber {
                    dig = s1
                    result = s2
                } else if s2.count == 1, let d = s2.first, d.isNumber {
                    dig = s2
                    result = s1
                } else if s1.count <= s2.count {
                    result = s1
                } else {
                    result = s2
                }
            }
        } else {
            result = c
        }

        if result.contains("/") {
            return ""
        }

        if !deleteTrailingLetters {
            return result
        }

        // delete trailing letters, retain at least 2 chars
        var chars = Array(result)
        var p = chars.count - 1
        while p >= 2 {
            if chars[p].isNumber { break }
            chars.remove(at: p)
            p -= 1
        }
        result = String(chars)

        // ensure trailing digit
        if let last = result.last, !last.isNumber {
            result += "0"
        }
        // replace digit
        if !dig.isEmpty {
            chars = Array(result)
            chars[chars.count - 1] = Character(dig)
            result = String(chars)
        }

        return String(result.prefix(5))
    }
}
