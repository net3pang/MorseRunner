// Morse Runner — Terminal Edition
//
// A dependency-free, cross-platform front end for the MorseRunner engine
// (macOS / Linux / Windows). It uses the same SimController as the macOS
// app, with the silent audio backend: the simulation runs in real time and
// can optionally be recorded to a .wav file (--wav out.wav) for playback.
//
// Command reference:
//   <callsign>        enter a callsign (same as typing it + Return)
//   c <callsign>      same, explicit
//   e1 <text>         set exchange field 1 then Return
//   e2 <text>         set exchange field 2 then Return
//   r                 run (pile-up by default, or the selected mode)
//   s                 stop
//   m <mode>          select mode: pileup | single | wpx | hst
//   cq nr tu my his b4 qm nil   send a function-key message
//   .                 TU + save the QSO
//   ;                 send <his> <#>
//   esc               abort the current transmission
//   w <wpm>           CW speed
//   d <minutes>       run duration
//   a <n>             pile-up activity level
//   q                 quit

import Foundation
import MorseRunnerCore
import AppKit

class NoSelectTextField: NSTextField {
    // Prevent AppKit's default "select all" behavior and force the cursor to move to the end of the string.
    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        if let edit = currentEditor() {
            edit.selectedRange = NSRange(location: stringValue.count, length: 0)
        }
    }
}

// MARK: - terminal helpers

enum Terminal {
    static func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }

    static func clearScreen() {
        #if os(Windows)
        write("\n")
        #else
        write("\u{1B}[2J\u{1B}[H")
        #endif
    }

    static func hideCursor() {
        #if !os(Windows)
        write("\u{1B}[?25l")
        #endif
    }

    static func showCursor() {
        #if !os(Windows)
        write("\u{1B}[?25h")
        #endif
    }
}

// MARK: - CLI arguments

nonisolated(unsafe) var cliContest: SimContest?
nonisolated(unsafe) var cliCall = Settings.call
nonisolated(unsafe) var cliExch: String?
nonisolated(unsafe) var cliWpm: Int?
nonisolated(unsafe) var cliMode: RunMode?
nonisolated(unsafe) var cliDuration: Int?
nonisolated(unsafe) var wavURL: URL?
var helpRequested = false

let args = CommandLine.arguments
var i = 1
while i < args.count {
    let a = args[i]
    func nextValue(_ flag: String) -> String? {
        if i + 1 < args.count { i += 1; return args[i] }
        Terminal.write("\(flag) requires a value\n")
        return nil
    }
    switch a {
    case "--contest":
        if let v = nextValue(a), let n = Int(v), let c = SimContest(rawValue: n) { cliContest = c }
    case "--call":
        cliCall = nextValue(a) ?? cliCall
    case "--exch":
        cliExch = nextValue(a)
    case "--wpm":
        if let v = nextValue(a) { cliWpm = Int(v) }
    case "--mode":
        if let v = nextValue(a) {
            switch v.lowercased() {
            case "pileup", "1": cliMode = .pileup
            case "single", "2": cliMode = .single
            case "wpx", "competition", "3": cliMode = .wpx
            case "hst", "4": cliMode = .hst
            default: break
            }
        }
    case "--duration":
        if let v = nextValue(a) { cliDuration = Int(v) }
    case "--wav":
        if let v = nextValue(a) { wavURL = URL(fileURLWithPath: v) }
    case "--help", "-h":
        helpRequested = true
    default:
        break
    }
    i += 1
}

if helpRequested {
    Terminal.write("""
    Morse Runner — Terminal Edition
    Usage: MorseRunnerTUI [--contest N] [--call CALL] [--exch "3A OR"] \\
                          [--wpm 25] [--mode pileup|single|wpx|hst] \\
                          [--duration MIN] [--wav out.wav] [--help]
    """)
    exit(0)
}

// MARK: - engine wiring

nonisolated(unsafe) let sim = SimController.shared

// UI state captured for rendering (all main-thread confined).
final class TUState {
    var clock = "00:00:00"
    var rate = 0
    var pileup = 0
    var status = ""
    var statusIsError = false
    var scoreText = ""
    var running = false
    var modeName = ""
}
nonisolated(unsafe) let ui = TUState()

// WAV recording (optional)
nonisolated(unsafe) var recorder: WavRecorder?
if let wavURL {
    if let r = WavRecorder(url: wavURL) {
        recorder = r
        SimEngine.shared.uiHooks.onOutputBlock = { samples in
            recorder?.append(samples)
        }
    } else {
        Terminal.write("warning: cannot open WAV file \(wavURL.path), continuing without recording\n")
    }
}

// Install the engine -> UI hooks.
SimEngine.shared.uiHooks.onClockUpdate = { ui.clock = $0 }
SimEngine.shared.uiHooks.onRateUpdate = { ui.rate = $0 }
SimEngine.shared.uiHooks.onPileupCount = { ui.pileup = $0 }
SimEngine.shared.uiHooks.onStatusBar = { text, isError in
    ui.status = text
    ui.statusIsError = isError
}
SimEngine.shared.uiHooks.onStatsUpdate = { s in
    ui.scoreText = "Raw \(s.points) pts × \(s.mults) mults  Verified \(s.verifiedPoints) pts × \(s.verifiedMults) mults"
}
SimEngine.shared.uiHooks.onRunState = { mode in
    ui.running = mode != .stop
    ui.modeName = mode == .stop ? "" : ["", "Pile-Up", "Single Calls", "COMPETITION", "H S T"][mode.rawValue]
}

// Initial configuration.
if let cliContest { sim.setContest(cliContest) } else { sim.setContest(Settings.simContest) }
_ = sim.setMyCall(cliCall.uppercased())
if let exch = cliExch {
    _ = sim.setMyExchange(exch.uppercased())
}
if let wpm = cliWpm { sim.setWpm(wpm) }
if let d = cliDuration { Settings.duration = d }
let defaultMode = cliMode ?? Settings.defaultRunMode
sim.masterVolume = 0.35
// self-monitor level, same default as the macOS GUI (-15 dB)
SimEngine.shared.uiHooks.volume = 0.75

// MARK: - command handling

func send(_ msg: StationMessage) {
    sim.sendMsg(msg)
}

@MainActor func handleCommand(_ rawLine: String) -> Bool {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return true }
    let lower = line.lowercased()
    let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
    let cmd = parts[0].lowercased()
    let arg = parts.count > 1 ? parts[1] : ""

    switch cmd {
    case "q", "quit", "exit":
        sim.stop()
        recorder?.close()
        Terminal.showCursor()
        return false
    case "r", "run":
        let mode = cliMode ?? (Settings.runMode == .stop ? Settings.defaultRunMode : Settings.runMode)
        sim.run(mode)
    case "s", "stop":
        sim.stop()
    case "m", "mode":
        let m: RunMode
        switch arg.lowercased() {
        case "pileup", "1": m = .pileup
        case "single", "2": m = .single
        case "wpx", "competition", "3": m = .wpx
        case "hst", "4": m = .hst
        default:
            Terminal.write("unknown mode '\(arg)'; use pileup|single|wpx|hst\n")
            return true
        }
        cliMode = m
        if !ui.running { sim.run(m) } else { Terminal.write("stop the run first\n") }
    case "cq": send(.cq)
    case "nr": send(.nr)
    case "tu": send(.tu)
    case "my", "mycall": send(.myCall)
    case "his", "hiscall": send(.hisCall)
    case "b4": send(.b4)
    case "qm", "?": send(.qm)
    case "nil": send(.nil_)
    case ".": sim.tuAndSave()
    case ";": sim.hisAndNR()
    case "esc", "abort": sim.abortSend()
    case "w", "wpm":
        if let v = Int(arg) { sim.setWpm(v) }
    case "d", "duration":
        if let v = Int(arg) { Settings.duration = v }
    case "a", "activity":
        if let v = Int(arg) { Settings.activity = v }
    case "e1":
        sim.enteredExch1 = arg.uppercased()
        sim.enterKeyPressed()
    case "e2":
        sim.enteredExch2 = arg.uppercased()
        sim.enterKeyPressed()
    case "c":
        sim.enteredCall = arg.uppercased()
        sim.enterKeyPressed()
    case "help", "h":
        Terminal.write("""
        Commands: <callsign> | c <call> | e1/e2 <text> | r | s | m <mode> |
                  cq nr tu my his b4 qm nil | . | ; | esc | w <wpm> |
                  d <min> | a <n> | q
        """)
        Terminal.write("\n")
    default:
        // Anything else is treated as a callsign entry.
        sim.enteredCall = line.uppercased()
        sim.enterKeyPressed()
    }
    return true
}

// MARK: - rendering

@MainActor func render() {
    Terminal.clearScreen()
    let contest = Settings.activeContest.name
    let running = ui.running ? "RUNNING (\(ui.modeName))" : "stopped"
    Terminal.write("Morse Runner — Terminal Edition\n")
    Terminal.write("Contest: \(contest)   Call: \(Settings.call)   Exch: \(sim.exchangeEdit)   [\(running)]\n")
    Terminal.write("Clock: \(ui.clock)   Speed: \(Settings.wpm) wpm   Activity: \(Settings.activity)   Duration: \(Settings.duration) min\n")
    Terminal.write("Pile-up: \(ui.pileup)   Rate: \(ui.rate) qso/hr   \(ui.scoreText)\n")
    Terminal.write("Entered: \(sim.enteredCall) | \(sim.enteredExch1) | \(sim.enteredExch2)\n")

    // status line
    let statusColor = ui.statusIsError ? "" : ""
    Terminal.write("Status: \(ui.status)\n")

    // score table tail
    let qsos = Log.shared.qsoList
    Terminal.write("--- Log (\(qsos.count) QSOs, last 6) ---\n")
    if qsos.isEmpty {
        Terminal.write("(none)\n")
    } else {
        for q in qsos.suffix(6) {
            let corr = q.err.isEmpty ? "" : " !\(q.err)"
            let hh = Int(q.t * 24)
            let mm = Int((q.t * 24 - Double(hh)) * 60)
            let utc = String(format: "%02d:%02d", hh, mm)
            let call = q.call.padding(toLength: 10, withPad: " ", startingAt: 0)
            let e1 = q.exch1.padding(toLength: 8, withPad: " ", startingAt: 0)
            let e2 = q.exch2.padding(toLength: 8, withPad: " ", startingAt: 0)
            Terminal.write("\(utc)  \(call) \(e1) \(e2)\(corr)\n")
        }
    }

    Terminal.write("--- Commands ---\n")
    Terminal.write("<call> Enter | c <call> | e1/e2 <text> | r/s | m <mode> | cq nr tu my his b4 qm nil | . ; esc | w <wpm> | q\n")
    Terminal.write("> ")
}

let renderTimer = Timer(timeInterval: 0.5, repeats: true) { _ in
    // the timer fires on RunLoop.main, so this is the main actor
    MainActor.assumeIsolated {
        render()
    }
}
RunLoop.main.add(renderTimer, forMode: .common)

// MARK: - input thread

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine(strippingNewline: true) {
        DispatchQueue.main.async {
            let keepGoing = handleCommand(line)
            if !keepGoing {
                exit(0)
            }
        }
    }
    // EOF (Ctrl-D)
    DispatchQueue.main.async {
        Terminal.write("\nEOF — quitting\n")
        recorder?.close()
        exit(0)
    }
}

Terminal.hideCursor()
Terminal.write("Morse Runner — Terminal Edition\n")
Terminal.write("Type 'help' for commands.\n")
render()
RunLoop.main.run()
