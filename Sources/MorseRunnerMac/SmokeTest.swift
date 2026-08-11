// Self-test driver for the app wiring (--smoke mode).
//
// Drives the REAL UI-facing pipeline (SimController + AudioOutput + the
// contest engine) through the complete user journey — Run, CQ, station
// spawn, a full QSO with the log, stop, restart — and logs the state of
// every stage so headless verification can see where a run breaks.
// Invoked by AppDelegate when the binary is launched with `--smoke`.

import Foundation
import MorseRunnerCore

public func runAppSmokeTest() {
    // t+1: start a run and call CQ (as the user pressing Run then F1)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        let sim = SimController.shared
        NSLog("SMOKE: contest=%@ call=%@ exch=%@",
              Settings.activeContest.name, Settings.call, sim.exchangeEdit)
        // --mode pileup|single|wpx|hst lets the smoke driver exercise a chosen
        // run mode (the GUI's mode combo / Run button path).
        let mode: RunMode
        if let idx = CommandLine.arguments.firstIndex(of: "--mode"),
           idx + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[idx + 1].lowercased() {
            case "single": mode = .single
            case "wpx": mode = .wpx
            case "hst": mode = .hst
            default: mode = .pileup
            }
        } else {
            mode = .pileup
        }
        sim.run(mode)
        if mode != .single {
            sim.sendMsg(.cq)
        }
        NSLog("SMOKE: run started, runMode=%d", Settings.runMode.rawValue)
    }

    // every second: keep calling CQ until stations spawn, then work a QSO
    var qsoStarted = false
    var cqCount = 0
    let driver = DispatchSource.makeTimerSource(queue: .main)
    driver.schedule(deadline: .now() + 2.0, repeating: 1.0)
    driver.setEventHandler(handler: {
        guard let contest = Contest.shared else { return }
        let sim = SimController.shared

        // keep calling CQ while idle until a caller shows up (pile-up only;
        // single mode spawns callers automatically)
        if !qsoStarted {
            NSLog("SMOKE: probe me.state=%d sendPos=%d envBytes=%d stations=%d block=%d",
                  contest.me.state.rawValue, contest.me.sendPos,
                  contest.me.envelope?.count ?? -1,
                  contest.stations.count, contest.blockNumber)
            if contest.me.state == .listening && contest.me.envelope == nil
                && Settings.runMode != .single {
                cqCount += 1
                NSLog("SMOKE: CQ#%d at blockNumber=%d (no callers yet)", cqCount, contest.blockNumber)
                sim.sendMsg(.cq)
            }
            if contest.stations.count > 0 {
                qsoStarted = true
                NSLog("SMOKE: stations spawned: %d, blockNumber=%d",
                      contest.stations.count, contest.blockNumber)
                // complete a QSO through the real entry path
                guard let dx = contest.stations.items.first as? DxStation else { return }
                sim.enteredCall = dx.myCall
                sim.sendMsg(.hisCall)
                sim.sendMsg(.nr)
                sim.enteredExch1 = dx.exch1
                sim.enteredExch2 = dx.exch2
                sim.tuAndSave()
                NSLog("SMOKE: QSO sent: %@ %@ %@, qsoList=%d, callSent=%d",
                      dx.myCall, dx.exch1, dx.exch2,
                      Log.shared.qsoList.count,
                      Log.shared.callSent ? 1 : 0)
            }
        }
    })
    driver.resume()

    // t+30: report final state, stop, restart, then exit
    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
        driver.cancel()
        let sim = SimController.shared
        let a = sim.audioDiagnostics
        let contest = Contest.shared
        NSLog("SMOKE: audio engineRunning=%d playerPlaying=%d pendingBlocks=%d",
              a.engineRunning ? 1 : 0, a.playerPlaying ? 1 : 0, a.pending)
        NSLog("SMOKE: sim blockNumber=%d stations=%d qsoList=%d meState=%d",
              contest?.blockNumber ?? -1, contest?.stations.count ?? -1,
              Log.shared.qsoList.count, contest?.me.state.rawValue ?? -1)
        sim.stop()
        NSLog("SMOKE: stopped, runMode=%d", Settings.runMode.rawValue)
        sim.run(.pileup)
        NSLog("SMOKE: restarted, runMode=%d, audioEngine=%d",
              Settings.runMode.rawValue, sim.audioDiagnostics.engineRunning ? 1 : 0)
        sim.stop()
        NSLog("SMOKE: final stop, runMode=%d", Settings.runMode.rawValue)
        exit(0)
    }
}
