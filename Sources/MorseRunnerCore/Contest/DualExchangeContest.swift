// Port of DualExchContest.pas — base for contests with asymmetric
// local/DX exchange fields (ARRL DX, NCJ NAQP).

import Foundation

/// Contest whose exchange types depend on whether the sending station is
/// local to the contest (port of `TDualExchContest`).
class DualExchangeContest: Contest {
    /// User's callsign is local to this contest (set by derived OnSetMyCall).
    var homeCallIsLocal = true
    /// Exchange types used when the station is local to the contest.
    var localTypes: ExchTypes
    /// Exchange types used when the station is DX to the contest.
    var dxTypes: ExchTypes

    init(local1: Exchange1Type, local2: Exchange2Type,
         dx1: Exchange1Type, dx2: Exchange2Type) {
        localTypes = ExchTypes(exch1: local1, exch2: local2)
        dxTypes = ExchTypes(exch1: dx1, exch2: dx2)
        super.init()
    }

    /// Karnough-map logic: HomeCallIsDX xor IsSimDxStation xor IsRecvMsgRequest
    override func getExchangeTypes(kind: StationKind, requestedMsgType: RequestedMsgType,
                                   stationCallsign: String, remoteCallsign: String) -> ExchTypes {
        let homeCallIsDX = !homeCallIsLocal
        let isSimDxStation = kind == .dxStation
        let isRecvMsgRequest = requestedMsgType == .recvMsg
        // 3-way xor; Bool != is xor and it is associative
        if (homeCallIsDX != isSimDxStation) != isRecvMsgRequest {
            return dxTypes
        }
        return localTypes
    }
}
