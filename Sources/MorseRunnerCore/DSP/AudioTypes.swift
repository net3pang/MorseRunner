// Port of SndTypes.pas — core audio data types and constants.
// The original is a Windows/Delphi unit; this is the macOS/Swift equivalent.

import Foundation

public enum AudioConstants {
    public static let fourPi = 4.0 * Double.pi
    public static let twoPi = 2.0 * Double.pi
    public static let halfPi = 0.5 * Double.pi
    public static let radiansInDegree = Double.pi / 180.0
    public static let smallFloat: Float = 1e-12

    /// Default sample rate used by the whole simulation (Hz), from Ini.pas.
    public static let defaultRate = 11025
    /// Default audio block size in samples, from Ini.pas.
    public static let defaultBufSize = 512
}

/// Single-precision sample array (Delphi `TSingleArray`).
public typealias SampleArray = [Float]

/// Double-precision array (Delphi `TDoubleArray`).
typealias DoubleArray = [Double]

/// Array of bytes (Delphi `TByteArray`).
typealias ByteArray = [UInt8]

/// 16-bit signed sample array (Delphi `TSmallIntArray`).
typealias SmallIntArray = [Int16]

/// Integer array (Delphi `TIntegerArray`).
typealias IntArray = [Int]

/// Delphi `Round()` — banker's rounding (half to even). Swift's default
/// `rounded()` rounds half away from zero, so the explicit rule is required
/// for exact fidelity of all time/sample conversions.
func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}

func bankersRound(_ value: Float) -> Int {
    Int(value.rounded(.toNearestOrEven))
}

/// Complex number with single-precision parts (Delphi `TComplex`).
struct Complex {
    var re: Float
    var im: Float

    init(_ re: Float = 0, _ im: Float = 0) {
        self.re = re
        self.im = im
    }
}

/// Array of complex numbers (Delphi `TComplexArray`).
typealias ComplexArray = [Complex]

/// Pair of real/imaginary single arrays (Delphi `TReImArrays`).
struct ReImArrays {
    var re = SampleArray()
    var im = SampleArray()

    init(re: SampleArray = [], im: SampleArray = []) {
        self.re = re
        self.im = im
    }

    mutating func setLength(_ len: Int) {
        re = SampleArray(repeating: 0, count: len)
        im = SampleArray(repeating: 0, count: len)
    }

    mutating func clear() {
        re = []
        im = []
    }
}
