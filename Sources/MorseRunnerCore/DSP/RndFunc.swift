// Port of RndFunc.pas — random distributions used by the simulation.
//
// The Delphi original draws from the global `Random` (Mersenne Twister).
// Swift's SystemRandomNumberGenerator is used instead; the simulation does
// not depend on a reproducible sequence, only on the distributions.

import Foundation

enum RndFunc {
    /// Standard normal via Box-Muller. Delphi wraps in try/except because
    /// `Random` can return 0 (log(0) = -inf); Swift never returns exactly 0
    /// from `Double.random(in: 0..<1)` but we guard anyway to stay total.
    static func normal() -> Float {
        while true {
            let u1 = Double.random(in: 0..<1)
            let u2 = Double.random(in: 0..<1)
            guard u1 > 0 else { continue }
            return Float(sqrt(-2.0 * log(u1)) * cos(AudioConstants.twoPi * u2))
        }
    }

    /// Gaussian distribution truncated to ±limit around mean, by rejection
    /// sampling (the comment in the original explains why clipping was wrong).
    static func gaussLim(mean: Float, limit: Float) -> Float {
        while true {
            let r = normal() * 0.5 * limit
            if abs(r) <= limit {
                return mean + r
            }
        }
    }

    /// Rayleigh distribution with the given mean.
    static func rayleigh(mean: Float) -> Float {
        let u1 = Double.random(in: 0..<1)
        let u2 = Double.random(in: 0..<1)
        guard u1 > 0, u2 > 0 else { return rayleigh(mean: mean) }
        return mean * Float(sqrt(-log(u1) - log(u2)))
    }

    /// Uniform in [-1, 1).
    static func uniform() -> Float {
        Float(Double.random(in: -1..<1))
    }

    /// U-shaped distribution on [-1, 1] (sin(pi * (u - 0.5))).
    static func uShaped() -> Float {
        Float(sin(Double.pi * (Double.random(in: 0..<1) - 0.5)))
    }

    /// Poisson with the given mean, via the simple product method
    /// (Numerical Recipes c7-3). Loop bound 30 mirrors the original.
    static func poisson(mean: Float) -> Int {
        let g = exp(-mean)
        var t: Float = 1
        for result in 0...30 {
            t *= Float(Double.random(in: 0..<1))
            if t <= g {
                return result
            }
        }
        return 30
    }

    /// Audio-block count for a duration in seconds, at the current buffer
    /// size (Delphi: `Round(DEFAULTRATE / Ini.BufSize * Sec)`).
    static func secondsToBlocks(_ sec: Float) -> Int {
        bankersRound(Float(AudioConstants.defaultRate) / Float(Settings.bufSize) * sec)
    }

    /// Seconds for an audio-block count (Delphi: `Blocks * Ini.BufSize / DEFAULTRATE`).
    static func blocksToSeconds(_ blocks: Float) -> Float {
        blocks * Float(Settings.bufSize) / Float(AudioConstants.defaultRate)
    }
}
