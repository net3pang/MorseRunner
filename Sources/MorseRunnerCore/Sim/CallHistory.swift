// Port of CallLst.pas — the Master.dta callsign list for CQ WPX and
// random QRM/DX-station calls.

import Foundation

/// Simple callsign list (port of `TCallList`).
final class CallList {
    private var calls: [String] = []

    init() {}

    var isEmpty: Bool { calls.isEmpty }

    func clear() {
        calls = []
    }

    /// Read callsigns from Master.dta (port of `LoadCallList`).
    /// Binary format: 1370×u32 index header (5480 bytes), then NUL-terminated
    /// sorted callsigns. Entries starting with 'VER2' are version stamps.
    func loadCallList() {
        calls = []
        guard let url = DataFiles.resourceURL("Master.dta") else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        let indexSize = 37 * 37 + 1   // 1370
        let indexBytes = indexSize * MemoryLayout<Int32>.size
        guard data.count >= indexBytes else { return }

        // validate header: FIndex[0] == INDEXBYTES and FIndex[last] == file size
        let first = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) }
        let last = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: (indexSize - 1) * 4, as: Int32.self) }
        guard first == Int32(indexBytes), last == Int32(data.count) else { return }

        // read the rest as NUL-terminated strings
        var list: [String] = []
        let body = data.dropFirst(indexBytes)
        var current = ""
        for byte in body {
            if byte == 0 {
                if !current.isEmpty {
                    if !current.hasPrefix("VER2") {
                        list.append(current)
                    }
                    current = ""
                }
            } else if byte < 128 {
                current.append(Character(UnicodeScalar(byte)))
            }
        }
        if !current.isEmpty, !current.hasPrefix("VER2") {
            list.append(current)
        }

        // dedupe via sort
        list.sort()
        var deduped: [String] = []
        for call in list where call != deduped.last {
            deduped.append(call)
        }
        calls = deduped
    }

    /// Random callsign; consumed (deleted) in HST mode (Delphi `PickCall`).
    func pickCall() -> String {
        if calls.isEmpty {
            return "P29SX"
        }
        let idx = Int.random(in: 0..<calls.count)
        let result = calls[idx]
        if Settings.runMode == .hst {
            calls.remove(at: idx)
        }
        return result
    }
}
