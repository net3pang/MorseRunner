// Port of DxOper.pas — the simulated DX operator FSM.
//
// Each DX station owns an operator that runs a QSO state machine driven by
// the *set* of message classes the user sent during their last transmission.
// Callsign matching uses edit distance / '?' wildcards plus a confidence
// metric so partial copies resolve against the strongest caller.

import Foundation

let fullPatience = 5
let lowConfidence = 2

/// Operator states (Delphi `TOperatorState`).
public enum OperatorState: Int {
    case needPrevEnd = 0, needQso, needNr, needCall, needCallNr, needEnd, done, failed
}

/// Callsign match result (Delphi `TCallCheckResult`).
public enum CallCheckResult: Int {
    case no = 0, yes, almost
}

/// Port of `TDxOperator`.
public final class DxOperator {
    /// Random in [0,1) fixed at creation for consistent responses.
    private let r2: Float
    private var lastCheckedCall = ""
    private var lastCallCheck: CallCheckResult = .no

    public var call = ""
    /// 1..3
    public var skills = 1
    /// Retries before giving up; ghosting when it reaches 0.
    public var patience = 0
    public var repeatCnt = 1
    public var state: OperatorState = .needPrevEnd
    /// Confidence of the last partial-call match (0..100).
    public var callConfidence = 0
    /// Count of sent messages while waiting for NR (NR? every 3rd).
    public var sendNrQmCnt = 0
    /// Operator sent a call correction plus exchange in one message.
    public var correctedCallAndExchSent = false

    init(call: String, state: OperatorState) {
        r2 = Float.random(in: 0..<1)
        self.call = call
        skills = 1 + Int.random(in: 0..<3)  // 1..3
        patience = 0
        repeatCnt = 1
        setState(state)
        lastCheckedCall = ""
        lastCallCheck = .no
        callConfidence = 0
        sendNrQmCnt = 0
        correctedCallAndExchSent = false
    }

    /// Ghosting: patience exhausted, station stops transmitting but stays
    /// around to receive the final 'TU'.
    public var isGhosting: Bool { patience == 0 }

    // MARK: - timing

    public func getSendDelay() -> Int {
        if state == .needPrevEnd {
            return never
        } else if Settings.runMode == .hst {
            return RndFunc.secondsToBlocks(0.05 + 0.5 * Float.random(in: 0..<1) * 10 / Float(Settings.wpm))
        } else {
            return RndFunc.secondsToBlocks(0.1 + 0.5 * Float.random(in: 0..<1))
        }
    }

    /// Sending speed; AWpmC carries the Farnsworth character speed.
    public func getWpm() -> (wpm: Int, wpmC: Int) {
        var result: Int
        let maxRxWpm = Settings.maxRxWpm
        let minRxWpm = Settings.minRxWpm
        if Settings.runMode == .hst {
            result = Settings.wpm
        } else if maxRxWpm == -1 || minRxWpm == -1 {
            // original algorithm
            result = bankersRound(Float(Settings.wpm) * 0.5 * (1 + Float.random(in: 0..<1)))
        } else if Settings.getWpmUsesGaussian {
            // Gaussian with limit: [Wpm-Min, Wpm+Max]
            let mean = Float(Settings.wpm) + Float(-minRxWpm + maxRxWpm) / 2
            let limit = Float(minRxWpm + maxRxWpm) / 2
            result = bankersRound(RndFunc.gaussLim(mean: mean, limit: limit))
        } else {
            result = bankersRound(Float(Settings.wpm - minRxWpm) + Float(minRxWpm + maxRxWpm) * Float.random(in: 0..<1))
        }

        if Settings.allStationsWpmS > 10 {
            result = Settings.allStationsWpmS
        }

        let wpmC: Int
        if Contest.shared?.isFarnsworthAllowed == true && result < Settings.farnsworthCharRate {
            wpmC = Settings.farnsworthCharRate
        } else {
            wpmC = result
        }
        return (result, wpmC)
    }

    /// Serial number for HST / start-of-contest mode.
    public func getNR() -> Int {
        assert(Settings.runMode == .hst || Settings.serialNR == .startContest)
        return 1 + bankersRound(Float.random(in: 0..<1) * Float(Contest.shared?.minute ?? 0) * Float(skills))
    }

    public func getName() -> String { "ALEX" }

    /// Timeout waiting for a reply after sending, in blocks.
    public func getReplyTimeout() -> Int {
        var result: Float
        if Settings.runMode == .hst {
            result = Float(RndFunc.secondsToBlocks(60.0 / Float(Settings.wpm)))
        } else {
            result = Float(RndFunc.secondsToBlocks(Float(6 - skills)))
        }
        return bankersRound(RndFunc.gaussLim(mean: result, limit: result / 2))
    }

    // MARK: - patience

    public func decPatience() {
        if state == .done { return }
        if patience > 0 { patience -= 1 }
        if patience < 1 && (state == .needPrevEnd || state == .needQso) {
            state = .failed
        }
    }

    public func morePatience(_ value: Int = 0) {
        if state == .done { return }
        if value > 0 {
            patience = min(value, fullPatience)
        } else if patience < fullPatience {
            if Settings.runMode == .single {
                patience = 4
            } else if patience == 0 {
                patience = 3   // immediately decremented, leaving 2 retries
            } else {
                patience = min(patience + 2, 4)
            }
        }
    }

    /// Set a new state and recompute patience (Delphi `SetState`).
    public func setState(_ newState: OperatorState) {
        state = newState

        // osNeedQso patience: 3 + Rayleigh(3) -> [4,14], mean 6 (ghosting fix, Issue #200)
        if newState == .needQso {
            patience = 3 + bankersRound(RndFunc.rayleigh(mean: 3))
        } else {
            patience = fullPatience
        }

        if newState == .needQso && !(Settings.runMode == .single || Settings.runMode == .hst)
            && Float.random(in: 0..<1) < 0.1 {
            repeatCnt = 2
        } else {
            repeatCnt = 1
        }

        if newState == .needQso {
            correctedCallAndExchSent = false
        }
        if newState == .needNr {
            sendNrQmCnt = 0
        }
    }

    // MARK: - callsign matching

    /// Compare the user-entered pattern against this operator's call
    /// (Delphi `IsMyCall`). Supports '?' wildcards, edit distance, and
    /// substring matches, returning a confidence 0..100.
    public func isMyCall(_ pattern: String, randomResult: Bool) -> CallCheckResult {
        let c0 = call

        if lastCheckedCall == pattern {
            return lastCallCheck
        }
        lastCheckedCall = pattern

        var result: CallCheckResult = .no

        if pattern.contains("?") {
            // regex search: '?' matches one char, trailing '?' matches rest
            var regexStr = pattern.replacingOccurrences(of: "?", with: ".")
            if pattern.hasSuffix("?") {
                regexStr += "*"
            }
            do {
                let regex = try NSRegularExpression(pattern: regexStr)
                let range = NSRange(c0.startIndex..., in: c0)
                if regex.firstMatch(in: c0, range: range) != nil {
                    result = .almost
                    let p = c0.count - pattern.replacingOccurrences(of: "?", with: "").count
                    callConfidence = 100 * (c0.count - p) / c0.count
                    if callConfidence == 0 {
                        callConfidence = lowConfidence
                    }
                } else {
                    result = .no
                    callConfidence = 0
                }
            } catch {
                result = .no
                callConfidence = 0
            }
        } else {
            // dynamic programming edit distance
            let a = Array(pattern)
            let b = Array(c0)
            var m = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
            for x in 0...a.count { m[x][0] = x }
            for y in 0...b.count { m[0][y] = y }
            for x in 1...a.count {
                for y in 1...b.count {
                    if a[x - 1] == b[y - 1] {
                        m[x][y] = m[x - 1][y - 1]
                    } else {
                        m[x][y] = 1 + min(m[x][y - 1], m[x - 1][y], m[x - 1][y - 1])
                    }
                }
            }
            let p = m[a.count][b.count]
            var substringFallback = false
            if p == 0 {
                result = .yes
            } else if p <= (c0.count - 1) / 2 {
                result = .almost
            } else {
                result = .no
            }

            // partial match: pattern found anywhere within the call.
            // Delphi reassigns P = C0.Length - APattern.Length here.
            if result == .no && c0.contains(pattern) {
                result = .almost
                substringFallback = true
            }

            switch result {
            case .yes:
                callConfidence = 100
            case .almost:
                let pp = substringFallback ? (c0.count - pattern.count) : p
                callConfidence = 100 * (c0.count - pp) / c0.count
                if callConfidence == 0 {
                    callConfidence = lowConfidence
                }
            case .no:
                callConfidence = 0
            }
        }

        lastCallCheck = result

        // LID tolerance: accept a wrong call, or reject the correct one
        if randomResult && Settings.lids && pattern.count > 3 && !pattern.contains("?") {
            switch result {
            case .yes:
                if Float.random(in: 0..<1) < 0.01 {
                    // LID rejects correct call
                    result = .almost
                    callConfidence = 100 * (c0.count - 1) / c0.count
                }
            case .almost:
                if Float.random(in: 0..<1) < 0.04 {
                    // LID accepts a wrong call
                    result = .yes
                    callConfidence = 100
                }
            case .no:
                break
            }
        }
        return result
    }

    /// Demote a partial match when a stronger caller exists (Delphi
    /// `CallConfidenceCheck`).
    public func callConfidenceCheck(_ call: String, randomResult: Bool) -> CallCheckResult {
        let result = isMyCall(call, randomResult: randomResult)
        if result == .almost && callConfidence < (Contest.shared?.stations.bestMatchConfidence ?? 0) {
            return .no
        }
        return result
    }

    /// Active in the QSO if confidence meets/exceeds the best match.
    public var isActiveInQso: Bool {
        callConfidence >= (Contest.shared?.stations.bestMatchConfidence ?? 0)
            || (Contest.shared?.stations.bestMatchCallsign == call)
    }

    // MARK: - message handling

    /// Receive the set of messages the user sent (Delphi `MsgReceived`).
    public func msgReceived(_ aMsg: StationMessages) {
        // CQ received: we can call no matter what else was sent
        if aMsg.contains(.cq) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decPatience()
            case .needNr, .needCall, .needCallNr: state = .failed
            case .needEnd: state = .done
            case .done, .failed: break
            }
            return
        }

        if aMsg.contains(.nil_) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decPatience()
            case .needNr, .needCall, .needCallNr, .needEnd: state = .failed
            case .done, .failed: break
            }
            return
        }

        if aMsg.contains(.hisCall) {
            switch callConfidenceCheck(Contest.shared?.me.hisCall ?? "", randomResult: true) {
            case .yes:
                if state == .needPrevEnd || state == .needQso { setState(.needNr) }
                else if state == .needCallNr { setState(.needNr) }
                else if state == .needNr || state == .needEnd { morePatience() }
                else if state == .needCall { setState(.needEnd) }
                else { break }
            case .almost:
                if state == .needPrevEnd || state == .needQso { setState(.needCallNr) }
                else if state == .needCallNr || state == .needCall { morePatience() }
                else if state == .needNr { setState(.needCallNr) }
                else if state == .needEnd { setState(.needCall) }
                else { break }
            case .no:
                if state == .needQso { state = .needPrevEnd }
                else if state == .needNr || state == .needCall || state == .needCallNr { state = .needPrevEnd }
                else if state == .needEnd { state = .done }
                else { break }
            }
        }

        if aMsg.contains(.b4) {
            switch state {
            case .needPrevEnd, .needQso: setState(.needQso)
            case .needNr, .needEnd: state = .failed
            case .needCall, .needCallNr: break // same state: correct the call
            case .done, .failed: break
            }
        }

        if aMsg.contains(.nr) {
            switch state {
            case .needPrevEnd: break
            case .needQso: state = .needPrevEnd
            case .needNr:
                if Float.random(in: 0..<1) < 0.9 || Settings.runMode == .hst || Settings.runMode == .single {
                    setState(.needEnd)
                } else {
                    morePatience()
                }
            case .needCall: morePatience()
            case .needCallNr:
                if Float.random(in: 0..<1) < 0.9 || Settings.runMode == .hst || Settings.runMode == .single {
                    setState(.needCall)
                } else {
                    morePatience()
                }
            case .needEnd: morePatience()
            case .done, .failed: break
            }
        }

        if aMsg.contains(.tu) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: setState(.needQso)
            case .needNr:
                if isActiveInQso { state = .done } else { setState(.needQso) }
            case .needCall:
                if isActiveInQso { state = .done } else { setState(.needQso) }
            case .needCallNr:
                if isActiveInQso && correctedCallAndExchSent { state = .done } else { setState(.needQso) }
            case .needEnd: state = .done
            case .done, .failed: break
            }
        }

        if aMsg.contains(.qm) {
            switch state {
            case .needPrevEnd:
                if SimEngine.shared.uiHooks.enteredCall.isEmpty { setState(.needQso) }
            case .needQso: break
            case .needNr, .needCall, .needCallNr, .needEnd: morePatience()
            case .done, .failed: break
            }
        }

        // msgGarbage: station was sending and missed part/all of the message
        if !Settings.lids && aMsg == .garbage {
            switch state {
            case .needPrevEnd, .needEnd, .done, .failed: break
            case .needQso, .needNr, .needCall, .needCallNr: morePatience()
            }
        }

        if state != .needPrevEnd {
            decPatience()
        }
    }

    // MARK: - replies

    /// Choose the reply message for the current state (Delphi `GetReply`).
    public func getReply() -> StationMessage {
        if isGhosting {
            return .none
        }
        switch state {
        case .needPrevEnd, .done, .failed:
            return .none
        case .needQso:
            return .myCall
        case .needNr:
            let postInc: Int = {
                let v = sendNrQmCnt
                sendNrQmCnt += 1
                return v
            }()
            if patience == fullPatience - 1   // first occurrence
                || postInc % 3 == 0           // every 3rd subsequent
                || Float.random(in: 0..<1) < 0.2 {
                return .nrQm
            }
            return .agn
        case .needCall:
            // have their Exch, need user to correct my call
            if Settings.runMode == .hst {
                return .deMyCallNr1
            } else if Settings.simContest == .arrlSS {
                switch Int(trunc(r2 * 3)) {
                case 0: return .deMyCallNr1
                default: return .myCallNr1
                }
            } else {
                switch Int(trunc(r2 * 6)) {
                case 0: return .deMyCallNr1
                case 1: return .deMyCallNr2
                case 2, 3: return .myCallNr1
                case 4: return .myCallNr2
                default: return .myCall
                }
            }
        case .needCallNr:
            // they sent an almost-correct callsign
            if Settings.runMode == .hst {
                return .deMyCall1
            }
            switch Int(trunc(r2 * 6)) {
            case 0: return .deMyCall1
            case 1: return .deMyCall2
            case 2, 3: return .myCall
            case 4: return .myCall2
            default:
                // LIDs occasionally send exchange before copying it
                if Settings.lids && r2 < 0.88 {
                    correctedCallAndExchSent = true
                    return .myCallNr1
                } else if r2 < 0.95 {
                    return .myCall
                } else {
                    return .myCall2
                }
            }
        case .needEnd:
            if patience < fullPatience - 1 {
                return .nr
            } else if Settings.runMode == .hst || Settings.simContest == .arrlSS
                || Float.random(in: 0..<1) < 0.9 {
                return .rNR
            } else {
                return .rNR2
            }
        }
    }
}
