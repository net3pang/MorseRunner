// Port of MovAvg.pas / QuickAvg.pas — moving-average filters used in the
// receive DSP chain and the QSB fading generator.

import Foundation

/// Multi-pass moving-average filter (port of `TMovingAverage`).
/// Cascaded boxcar averages with a shared sliding-sum state per pass,
/// acting on blocks of `SamplesInInput` samples.
final class MovingAverage {
    var points = 129
    var passes = 3
    var samplesInInput = 512
    var decimateFactor = 1
    var gainDb: Float = 0 {
        didSet { calcScale() }
    }

    private var bufRe: [[Float]] = []
    private var bufIm: [[Float]] = []
    private var norm: Float = 0

    /// Debug: current normalization factor for DSP diagnostics.
    var debugNorm: Float { norm }

    init() {
        reset()
    }

    private func calcScale() {
        // (gain db -> linear) * (averaging factor)
        norm = pow(10, 0.05 * gainDb) * pow(Float(points), Float(-passes))
    }

    func reset() {
        bufRe = [[Float]](repeating: [Float](repeating: 0, count: samplesInInput + points), count: passes + 1)
        bufIm = [[Float]](repeating: [Float](repeating: 0, count: samplesInInput + points), count: passes + 1)
        calcScale()
    }

    func filter(_ data: SampleArray) -> SampleArray {
        doFilter(data, &bufRe)
    }

    func filter(_ data: ReImArrays) -> ReImArrays {
        var result = ReImArrays()
        result.re = doFilter(data.re, &bufRe)
        result.im = doFilter(data.im, &bufIm)
        return result
    }

    /// Shift existing data left and append new data at the end of the buffer.
    private func pushArray(_ src: SampleArray, _ dst: inout SampleArray) {
        let len = dst.count - src.count
        for i in 0..<len { dst[i] = dst[i + src.count] }
        for i in 0..<src.count { dst[len + i] = src[i] }
    }

    private func shiftArray(_ dst: inout SampleArray, count: Int) {
        for i in 0..<(dst.count - count) { dst[i] = dst[i + count] }
    }

    /// One averaging pass: recursive running sum over `points` taps.
    private func pass(_ src: SampleArray, _ dst: inout SampleArray) {
        shiftArray(&dst, count: samplesInInput)
        for i in points..<src.count {
            dst[i] = dst[i - 1] - src[i - points] + src[i]
        }
    }

    private func getResult(_ src: SampleArray) -> SampleArray {
        if decimateFactor == 1 {
            var result = SampleArray(repeating: 0, count: samplesInInput)
            for i in 0..<result.count {
                result[i] = src[points + i] * norm
            }
            return result
        } else {
            var result = SampleArray(repeating: 0, count: samplesInInput / decimateFactor)
            for i in 0..<result.count {
                result[i] = src[points + i * decimateFactor] * norm
            }
            return result
        }
    }

    private func doFilter(_ data: SampleArray, _ buf: inout [[Float]]) -> SampleArray {
        pushArray(data, &buf[0])
        for i in 1...passes {
            pass(buf[i - 1], &buf[i])
        }
        return getResult(buf[passes])
    }
}

/// Sample-by-sample cascaded moving average (port of `TQuickAverage`),
/// used by the QSB generator. Keeps complex state so Re/Im streams stay
/// phase-aligned.
final class QuickAverage {
    var points = 128 {
        didSet { points = max(1, points); reset() }
    }
    var passes = 4 {
        didSet { passes = max(1, min(8, passes)); reset() }
    }

    private var reBufs: [[Double]] = []
    private var imBufs: [[Double]] = []
    private var scale: Double = 0
    private var idx = 0
    private var prevIdx = 0

    init() {
        reset()
    }

    func reset() {
        reBufs = [[Double]](repeating: [Double](repeating: 0, count: points), count: passes + 1)
        imBufs = [[Double]](repeating: [Double](repeating: 0, count: points), count: passes + 1)
        scale = pow(Double(points), Double(-passes))
        idx = 0
        prevIdx = points - 1
    }

    func filter(_ v: Float) -> Float {
        let r = doFilter(Double(v), &reBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return Float(r)
    }

    func filter(_ re: Float, _ im: Float) -> Complex {
        let r = doFilter(Double(re), &reBufs)
        let i = doFilter(Double(im), &imBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return Complex(Float(r), Float(i))
    }

    func filteredModule(_ re: Float, _ im: Float) -> Float {
        let c = filter(re, im)
        return sqrt(c.re * c.re + c.im * c.im)
    }

    private func doFilter(_ v: Double, _ bufs: inout [[Double]]) -> Double {
        var result = v
        for p in 1...passes {
            let oldV = result
            result = bufs[p][prevIdx] - bufs[p - 1][idx] + oldV
            bufs[p - 1][idx] = oldV
        }
        bufs[passes][idx] = result
        return result * scale
    }
}
