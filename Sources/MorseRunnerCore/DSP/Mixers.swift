// Port of Mixers.pas (TModulator only) — up-conversion of baseband I/Q to
// the audio carrier. TDownMixer/TFastDownMixer are not used by the current
// code base and are omitted.

import Foundation

/// Up-mixer with a precomputed sin/cos carrier table (port of `TModulator`).
final class Modulator {
    // Backing storage: calcSinCos() quantizes the carrier frequency and must
    // not re-trigger the observers (the Delphi original has explicit setters).
    private var _samplesPerSec = 5512
    private var _carrierFreq: Float = 600
    private var _gain: Float = 1

    var samplesPerSec: Int {
        get { _samplesPerSec }
        set { _samplesPerSec = newValue; calcSinCos() }
    }
    var carrierFreq: Float {
        get { _carrierFreq }
        set { _carrierFreq = newValue; calcSinCos() }
    }
    var gain: Float {
        get { _gain }
        set { _gain = newValue; calcSinCos() }
    }

    private var sn: SampleArray = []
    private var cs: SampleArray = []
    private var sampleNo = 0

    init() {
        // mirror the Delphi constructor defaults
        carrierFreq = 600
        samplesPerSec = 5512
        gain = 1
        sampleNo = 0
    }

    /// Rebuild the carrier table. The carrier frequency is quantized to an
    /// exact integer number of samples per cycle.
    private func calcSinCos() {
        let cnt = bankersRound(Float(_samplesPerSec) / _carrierFreq)
        _carrierFreq = Float(_samplesPerSec) / Float(cnt)
        let dFi = Float(AudioConstants.twoPi) / Float(cnt)

        sn = SampleArray(repeating: 0, count: cnt)
        cs = SampleArray(repeating: 0, count: cnt)
        if cnt > 1 {
            sn[0] = 0; sn[1] = sin(dFi)
            cs[0] = 1; cs[1] = cos(dFi)
            for i in 2..<cnt {
                cs[i] = cs[1] * cs[i - 1] - sn[1] * sn[i - 1]
                sn[i] = cs[1] * sn[i - 1] + sn[1] * cs[i - 1]
            }
        } else {
            sn[0] = 0; cs[0] = 1
        }
        // apply gain
        for i in 0..<cnt {
            cs[i] *= _gain
            sn[i] *= _gain
        }
        sampleNo = 0
    }

    func modulate(_ data: ReImArrays) -> SampleArray {
        var result = SampleArray(repeating: 0, count: data.re.count)
        for i in 0..<result.count {
            result[i] = data.re[i] * sn[sampleNo] - data.im[i] * cs[sampleNo]
            sampleNo = (sampleNo + 1) % cs.count
        }
        return result
    }

    func modulate(_ data: SampleArray) -> SampleArray {
        var result = SampleArray(repeating: 0, count: data.count)
        for i in 0..<result.count {
            result[i] = data[i] * cs[sampleNo]
            sampleNo = (sampleNo + 1) % cs.count
        }
        return result
    }
}
