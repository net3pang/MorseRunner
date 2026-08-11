// Port of QrmStn.pas / QrnStn.pas — interference sources.

import Foundation

/// Interfering station sending QRL?/CQ/QS? (port of `TQrmStation`).
final class QrmStation: Station {
    /// Number of times the station retries before disappearing.
    private var patience = 1

    override init() {
        super.init()
        initStation()
    }

    private func initStation() {
        super.initState()
        patience = 1 + Int.random(in: 0..<5)
        myCall = Contest.shared?.pickCallOnly() ?? "P29SX"
        hisCall = Settings.call
        amplitude = 5000 + 25000 * Float.random(in: 0..<1)
        pitch = bankersRound(RndFunc.gaussLim(mean: 0, limit: 300))
        wpmS = 30 + Int.random(in: 0..<20)
        wpmC = wpmS

        sentExchTypes = Contest.shared?.getSentExchTypes(kind: .dxStation, callsign: myCall) ?? .undef

        switch Int.random(in: 0..<7) {
        case 0: sendMsg(.qrl)
        case 1, 2: sendMsg(.qrl2)
        case 3, 4, 5: sendMsg(.longCQ)
        default: sendMsg(.qsy)
        }
    }

    override func processEvent(_ event: StationEvent) {
        switch event {
        case .msgSent:
            patience -= 1
            if patience == 0 {
                removeFromCollection()
            } else {
                timeout = bankersRound(RndFunc.gaussLim(
                    mean: Float(RndFunc.secondsToBlocks(4)),
                    limit: Float(RndFunc.secondsToBlocks(2))))
            }
        case .timeout:
            sendMsg(.longCQ)
        case .meStarted, .meFinished:
            break
        }
    }

    /// Replace '<his>' before the base class token processing, to bypass the
    /// special MyStation handling of '<his>' (Delphi override).
    override func sendText(_ aMsg: String) {
        super.sendText(aMsg.replacingOccurrences(of: "<his>", with: hisCall))
    }

    private func removeFromCollection() {
        Contest.shared?.stations.removeStation(self)
    }
}

/// Impulsive noise source (port of `TQrnStation`). Sends nothing; emits
/// random static crashes from a precomputed envelope.
final class QrnStation: Station {
    override init() {
        super.init()
        initStation()
    }

    private func initStation() {
        // QrnStation doesn't send messages: no call nor exchange types
        sentExchTypes = .undef

        let dur = RndFunc.secondsToBlocks(Float.random(in: 0..<1)) * Settings.bufSize
        var env = SampleArray(repeating: 0, count: dur)
        amplitude = 1e5 * pow(10, 2 * Float.random(in: 0..<1))
        for i in 0..<env.count {
            if Float.random(in: 0..<1) < 0.01 {
                env[i] = (Float.random(in: 0..<1) - 0.5) * amplitude
            }
        }
        envelope = env
        state = .sending
    }

    override func processEvent(_ event: StationEvent) {
        if event == .msgSent {
            removeFromCollection()
        }
    }

    private func removeFromCollection() {
        Contest.shared?.stations.removeStation(self)
    }
}
