// Port of Qsb.pas — Rayleigh fading (QSB) generator for DX stations.
//
// Two uniform noise streams through a 3-pass QuickAverage produce a
// Rayleigh-distributed complex signal; the gain is normalized to unity mean.
// Bandwidth sets the fade rate; Flutter uses a much wider bandwidth.

import Foundation

final class Qsb {
    private let filt = QuickAverage()
    private var gain: Float = 0
    private(set) var bandwidth: Float = 0.1

    /// Depth of the fading: 1 = full Rayleigh, <1 = partial.
    var qsbLevel: Float = 1

    init() {
        filt.passes = 3
        qsbLevel = 1
        bandwidth = 0.1
    }

    private func newGain() -> Float {
        let c = filt.filter(RndFunc.uniform(), RndFunc.uniform())
        let r = sqrt((c.re * c.re + c.im * c.im) * 3 * Float(filt.points))
        return r * qsbLevel + (1 - qsbLevel)
    }

    func setBandwidth(_ value: Float) {
        bandwidth = value
        filt.points = Int(ceil(0.37 * Float(AudioConstants.defaultRate) / (Float(Settings.bufSize / 4) * value)))
        // re-prime the gain with the new filter state
        for _ in 0..<(filt.points * 3) {
            gain = newGain()
        }
    }

    /// Apply fading to a block, interpolating the gain linearly every
    /// BufSize/4 samples.
    func applyTo(_ arr: inout SampleArray) {
        let quarter = Settings.bufSize / 4
        let blkCnt = arr.count / quarter
        for b in 0..<blkCnt {
            let dG = (newGain() - gain) / Float(quarter)
            for i in 0..<quarter {
                arr[b * quarter + i] *= gain
                gain += dG
            }
        }
    }
}
