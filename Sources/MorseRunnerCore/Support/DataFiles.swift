// Runtime data-file resolution (DXCC.LIST, Master.dta, contest history files).
//
// The Windows original reads these from the executable's directory. On macOS
// the files ship inside the app bundle's Resources; when running from the
// SwiftPM build (swift run) they are found via Bundle.module. The current
// working directory is a fallback for development.

import Foundation

enum DataFiles {
    /// Absolute URL for a data file, or nil if not found anywhere.
    static func resourceURL(_ name: String) -> URL? {
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bases: [URL] = [Bundle.main.bundleURL, exeDir, cwd]
        var candidates: [URL?] = []
        for base in bases {
            candidates.append(base.appendingPathComponent(name))
            candidates.append(base.appendingPathComponent("Resources").appendingPathComponent(name))
            candidates.append(base.appendingPathComponent("Contents/Resources").appendingPathComponent(name))
        }
        for candidate in candidates {
            if let url = candidate, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Load a data file as a string, or nil if unavailable. Tries UTF-8
    /// then ASCII; both are strict, so the first that decodes wins.
    static func loadString(_ name: String) -> String? {
        guard let url = resourceURL(name) else { return nil }
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .ascii) { return s }
        // last resort: replace undecodable bytes
        if let data = try? Data(contentsOf: url) {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }
}
