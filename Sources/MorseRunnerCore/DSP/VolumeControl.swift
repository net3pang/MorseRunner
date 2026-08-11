// Port of VolumCtl.pas — TVolumeControl: default gain and AGC.
//
// AGC: per-sample envelope detection with a lookahead window shaped by an
// attack function; gain = FMaxOut * (1 - exp(-env/FBeta)) / env (the classic
// log-domain compressor with soft-knee characteristic).

import Foundation

/// Volume control / AGC (port of `TVolumeControl`).
final class VolumeControl {
    private var noiseIn: Float = 1
    private var noiseOut: Float = 2000
    private var beta: Float = 0
    private var envelope: Float = 0
    private var defaultGain: Float = 0

    private var complexBuf = ReImArrays()
    private var realBuf: SampleArray = []
    private var magBuf: SampleArray = []
    private var len = 0
    private var bufIdx = 0

    private(set) var agcEnabled = false
    private var attackShape: SampleArray = []
    private(set) var isOverload = false

    /// Debug: current compressor knee (beta) for DSP diagnostics.
    var debugBeta: Float { beta }

    private var attackSamples = 28 {
        didSet { attackSamples = max(1, attackSamples); makeAttackShape() }
    }
    private var holdSamples = 28 {
        didSet { holdSamples = max(1, holdSamples); makeAttackShape() }
    }
    private var maxOut: Float = 20000 {
        didSet { calcBeta() }
    }

    init() {
        maxOut = 20000
        noiseIn = 1
        noiseOut = 2000
        calcBeta()
        attackSamples = 28 // 5 ms if SampleRate=5512
        holdSamples = 28
        makeAttackShape()
    }

    // MARK: - settings

    var noiseInDb: Float {
        get { 20 * log10(noiseIn) }
        set { noiseIn = pow(10, 0.05 * newValue); calcBeta() }
    }

    var noiseOutDb: Float {
        get { 20 * log10(noiseOut) }
        set { noiseOut = min(0.25 * maxOut, pow(10, 0.05 * newValue)); calcBeta() }
    }

    func setMaxOut(_ v: Float) {
        maxOut = v
    }

    func setAttackSamples(_ v: Int) {
        attackSamples = v
    }

    func setHoldSamples(_ v: Int) {
        holdSamples = v
    }

    func setAgcEnabled(_ v: Bool) {
        if v && !agcEnabled { reset() }
        agcEnabled = v
    }

    func reset() {
        realBuf = SampleArray(repeating: 0, count: len)
        complexBuf.setLength(len)
        magBuf = SampleArray(repeating: 0, count: len)
        bufIdx = 0
    }

    // MARK: - internals

    private func makeAttackShape() {
        len = 2 * (attackSamples + holdSamples) + 1
        attackShape = SampleArray(repeating: 0, count: len)
        for i in 0..<attackSamples {
            let v = log(0.5 - 0.5 * cos(Double(i + 1) * Double.pi / Double(attackSamples + 1)))
            attackShape[i] = Float(v)
            attackShape[len - 1 - i] = Float(v)
        }
        reset()
    }

    /// Find FBeta that maps FNoiseIn to FNoiseOut for the AGC characteristic
    /// Out = FMaxOut * (1 - exp(-In / FBeta)).
    private func calcBeta() {
        beta = noiseIn / log(maxOut / (maxOut - noiseOut))
        defaultGain = noiseOut / noiseIn
    }

    /// Look both sides of the current sample and take the max magnitude,
    /// weighted by the attack shape (log-domain).
    private func calcAgcGain() -> Float {
        var envel: Float = 1e-10
        var wi = 0
        var d = bufIdx
        while wi < len {
            let sample = magBuf[d] + attackShape[wi]
            if sample > envel { envel = sample }
            d += 1
            if d == len { d = 0 }
            wi += 1
        }
        envelope = envel
        let env = exp(envel)
        return maxOut * (1 - exp(-env / beta)) / env
    }

    private func applyAgc(_ v: Float) -> Float {
        realBuf[bufIdx] = v
        magBuf[bufIdx] = log(abs(v) + 1e-10)
        bufIdx = (bufIdx + 1) % len
        return realBuf[(bufIdx + (len / 2)) % len] * calcAgcGain()
    }

    private func applyAgc(_ re: Float, _ im: Float) -> Complex {
        complexBuf.re[bufIdx] = re
        complexBuf.im[bufIdx] = im
        magBuf[bufIdx] = 0.5 * log(re * re + im * im)
        bufIdx = (bufIdx + 1) % len
        let mid = (bufIdx + (len / 2)) % len
        let gain = calcAgcGain()
        return Complex(complexBuf.re[mid] * gain, complexBuf.im[mid] * gain)
    }

    private func applyDefaultGain(_ v: Float) -> Float {
        let r = min(maxOut, max(-maxOut, v * defaultGain))
        isOverload = isOverload || (abs(r) == maxOut)
        return r
    }

    private func applyDefaultGain(_ re: Float, _ im: Float) -> Complex {
        let r = min(maxOut, max(-maxOut, re * defaultGain))
        let i = min(maxOut, max(-maxOut, im * defaultGain))
        isOverload = isOverload || (abs(r) == maxOut) || (abs(i) == maxOut)
        return Complex(r, i)
    }

    // MARK: - processing

    func process(_ data: SampleArray) -> SampleArray {
        isOverload = false
        var result = SampleArray(repeating: 0, count: data.count)
        if agcEnabled {
            for i in 0..<result.count {
                result[i] = applyAgc(data[i])
            }
        } else {
            for i in 0..<result.count {
                result[i] = applyDefaultGain(data[i])
            }
        }
        return result
    }

    func process(_ data: ReImArrays) -> ReImArrays {
        isOverload = false
        var result = ReImArrays()
        result.setLength(data.re.count)
        if agcEnabled {
            for i in 0..<result.re.count {
                let c = applyAgc(data.re[i], data.im[i])
                result.re[i] = c.re
                result.im[i] = c.im
            }
        } else {
            for i in 0..<result.re.count {
                let c = applyDefaultGain(data.re[i], data.im[i])
                result.re[i] = c.re
                result.im[i] = c.im
            }
        }
        return result
    }
}
