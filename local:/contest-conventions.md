# MorseRunner → Swift 移植约定（Contest 模块）

## 目标
把 /tmp/MorseRunner-reference 下的 Delphi 比赛模块移植为 Swift，放入
/Users/klaus/Documents/code/MorseRunnerForMac/Sources/MorseRunner/Contest/。

## 已存在的 Swift 基础设施（同一 target，直接用）
- `Settings`（Support/Settings.swift）：`Settings.simContest`(SimContest枚举), `Settings.runMode`(RunMode), `Settings.call`, `Settings.activity`, `Settings.lids`, `Settings.qrn/qrm/qsb/flutter`, `Settings.serialNRSettings`(字典[SerialNRType: SerialNumberSettings]), `Settings.serialNR`, `Settings.wpm`, `Settings.minRxWpm/maxRxWpm`, `Settings.farnsworthCharRate`, `Settings.nilInstantRemove`, `Settings.duration`, `Settings.hamName`, `Settings.isNum(String)->Bool`
- `contestDefinitions`（[ContestDefinition]）：name/key/exchType1/exchType2/exchFieldEditable/exchDefault/msg
- `Settings.activeContest` → ContestDefinition
- `ExchTypes`（struct，字段 exch1: Exchange1Type, exch2: Exchange2Type）
- `Exchange1Type`/`Exchange2Type` 枚举（含 .undef = -1）
- `Contest`（Contest/Contest.swift）基类：
  - 抽象方法（子类必须 override）：`loadCallHistory(_ userCallsign: String) -> Bool`、`pickStation() -> Int`、`dropStation(_ id: Int)`、`getCall(_ id: Int) -> String`、`getExchange(_ id: Int, into station: DxStation)`
  - 可 override：`sendMsg(_ stn: Station, _ aMsg: StationMessage)`、`sendText(_ stn: Station, _ aMsg: String)`、`getStationInfo(_ callsign: String) -> String`、`getExchangeTypes(kind:requestedMsgType:stationCallsign:remoteCallsign:) -> ExchTypes`、`extractMultiplier(_ qso: Qso) -> String`、`onSetMyCall`、`serialNrModeChanged()`、`setFarnsworthEnabled(_ v: Bool)`
  - 实例成员：`me`(MyStation), `stations`(StationCollection), `blockNumber`
  - 基类 `init()` 已完成 DSP 设置；子类 override `init()` 时调 `super.init()`
- `DxStation`：字段 `opName`、`exch1`、`exch2`、`userText`、`nr`、`myCall`、`sentExchTypes`
- `Dxcc.shared.findRec(_ call: String) -> DxccRec?`（rec.entity/rec.continent），`Dxcc.shared.stationInfo(_ call: String) -> String`
- `DataFiles.loadString(_ name: String) -> String?`（读取资源文件，文件名大小写按 Delphi 原样：CQWWCW.txt、FDGOTA.TXT 等）
- `RndFunc`：`normal()`、`gaussLim(mean:limit:)`、`rayleigh(mean:)`、`uniform()`、`uShaped()`、`poisson(mean:)`、`secondsToBlocks(_:)`、`blocksToSeconds(_:)`
- `SerialNRGen`（Sim/SerialNRGen.swift）：`addRange(_ range: SerialNumberSettings)`、`addDistribution(_ range: SerialNumberSettings, sampleTbl: [SerNRSampleBin])`、`getNR() -> Int`
- `Qso`（Support/Log.swift）：字段 call/trueCall/exch1/exch2/nr/rst/pfx/multStr/points/dupe/err 等
- `CallList`（Sim/CallHistory.swift）：`loadCallList()`、`pickCall() -> String`、`isEmpty`
- `StationMessage` 枚举：.cq/.nr/.tu/.myCall/.hisCall/.b4/.qm/.nil_/.garbage/.rNR/.rNR2/.deMyCall1/.deMyCall2/.deMyCallNr1/.deMyCallNr2/.myCallNr1/.myCallNr2/.myCall2/.nrQm/.longCQ/.qrl/.qrl2/.qsy/.agn/.none

## 关键翻译模式
- Delphi `random(N)` → `Int.random(in: 0..<N)`；`Random` → `Float.random(in: 0..<1)`
- Delphi `Format('...%d...', [x])` → `String(format: "..%d..", x)`；`%s` 传 String 会崩溃！用 `\(x)` 插值
- CSV 解析：`line.components(separatedBy: ",")`
- 文件读取：`DataFiles.loadString("文件名")`，按行 `components(separatedBy: .newlines)`，跳过 `#` 和 `!!Order!!` 开头行
- `TStringList.BinarySearch` 语义 = lower_bound（参考 CWOPS.swift 的 findCallRec）
- 布尔开关直接读 `Settings.xxx`
- 类名：TCqWW → `CqWW`，TArrlFieldDay → `ArrlFieldDay`，TNcjNaQp → `NcjNaQp`，TArrlDx → `ArrlDx`，TCWSST → `CWSST`，TALLJA → `ALLJA`，TACAG → `ACAG`，TIaruHf → `IaruHf`，TCqWpx → `CqWpx`，TSweepstakes → `Sweepstakes`
- 工厂（Contest/ContestFactory.swift）已引用这些类名，必须精确匹配
- 文件命名：CqWW.swift, CWSST.swift, ALLJA.swift, ACAG.swift, IaruHf.swift, NaQp.swift, ArrlDx.swift, ArrlFd.swift, CqWpx.swift, Sweepstakes.swift

## 参考实现
CWOPS.swift 是完整范例（必须读）。Delphi 源码在 /tmp/MorseRunner-reference/。

## 验收
- 只写文件，不跑 swift build、不写测试、不跑 linter
- 忠实移植逻辑；每个文件头部注释标注 Delphi 来源文件名
- 完成后回复：写了哪些文件、每个文件对应 Delphi 哪个 unit
