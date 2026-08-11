// Audio output abstraction (port of VCL/SndOut.pas).
//
// The Windows original pushes 512-sample blocks to waveOut; its callback
// (OnBufAvailable) drives the simulation. This abstraction keeps that push
// model while letting each platform provide its own sink:
//
//   - macOS:   AVAudioBackend (AVAudioEngine/AVAudioPlayerNode)
//   - Linux:   PortAudio backend (planned) or the silent backend
//   - headless: SilentAudioBackend (tests, CI, TUI without a sound card)
//
// The engine in this package depends only on AudioBackend, so the whole
// simulation runs anywhere Swift runs — no platform frameworks needed.

import Foundation

/// A sink for the simulation's audio blocks. `start` begins the real-time
/// pump; the engine generates one block per call through `blockProvider`
/// (Tst.GetAudio in the original).
public protocol AudioBackend: AnyObject {
    /// Master output volume 0..1.
    var playerVolume: Float { get set }
    /// Diagnostics for self-tests (--smoke, engine tests).
    var diagnostics: (engineRunning: Bool, playerPlaying: Bool, pending: Int) { get }
    /// Start the pump; blockProvider is called on the main thread at the
    /// block rate (512 samples @ 11025 Hz ≈ 46.4 ms).
    func start(blockProvider: @escaping () -> SampleArray)
    /// Stop the pump.
    func stop()
}

/// Default backend with no audio device. The simulation still advances in
/// real time so headless runs, tests, and the terminal UI work everywhere.
/// One block = 512 samples at 11025 Hz ≈ 46.4 ms; with a 20 ms timer every
/// second tick is close enough to real time.
public final class SilentAudioBackend: AudioBackend {
    public init() {}

    private var timer: Timer?
    private var pendingBlocks = 0
    private var blockProvider: (() -> SampleArray)?

    public var playerVolume: Float = 1.0

    public var diagnostics: (engineRunning: Bool, playerPlaying: Bool, pending: Int) {
        (false, false, pendingBlocks)
    }

    public func start(blockProvider: @escaping () -> SampleArray) {
        self.blockProvider = blockProvider
        pendingBlocks = 0
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.fill()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        pendingBlocks = 0
    }

    private func fill() {
        guard let provider = blockProvider else { return }
        pendingBlocks += 1
        if pendingBlocks >= 2 {
            pendingBlocks = 0
            _ = provider()
        }
    }

    /// Synchronous pump for tests: delivers one block immediately.
    func advanceForTesting() {
        guard let provider = blockProvider else { return }
        pendingBlocks += 1
        if pendingBlocks >= 2 {
            pendingBlocks = 0
            _ = provider()
        }
    }
}
