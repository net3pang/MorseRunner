// Port of MorseKey.pas / FarnsKeyer.pas — text-to-CW-envelope keyers.
//
// TKeyer encodes text into a CW waveform envelope (0/1 samples with
// Blackman-Harris shaped rise/fall ramps). TFarnsKeyer adds Farnsworth
// spacing: characters are sent at WpmC while inter-character/inter-word
// spacing is stretched so the overall speed is WpmS (WpmS <= WpmC).

import Foundation

/// Global keyer singleton (port of the Delphi `Keyer` global).
/// Replaced when the contest changes (FarnsKeyer for K1USN SST).
extension Keyer {
    nonisolated(unsafe) static var shared: Keyer = Keyer()
}

/// Base keyer (port of `TKeyer`).
class Keyer {
    /// Morse code lookup: char -> dit/dash string with trailing marker
    /// (' ' for TKeyer, '^' for TFarnsKeyer).
    var morse: [Character: String] = [:]

    var rampLen: Int = 0
    var rampOn: SampleArray = []
    var rampOff: SampleArray = []

    /// Sending speed (set by UI) and character speed (INI, default 25 wpm).
    var wpmS = 0
    var wpmC = 0

    var bufSize = AudioConstants.defaultBufSize
    var rate = AudioConstants.defaultRate
    /// Encoded Morse message (dit/dash + markers) currently being rendered.
    var morseMsg = ""
    var trueEnvelopeLen = 0

    var riseTime: Float = 0.005 {
        didSet { makeRamp() }
    }

    init(rate: Int = AudioConstants.defaultRate, bufSize: Int = AudioConstants.defaultBufSize) {
        self.rate = rate
        self.bufSize = bufSize
        loadMorseTable()
        riseTime = 0.005
    }

    func setWpm(_ s: Int, _ c: Int = 0) {
        wpmS = s
        wpmC = c
    }

    /// Load MorseTable with a trailing space (standard inter-char spacing).
    func loadMorseTable() {
        for (ch, code) in MorseTable.entries {
            morse[ch] = code + " "
        }
    }

    private func blackmanHarrisKernel(_ x: Float) -> Float {
        let a0: Float = 0.35875, a1: Float = 0.48829
        let a2: Float = 0.14128, a3: Float = 0.01168
        return a0 - a1 * cos(2 * Float.pi * x) + a2 * cos(4 * Float.pi * x) - a3 * cos(6 * Float.pi * x)
    }

    private func blackmanHarrisStepResponse(_ len: Int) -> SampleArray {
        precondition(len > 0)
        var result = SampleArray(repeating: 0, count: len)
        for i in 0..<len {
            result[i] = blackmanHarrisKernel(Float(i) / Float(len))
        }
        for i in 1..<len {
            result[i] = result[i - 1] + result[i]
        }
        let scale = 1 / result[len - 1]
        for i in 0..<len {
            result[i] *= scale
        }
        return result
    }

    private func makeRamp() {
        rampLen = bankersRound(2.7 * riseTime * Float(rate))
        rampOn = blackmanHarrisStepResponse(rampLen)
        rampOff = SampleArray(repeating: 0, count: rampLen)
        for i in 0..<rampLen {
            rampOff[rampLen - 1 - i] = rampOn[i]
        }
    }

    /// Encode text into Morse symbols. ' ' and '_' become word spacing;
    /// the final symbol is replaced with '~' (end-of-message marker, ~5U).
    func encode(_ txt: String) -> String {
        var result = ""
        for ch in txt {
            if ch == " " || ch == "_" {
                result += " "
            } else if let code = morse[ch] {
                result += code
            }
        }
        if !result.isEmpty {
            result = String(result.dropLast()) + "~"
        }
        return result
    }

    /// Render the current MorseMsg into a sample envelope padded to whole blocks.
    func getEnvelope() -> SampleArray {
        precondition(wpmS > 0, "must init using setWpm()")

        // count units: dit = 1U on + 1U spacing; dash = 3U + 1U; char space 2U; EOM 3U
        var unitCnt = 0
        for ch in morseMsg {
            switch ch {
            case ".": unitCnt += 2
            case "-": unitCnt += 4
            case " ": unitCnt += 2
            case "~": unitCnt += 3
            default: break
            }
        }

        // 48U = one word including 5U inter-word space
        let samplesInUnit = bankersRound(60.0 / 48.0 * Double(rate) / Double(wpmS))
        trueEnvelopeLen = unitCnt * samplesInUnit
        let len = bufSize * Int(ceil(Double(trueEnvelopeLen) / Double(bufSize)))
        var result = SampleArray(repeating: 0, count: len)
        var p = 0

        func addRampOn() {
            for i in 0..<rampOn.count { result[p + i] = rampOn[i] }
            p += rampOn.count
        }
        func addRampOff() {
            for i in 0..<rampOff.count { result[p + i] = rampOff[i] }
            p += rampOff.count
        }
        func addOn(_ dur: Int) {
            for i in 0..<(dur * samplesInUnit - rampLen) { result[p + i] = 1 }
            p += dur * samplesInUnit - rampLen
        }
        // Dur units of silence; ARampLen compensates for a preceding RampOff
        func addOff(_ dur: Int, _ aRampLen: Int) {
            p += dur * samplesInUnit - aRampLen
        }

        for ch in morseMsg {
            switch ch {
            case ".": addRampOn(); addOn(1); addRampOff(); addOff(1, rampLen)
            case "-": addRampOn(); addOn(3); addRampOff(); addOff(1, rampLen)
            case " ": addOff(2, 0)
            case "~": addOff(3, 0)
            default: break
            }
        }
        assert(p == trueEnvelopeLen)
        return result
    }
}

/// Farnsworth keyer (port of `TFarnsKeyer`).
final class FarnsKeyer: Keyer {
    /// 3U inter-char, 5U inter-word, 4U inter-message spacing
    private let interCharSpacing = 3
    private let interWordSpacing = 5
    private let interMsgSpacing = 4

    override init(rate: Int = AudioConstants.defaultRate, bufSize: Int = AudioConstants.defaultBufSize) {
        super.init(rate: rate, bufSize: bufSize)
        loadMorseTable()
    }

    /// Load MorseTable with '^' intra-character markers so inter-char and
    /// inter-word spacing can be timed separately.
    override func loadMorseTable() {
        for (ch, code) in MorseTable.entries {
            morse[ch] = code + "^"
        }
    }

    override func encode(_ txt: String) -> String {
        var result = ""
        for ch in txt {
            if ch == " " || ch == "_" {
                result += " "
            } else if let code = morse[ch] {
                result += code
            }
        }
        // '^ ' -> '_' (inter-word marker)
        result = result.replacingOccurrences(of: "^ ", with: "_")
        if result.hasSuffix("^") {
            result = String(result.dropLast()) + "~"
        }
        return result
    }

    override func getEnvelope() -> SampleArray {
        precondition(wpmS > 0, "must init using setWpm()")

        var unitCnt = 0      // units at character speed WpmC
        var adjustCnt = 0    // units at sending speed WpmS (Farnsworth spacing)

        // Farnsworth timing: WpmS <= WpmC. The delay per word is derived from
        // the PARIS word: 31 character units at WpmC, the remaining
        // (12 + interWordSpacing) spacing units at WpmS.
        let farnsworth = wpmS <= wpmC
        var delayPerWord: Float = 0
        var samplesInAdjustUnit = 0
        var wpmC = self.wpmC
        if farnsworth {
            delayPerWord = 60.0 / Float(wpmS) - 31.0 * 60.0 / Float(wpmC) / Float(43 + interWordSpacing)
            samplesInAdjustUnit = bankersRound(delayPerWord * Float(rate) / Float(12 + interWordSpacing))
        } else {
            wpmC = wpmS
        }

        func incAdjust(_ dur: Int, _ prior: Int) {
            assert(prior <= 0)
            if farnsworth {
                unitCnt += prior
                adjustCnt += dur
            } else {
                unitCnt += dur + prior
            }
        }

        // count units
        for ch in morseMsg {
            switch ch {
            case ".": unitCnt += 2
            case "-": unitCnt += 4
            case "^": incAdjust(interCharSpacing, -1)
            case " ": incAdjust(interWordSpacing, 0)
            case "_": incAdjust(interWordSpacing, -1)
            case "~": incAdjust(interMsgSpacing, -1)
            default: break
            }
        }

        // 43U + 5U inter-word = 48U per word at character speed
        let samplesInUnit = bankersRound(60.0 * Double(rate) / Double(wpmC) / Double(43 + interWordSpacing))
        trueEnvelopeLen = unitCnt * samplesInUnit + adjustCnt * samplesInAdjustUnit
        let len = bufSize * Int(ceil(Double(trueEnvelopeLen) / Double(bufSize)))
        var result = SampleArray(repeating: 0, count: len)
        var p = 0

        func addRampOn() {
            for i in 0..<rampOn.count { result[p + i] = rampOn[i] }
            p += rampOn.count
        }
        func addRampOff() {
            for i in 0..<rampOff.count { result[p + i] = rampOff[i] }
            p += rampOff.count
        }
        func addOn(_ dur: Int) {
            for i in 0..<(dur * samplesInUnit - rampLen) { result[p + i] = 1 }
            p += dur * samplesInUnit - rampLen
        }
        func addOff(_ dur: Int, _ aRampLen: Int = 0) {
            p += dur * samplesInUnit - aRampLen
        }
        // Widen the trailing intra-char space of the previous character to a
        // Farnsworth inter-char space.
        func adjustSpace(_ dur: Int) {
            p += (dur - 1) * samplesInUnit
            if farnsworth {
                p += dur * (samplesInAdjustUnit - samplesInUnit)
            }
        }
        // Plain spacing between words (no prior space to compensate).
        func addSpace(_ dur: Int) {
            if farnsworth {
                p += dur * samplesInAdjustUnit
            } else {
                p += dur * samplesInUnit
            }
        }

        for ch in morseMsg {
            switch ch {
            case ".": addRampOn(); addOn(1); addRampOff(); addOff(1, rampLen)
            case "-": addRampOn(); addOn(3); addRampOff(); addOff(1, rampLen)
            case "^": adjustSpace(interCharSpacing)
            case " ": addSpace(interWordSpacing)
            case "_": adjustSpace(interWordSpacing)
            case "~": adjustSpace(interMsgSpacing)
            default: break
            }
        }
        assert(p == trueEnvelopeLen)
        return result
    }
}
