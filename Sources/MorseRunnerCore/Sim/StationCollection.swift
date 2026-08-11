// Port of StnColl.pas — the collection of active stations.

import Foundation

/// Collection of active simulation stations (port of `TStations`).
public final class StationCollection {
    public private(set) var items: [Station] = []

    /// Max confidence of the best matching caller (init 1 — rejects all mcNo).
    var bestMatchConfidence = 1
    /// Callsign with the highest confidence.
    var bestMatchCallsign = ""

    init() {}

    public var count: Int { items.count }

    subscript(index: Int) -> Station {
        items[index]
    }

    func removeStation(_ station: Station) {
        items.removeAll { $0 === station }
    }

    func removeAll() {
        items.removeAll()
    }

    private func callsignExists(_ aCall: String) -> Bool {
        items.contains { $0.myCall == aCall }
    }

    /// Add a caller, retrying up to 10 times to avoid duplicate callsigns
    /// (Delphi `AddCaller`).
    @discardableResult
    func addCaller() -> Station? {
        var cnt = 10
        var result: Station? = nil
        while result == nil {
            let station = DxStation()
            cnt -= 1
            if cnt == 0 { break }
            if callsignExists(station.myCall) {
                continue
            }
            result = station
        }
        if let station = result {
            items.append(station)
        }
        return result
    }

    @discardableResult
    func addQrn() -> Station {
        let station = QrnStation()
        items.append(station)
        return station
    }

    @discardableResult
    func addQrm() -> Station {
        let station = QrmStation()
        items.append(station)
        return station
    }

    /// Remove the strongest active DX station for a 'NIL' (Delphi
    /// `DropCallerForNil`). Returns (call, wasActive).
    @discardableResult
    func dropCallerForNil() -> (call: String, active: Bool)? {
        var target: DxStation? = nil
        var active = false

        func pick(_ dx: DxStation, _ act: Bool) {
            if target == nil || dx.amplitude > target!.amplitude {
                target = dx
                active = act
            }
        }

        // 1st pass: operators actively engaged in a QSO
        for i in stride(from: items.count - 1, through: 0, by: -1) {
            if let dx = items[i] as? DxStation {
                if [.needNr, .needCall, .needCallNr, .needEnd].contains(dx.oper.state) {
                    pick(dx, true)
                }
            }
        }
        // 2nd pass: stations currently sending
        if target == nil {
            for i in stride(from: items.count - 1, through: 0, by: -1) {
                if let dx = items[i] as? DxStation, dx.state == .sending {
                    pick(dx, false)
                }
            }
        }
        // 3rd pass: idle callers
        if target == nil {
            for i in stride(from: items.count - 1, through: 0, by: -1) {
                if let dx = items[i] as? DxStation,
                   [.needQso, .needPrevEnd].contains(dx.oper.state) {
                    pick(dx, false)
                }
            }
        }

        guard let t = target else { return nil }
        let call = t.myCall
        t.envelope = nil
        t.oper.state = .failed
        removeStation(t)
        return (call, active)
    }

    /// Visit all DX stations and compute the confidence of each match against
    /// the entered call, retaining the maximum (Delphi `FindBestMatches`).
    func findBestMatches(_ enteredCall: String) {
        bestMatchConfidence = 1
        bestMatchCallsign = ""
        for i in stride(from: items.count - 1, through: 0, by: -1) {
            if let dx = items[i] as? DxStation {
                let r = dx.oper.isMyCall(enteredCall, randomResult: false)
                assert(r == .no || dx.oper.callConfidence > 0)
                if dx.oper.callConfidence > bestMatchConfidence {
                    bestMatchCallsign = dx.oper.call
                    bestMatchConfidence = dx.oper.callConfidence
                }
            }
        }
    }
}
