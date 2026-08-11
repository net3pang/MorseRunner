// Port of Util/SSExchParser.pas — the ARRL Sweepstakes exchange parsers.

import Foundation

/// Exchange token types (Delphi `TExchTokenType`).
enum ExchTokenType: Int {
    case eos = 0, digit1, digit2, digits, alpha, callsign, prec, sect
}

/// A classified exchange token (Delphi `TSSExchToken`).
final class SSExchToken {
    var tokenType = -1
    var value = ""
    var pos = -1

    init() {}

    init(_ token: ExchToken) {
        tokenType = token.tokenType
        value = token.value
        pos = token.pos
    }

    var isValid: Bool { tokenType != -1 }
}

/// SS lexer rules (Delphi `SSLexerRules`).
let ssLexerRules: [TokenRuleDef] = [
    // https://en.wikipedia.org/wiki/Amateur_radio_call_signs
    // the leading positive-lookbehind ensures whitespace precedes the call
    TokenRuleDef(
        regex: "(?<=\\b)([A-Z\\d]{2,}\\/)?([A-Z]{1,2}|\\d[A-Z]|[A-Z]\\d|\\d[A-Z]{2})([0-9])([A-Z\\d]*[A-Z])(\\/[A-Z\\d]+)?(\\/[A-Z\\d]+)?\\b",
        tokenType: ExchTokenType.callsign.rawValue),
    TokenRuleDef(regex: "\\d\\d\\d+", tokenType: ExchTokenType.digits.rawValue),
    TokenRuleDef(regex: "\\d\\d", tokenType: ExchTokenType.digit2.rawValue),
    TokenRuleDef(regex: "\\d", tokenType: ExchTokenType.digit1.rawValue),
    TokenRuleDef(regex: "[A-Z]+", tokenType: ExchTokenType.alpha.rawValue),
]

/// SS lexer with precedence/section classification (port of `TSSLexer`).
final class SSLexer: Lexer {
    private let sections: [String]

    init() {
        sections = ArrlSections.sectionsTbl.sorted()
        super.init(rules: ssLexerRules, skipWhitespace: true)
    }

    override func nextToken() throws -> ExchToken? {
        guard let token = try super.nextToken() else { return nil }
        var t = token
        switch ExchTokenType(rawValue: t.tokenType) {
        case .alpha:
            if t.value.count == 1 && "QABUMS".contains(t.value) {
                t.tokenType = ExchTokenType.prec.rawValue
            } else if binarySearch(sections, t.value) {
                t.tokenType = ExchTokenType.sect.rawValue
            }
        case .digit1:
            // treat '0' as a possible 2-digit <Chk> value ('0' -> '00')
            if t.value == "0" {
                t.tokenType = ExchTokenType.digit2.rawValue
                t.value = "00"
            }
        default:
            break
        }
        return t
    }

    func isValidCall(_ call: String) -> Bool {
        input(call)
        guard let token = try? nextToken() else { return false }
        return token.tokenType == ExchTokenType.callsign.rawValue
    }

    func isValidSection(_ section: String) -> Bool {
        binarySearch(sections, section)
    }

    private func binarySearch(_ list: [String], _ value: String) -> Bool {
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid] < value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo < list.count && list[lo] == value
    }
}

/// Validates the user's *sent* exchange (port of `TMyExchParser`).
/// Syntax: [nr | #] <Precedence> <Check> <Section>.
final class MyExchParser {
    /// Group names: exch1, nr, prec, chk, sect.
    private static let myExchRegExpr = "^ *(?<exch1>(?<nr>[0-9]+|#)? *(?<prec>[QABUMS])) +(?<chk>[0-9]{2}) *(?<sect>[A-Z]+) *$"
    private let regex = try! NSRegularExpression(pattern: MyExchParser.myExchRegExpr)

    private(set) var errorStr = ""

    /// Parse and validate; on success call `groupByName` for the fields.
    func parseMyExch(_ exchange: String) -> Bool {
        let range = NSRange(exchange.startIndex..., in: exchange)
        let matched = regex.firstMatch(in: exchange, range: range) != nil
        errorStr = ""
        if !matched {
            errorStr = "invalid exchange '\(exchange)'"
        }
        return matched
    }

    func groupByName(_ name: String, in exchange: String) -> String {
        let range = NSRange(exchange.startIndex..., in: exchange)
        guard let match = regex.firstMatch(in: exchange, range: range),
              let r = match.range(withName: name) as NSRange?,
              r.location != NSNotFound,
              let swiftRange = Range(r, in: exchange) else { return "" }
        return String(exchange[swiftRange])
    }
}

/// Incremental parser for the user-entered (received) SS exchange
/// (port of `TSSExchParser`).
final class SSExchParser {
    private let lexer = SSLexer()
    private var tokens: [SSExchToken] = []
    /// Each new 2-digit token is appended.
    private var twoDigitList: [SSExchToken] = []
    /// Each new check token is pushed.
    private var checkTokenStack: [SSExchToken] = []
    /// NR tokens not yet bound to a precedence.
    private var unboundNRs: [SSExchToken] = []

    private var previousCall = ""
    private var nrToken: SSExchToken?
    private var precedenceToken: SSExchToken?
    private var checkToken: SSExchToken?
    private var sectionToken: SSExchToken?
    private var isValidExchange = false
    private var exchError = ""

    // ---- parsed results
    private(set) var nr = 0
    private(set) var precedence = ""
    private(set) var check = ""
    private(set) var section = ""
    private(set) var call = ""

    /// Parsed exchange summary, e.g. '192A W7SST 72 OR'.
    var exchSummary: String {
        if nrToken != nil || checkToken != nil || precedenceToken != nil
            || sectionToken != nil || !call.isEmpty {
            return "\(nr)\(precedence) \(call.isEmpty ? previousCall : call) \(check) \(section)"
        }
        return ""
    }

    var error: String { exchError }

    func onWipeBoxes() {
        reset()
    }

    private func reset() {
        nrToken = nil
        precedenceToken = nil
        checkToken = nil
        sectionToken = nil
        tokens = []
        twoDigitList = []
        checkTokenStack = []
        unboundNRs = []
        nr = 0
        precedence = ""
        check = ""
        section = ""
        call = ""
        isValidExchange = false
    }

    /// Validate the entered exchange; memoized on unchanged input
    /// (Delphi `ValidateEnteredExchange`).
    @discardableResult
    func validateEnteredExchange(_ aCall: String, _ aExch1: String, _ aExch2: String) -> (valid: Bool, error: String) {
        // optimization: return if the input has not changed
        if aCall == previousCall && aExch2 == lexer.buf {
            return (isValidExchange, exchError)
        }

        reset()
        var nrIsBound = false

        do {
            lexer.input(aExch2)
            previousCall = aCall

            // Pass 1: build the token array; grab the callsign
            while let token0 = try lexer.nextToken() {
                if ExchTokenType(rawValue: token0.tokenType) == .callsign {
                    call = token0.value
                } else {
                    tokens.append(SSExchToken(token0))
                }
            }

            // Pass 2: process each token
            var skipNextToken = false
            var i = 0
            while i < tokens.count {
                if skipNextToken {
                    skipNextToken = false
                    i += 1
                    continue
                }
                let token = tokens[i]
                switch ExchTokenType(rawValue: token.tokenType) {
                case .digit1, .digits:
                    if (Int(token.value) ?? 0) > 10000 {
                        token.value = "10000"
                    }
                    // is the next token a possible Section value (length 2 or 3)?
                    if i + 1 < tokens.count,
                       let next = ExchTokenType(rawValue: tokens[i + 1].tokenType),
                       (next == .sect || next == .alpha),
                       tokens[i + 1].value.count == 2 || tokens[i + 1].value.count == 3 {
                        // verify the current token holds a valid Check value (00..99)
                        if (Int(token.value) ?? 999) < 100 {
                            checkToken = token
                            checkTokenStack = []
                            twoDigitList = []
                            nrIsBound = true
                            unboundNRs.append(token)
                            if ExchTokenType(rawValue: tokens[i + 1].tokenType) == .sect {
                                sectionToken = tokens[i + 1]
                            }
                        }
                        skipNextToken = true
                    } else {
                        // otherwise treat this token as a serial NR
                        nrToken = token
                        nrIsBound = true
                        unboundNRs.append(token)

                        // is the next token a Precedence value?
                        if i + 1 < tokens.count,
                           let next = ExchTokenType(rawValue: tokens[i + 1].tokenType),
                           (next == .prec || next == .alpha),
                           tokens[i + 1].value.count == 1 {
                            if next == .prec || "QABUMS".contains(tokens[i + 1].value) {
                                precedenceToken = tokens[i + 1]
                            }
                            skipNextToken = true
                        }
                    }

                case .digit2:
                    twoDigitList.append(token)

                    // is the next token a possible Precedence value (length 1)?
                    if i + 1 < tokens.count,
                       let next = ExchTokenType(rawValue: tokens[i + 1].tokenType),
                       (next == .prec || next == .alpha),
                       tokens[i + 1].value.count == 1 {
                        nrToken = token
                        twoDigitList = []
                        checkTokenStack = []
                        nrIsBound = true
                        if next == .prec || "QABUMS".contains(tokens[i + 1].value) {
                            precedenceToken = tokens[i + 1]
                            skipNextToken = true
                        }
                    }
                    // is the next token a possible Section token (length 2 or 3)?
                    else if i + 1 < tokens.count,
                            let next = ExchTokenType(rawValue: tokens[i + 1].tokenType),
                            (next == .sect || next == .alpha),
                            tokens[i + 1].value.count == 2 || tokens[i + 1].value.count == 3 {
                        if !nrIsBound && !checkTokenStack.isEmpty {
                            nrToken = checkTokenStack.last
                        }
                        checkToken = token
                        checkTokenStack = []
                        if next == .sect {
                            sectionToken = tokens[i + 1]
                        }
                        skipNextToken = true
                    }
                    // if Check/Section are bound, update Check
                    else if checkToken != nil && sectionToken != nil {
                        if !nrIsBound && !checkTokenStack.isEmpty {
                            nrToken = checkTokenStack.last
                        }
                        checkToken = token
                        checkTokenStack.append(checkToken!)
                    }
                    // otherwise update Chk and optionally NR
                    else {
                        if checkToken != nil && !nrIsBound && !checkTokenStack.isEmpty {
                            nrToken = checkTokenStack.last
                        }
                        checkToken = token
                        checkTokenStack.append(checkToken!)
                    }

                case .alpha:
                    // other character strings, not valid Precedence nor Section
                    if token.value.count == 2 {
                        // could be a 2x1 or 2x2 callsign
                        if !twoDigitList.isEmpty && nrToken != nil {
                            checkToken = twoDigitList.last
                            checkTokenStack.append(checkToken!)
                        } else if !unboundNRs.isEmpty {
                            checkToken = unboundNRs.removeLast()
                            checkTokenStack.append(checkToken!)
                            if !unboundNRs.isEmpty {
                                nrToken = unboundNRs.last
                            }
                        }
                    }

                case .prec:
                    precedenceToken = token
                    if nrToken != nil {
                        nrIsBound = true
                    }

                case .sect:
                    sectionToken = token

                case .eos, .callsign:
                    break
                case .none:
                    break
                }
                i += 1
            }

            if let nrToken { nr = Int(nrToken.value) ?? 0 }
            if let precedenceToken { precedence = precedenceToken.value }
            if let checkToken { check = String(format: "%02d", Int(checkToken.value) ?? 0) }
            if let sectionToken { section = sectionToken.value }

            if nrToken == nil {
                exchError = "Missing/Invalid Serial Number"
            } else if precedenceToken == nil {
                exchError = "Missing/Invalid Precedence"
            } else if checkToken == nil {
                exchError = "Missing/Invalid Check"
            } else if sectionToken == nil {
                exchError = "Missing/Invalid Section"
            } else {
                exchError = ""
            }
            isValidExchange = exchError.isEmpty

        } catch let e as InvalidDataError {
            exchError = e.message
            isValidExchange = false
        } catch {
            exchError = "lexer error"
            isValidExchange = false
        }

        return (isValidExchange, exchError)
    }
}
