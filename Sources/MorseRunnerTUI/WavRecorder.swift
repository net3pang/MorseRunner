// Minimal RIFF/WAVE writer (pure Foundation) for the terminal edition.
// The simulation produces 16-bit-scale Float samples; they are converted to
// little-endian Int16 PCM like the original's waveOut path.

import Foundation
import MorseRunnerCore

/// Records the audio output to a .wav file (44.1k? no — the simulation's
/// native 11025 Hz mono 16-bit PCM).
final class WavRecorder {
    private let handle: FileHandle
    private var dataBytes = 0
    private let sampleRate: Int

    init?(url: URL, sampleRate: Int = AudioConstants.defaultRate) {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return nil }
        guard let h = FileHandle(forWritingAtPath: url.path) else { return nil }
        self.handle = h
        self.sampleRate = sampleRate
        // Placeholder 44-byte header; data size fields are patched on close.
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: [UInt8](repeating: 0, count: 4))  // riff size
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: [16, 0, 0, 0])                    // fmt chunk size
        header.append(contentsOf: [1, 0])                           // PCM
        header.append(contentsOf: [1, 0])                           // mono
        var rate = UInt32(sampleRate)
        withUnsafeBytes(of: &rate) { header.append(contentsOf: $0) }
        let byteRate = UInt32(sampleRate * 2)
        var br = byteRate
        withUnsafeBytes(of: &br) { header.append(contentsOf: $0) }
        header.append(contentsOf: [2, 0])                           // block align
        header.append(contentsOf: [16, 0])                          // bits per sample
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: [UInt8](repeating: 0, count: 4))  // data size
        handle.write(header)
    }

    /// Append one audio block (float samples in 16-bit scale ±32767).
    func append(_ samples: SampleArray) {
        var data = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-32767, min(32767, Int(s.rounded()))))
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        handle.write(data)
        dataBytes += data.count
    }

    /// Patch the header sizes and close.
    func close() {
        do {
            try handle.seek(toOffset: 4)
            var riffSize = UInt32(36 + dataBytes)
            withUnsafeBytes(of: &riffSize) { handle.write(Data($0)) }
            try handle.seek(toOffset: 40)
            var dataSize = UInt32(dataBytes)
            withUnsafeBytes(of: &dataSize) { handle.write(Data($0)) }
            try handle.close()
        } catch {
            NSLog("WavRecorder: close failed: \(error)")
        }
    }
}
