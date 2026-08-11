// Port of SerNRGen.pas — serial-number generator matching a sample
// distribution from a prior contest (F6FVY's 2023 CQ WPX data).

import Foundation

/// One bin of the sample distribution (Delphi `TSerNRSampleBin`).
struct SerNRSampleBin {
    var b: UInt16   // starting serial number for this bin
    var c: UInt16   // number of samples (logs/entries) in this bin
}

/// Generates random serial numbers following a sample distribution
/// (Delphi `TSerialNRGen`).
final class SerialNRGen {
    struct SerialNRItem {
        var idRangeBegin: UInt16    // serial number range starting value
        var idRangeWidth: UInt16    // bin width
        var cummulativeCnt: UInt16  // running cummulative total count

        func getNR() -> Int {
            Int(idRangeBegin) + Int.random(in: 0..<Int(idRangeWidth))
        }
    }

    private(set) var serialNrTbl: [SerialNRItem] = []
    private var lowIdx = 0
    private var highIdx = 0
    private var sum: UInt16 = 0

    init() {}

    /// Simple user-defined range without a distribution table.
    func addRange(_ range: SerialNumberSettings) {
        serialNrTbl = [SerialNRItem]()
        sum = 1
        serialNrTbl.append(SerialNRItem(
            idRangeBegin: UInt16(range.minVal),
            idRangeWidth: UInt16(range.maxVal - range.minVal),
            cummulativeCnt: sum))
        lowIdx = 0
        highIdx = 0
    }

    /// Slice a sample-bin table for the given range and build running totals.
    func addDistribution(_ range: SerialNumberSettings, sampleTbl: [SerNRSampleBin]) {
        sum = 0
        switch range.minVal {
        case 50: lowIdx = 5
        case 500: lowIdx = 14
        default: assertionFailure("unsupported MinVal \(range.minVal)")
        }
        switch range.maxVal {
        case 500: highIdx = 13
        case 5000: highIdx = 58
        default: assertionFailure("unsupported MaxVal \(range.maxVal)")
        }

        var items = [SerialNRItem]()
        for i in lowIdx...highIdx {
            sum += sampleTbl[i].c
            assert(i + 1 < sampleTbl.count)
            items.append(SerialNRItem(
                idRangeBegin: sampleTbl[i].b,
                idRangeWidth: sampleTbl[i + 1].b - sampleTbl[i].b,
                cummulativeCnt: sum))
        }
        serialNrTbl = items
    }

    var entryCount: UInt16 {
        sum
    }

    /// Find the first bin whose accumulated count >= `count`
    /// (Delphi `TArray.BinarySearch` lower-bound semantics).
    func findBin(_ count: UInt16) -> Int {
        let last = serialNrTbl[serialNrTbl.count - 1].cummulativeCnt
        assert(count <= last)
        let c = min(count, last)
        // lower_bound
        var lo = 0, hi = serialNrTbl.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if serialNrTbl[mid].cummulativeCnt < c {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    func getNR() -> Int {
        let entryCount = serialNrTbl[serialNrTbl.count - 1].cummulativeCnt
        let foundIdx = findBin(UInt16(Int.random(in: 1...Int(entryCount))))
        return serialNrTbl[foundIdx].getNR()
    }
}
