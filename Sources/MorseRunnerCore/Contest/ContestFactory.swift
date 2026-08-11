// Port of the TMainForm.CreateContest factory (Main.pas).

import Foundation

enum ContestFactory {
    /// Create the contest instance for the given contest id
    /// (Delphi `TMainForm.CreateContest` case statement).
    static func create(_ id: SimContest) -> Contest {
        switch id {
        case .wpx, .hst:
            return CqWpx()
        case .cwt:
            return CWOPS()
        case .fieldDay:
            return ArrlFieldDay()
        case .naQp:
            return NcjNaQp()
        case .cqww:
            return CqWW()
        case .arrlDx:
            return ArrlDx()
        case .sst:
            return CWSST()
        case .allJa:
            return ALLJA()
        case .acag:
            return ACAG()
        case .iaruHf:
            return IaruHf()
        case .arrlSS:
            return Sweepstakes()
        }
    }
}
