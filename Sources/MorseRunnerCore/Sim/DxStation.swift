// Port of DxStn.pas — one pile-up caller.

import Foundation

/// A DX station in the pile-up (port of `TDxStation`).
public final class DxStation: Station {
    /// Fading generator applied to this station's block.
    private var qsb = Qsb()
    /// Operator FSM driving the QSO.
    public var oper: DxOperator!
    /// Index into the contest caller list (`Tst.PickStation`); -1 after HST drop.
    public var operid = -1

    override init() {
        super.init()
        createStation()
    }

    private func createStation() {
        guard let contest = Contest.shared else { fatalError("Contest must exist before DxStation") }

        hisCall = Settings.call

        // pick one callsign from the contest call history
        operid = contest.pickStation()
        myCall = contest.getCall(operid)

        oper = DxOperator(call: myCall, state: .needPrevEnd)
        nrWithError = Settings.lids && Float.random(in: 0..<1) < 0.1

        // DX speed is set once at creation
        let speeds = oper.getWpm()
        wpmS = speeds.wpm
        wpmC = speeds.wpmC

        // DX's sent exchange types depend on station kind and callsign
        sentExchTypes = contest.getSentExchTypes(kind: .dxStation, callsign: myCall)

        // load dynamic exchange field info into this station
        contest.getExchange(operid, into: self)

        if Settings.lids && Float.random(in: 0..<1) < 0.03 {
            rst = 559 + 10 * Int.random(in: 0..<4)
        } else {
            rst = 599
        }

        qsb = Qsb()
        qsb.setBandwidth(0.1 + Float.random(in: 0..<1) / 2)
        if Settings.flutter && Float.random(in: 0..<1) < 0.3 {
            qsb.setBandwidth(3 + Float.random(in: 0..<1) * 30)
        }

        amplitude = 9000 + 18000 * (1 + RndFunc.uShaped())
        if Settings.runMode == .single {
            pitch = bankersRound(RndFunc.gaussLim(mean: 0, limit: 50))
        } else {
            pitch = bankersRound(RndFunc.gaussLim(mean: 0, limit: 300))
        }

        if Settings.runMode == .hst {
            contest.dropStation(operid)
            operid = -1
        }

        // the MeSent event follows immediately
        timeout = never
        state = .copying
    }

    override func processEvent(_ event: StationEvent) {
        guard oper.state != .done else { return }

        switch event {
        case .msgSent:
            // we finished sending and started listening
            if Contest.shared?.me.state == .sending {
                timeout = never
            } else {
                timeout = oper.getReplyTimeout()
            }

        case .timeout:
            // he did not reply: quit or try again
            if state == .listening {
                oper.msgReceived(.none)
                if oper.state == .failed {
                    SimEngine.shared.debugGhosting?("[\(myCall)-osFailed], Stn deleted")
                    removeFromCollection()
                    return
                }
                if oper.isGhosting {
                    // ghosting: stop transmitting but stay to receive final messages
                    state = .listening
                } else {
                    state = .preparingToSend
                }
            }

            // preparations are done, now send
            if state == .preparingToSend {
                for _ in 1...oper.repeatCnt {
                    sendMsg(oper.getReply())
                }
            }

        case .meFinished:
            // we notice the message only if we are not sending ourselves
            if state != .sending {
                let myMsg = Contest.shared?.me.msg ?? []
                // interpret the message
                switch state {
                case .copying:
                    oper.msgReceived(myMsg)
                case .listening, .preparingToSend:
                    // these messages can be copied even if partially received
                    if myMsg.contains(.cq) || myMsg.contains(.tu) || myMsg.contains(.nil_) {
                        oper.msgReceived(myMsg)
                    } else {
                        oper.msgReceived(.garbage)
                    }
                case .sending:
                    break
                }

                // react to the message
                if oper.state == .failed {
                    SimEngine.shared.debugGhosting?("[\(myCall)-osFailed, Stn deleted]")
                    removeFromCollection()
                    return
                }
                if oper.isGhosting {
                    state = .listening
                } else {
                    timeout = oper.getSendDelay()  // reply or switch to standby
                    state = .preparingToSend
                }
            } else if state == .sending {
                // special case: user sent 'TU' while we are re-sending our call
                if oper.state == .needCall, let myMsg = Contest.shared?.me.msg, myMsg.contains(.tu) {
                    oper.msgReceived(myMsg)
                }
            }

        case .meStarted:
            // if we are not sending, we can start copying
            if state != .sending {
                assert(state == .preparingToSend || state == .listening)
                state = .copying
            }
            timeout = never
        }
    }

    /// Copy this station's true data into the last QSO and remove self
    /// from the collection (Delphi `DataToLastQso`).
    func dataToLastQso() {
        Contest.shared?.logDxStationData(self)
        removeFromCollection()
    }

    private func removeFromCollection() {
        Contest.shared?.stations.removeStation(self)
    }

    override func getBlock() -> SampleArray {
        var result = super.getBlock()
        if Settings.qsb {
            qsb.applyTo(&result)
        }
        return result
    }
}
