// Port of Main.dfm / TMainForm UI — the main window.
//
// Layout follows the original: contest/station strip on top, band conditions,
// the QSO entry fields with function-key buttons, the score table with the
// summary, and a status bar. The simulation itself runs in SimController.

import AppKit
import MorseRunnerCore

/// Forces text fields to uppercase as the user types (Delphi OnChange
/// behavior for the call/exchange entry fields).
private final class UpperCaseFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        (obj as? String)?.uppercased()
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string.uppercased() as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        newString?.pointee = partialString.uppercased() as NSString
        return true
    }
}

public final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {    private let sim = SimController.shared

    // ---- top strip
    private let contestCombo = NSPopUpButton()
    private let callField = NSTextField(string: Settings.call)
    private let exchangeField = NSTextField(string: "")
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let modeCombo = NSPopUpButton()

    // ---- band strip
    private let wpmSlider = NSSlider(value: 25, minValue: 10, maxValue: 120, target: nil, action: nil)
    private let wpmLabel = NSTextField(labelWithString: "25 wpm")
    private let pitchCombo = NSPopUpButton()
    private let bwCombo = NSPopUpButton()
    private let activityField = NSTextField(string: "2")
    private let durationField = NSTextField(string: "30")
    private let ritLabel = NSTextField(labelWithString: "RIT 0")

    // ---- conditions
    private let qsbCheck = NSButton(checkboxWithTitle: "QSB", target: nil, action: nil)
    private let qrmCheck = NSButton(checkboxWithTitle: "QRM", target: nil, action: nil)
    private let qrnCheck = NSButton(checkboxWithTitle: "QRN", target: nil, action: nil)
    private let flutterCheck = NSButton(checkboxWithTitle: "Flutter", target: nil, action: nil)
    private let lidsCheck = NSButton(checkboxWithTitle: "Lids", target: nil, action: nil)
    private let monitorSlider = NSSlider(value: 0.75, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let outputVolumeSlider = NSSlider(value: 0.35, minValue: 0, maxValue: 1, target: nil, action: nil)

    // ---- receive CW speed limits (original: Settings -> CW Max/Min Rx Speed)
    private let maxRxWpmCombo = NSPopUpButton()
    private let minRxWpmCombo = NSPopUpButton()

    // ---- serial number mode (original: Settings -> Serial NR)
    private let serialNRCombo = NSPopUpButton()

    // ---- entry
    private let callEntry = NSTextField(string: "")
    private let exch1Entry = NSTextField(string: "")
    private let exch2Entry = NSTextField(string: "")
    private let exch1Label = NSTextField(labelWithString: "RST")
    private let exch2Label = NSTextField(labelWithString: "Exch")

    // ---- score
    private let logTable = NSTableView()
    private let logScroll = NSScrollView()
    private let rawPtsLabel = NSTextField(labelWithString: "")
    private let rawMultLabel = NSTextField(labelWithString: "")
    private let rawScoreLabel = NSTextField(labelWithString: "")
    private let verPtsLabel = NSTextField(labelWithString: "")
    private let verMultLabel = NSTextField(labelWithString: "")
    private let verScoreLabel = NSTextField(labelWithString: "")

    // ---- status
    private let clockLabel = NSTextField(labelWithString: "00:00:00")
    private let pileupLabel = NSTextField(labelWithString: "")
    private let rateLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "")
    private let hstScoreLabel = NSTextField(labelWithString: "")
    private let statusBar = NSTextField(labelWithString: "")

    private var running = false

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1190, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Morse Runner for macOS"
        window.minSize = NSSize(width: 1060, height: 560)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        self.init(window: window)
        window.contentViewController = buildContent()
        setup()
    }

    // MARK: - layout

    private func buildContent() -> NSViewController {
        let vc = NSViewController()
        let root = NSView()

        // ---- row 0: contest / station
        contestCombo.target = self
        contestCombo.action = #selector(contestChanged)
        for def in contestDefinitions {
            contestCombo.addItem(withTitle: def.name)
        }

        callField.placeholderString = "My call"
        callField.target = self
        callField.action = #selector(myCallEntered)
        exchangeField.placeholderString = "Sent exchange (e.g. 3A OR)"
        exchangeField.target = self
        exchangeField.action = #selector(exchangeEntered)

        runButton.target = self
        runButton.action = #selector(runToggled)
        modeCombo.addItems(withTitles: ["Pile-Up", "Single Calls", "COMPETITION", "H S T"])
        modeCombo.target = self
        modeCombo.action = #selector(modeChanged)

        serialNRCombo.addItems(withTitles: [
            "Serial NR: Start of Contest", "Serial NR: Mid-Contest",
            "Serial NR: End of Contest", "Serial NR: Custom",
        ])
        serialNRCombo.target = self
        serialNRCombo.action = #selector(serialNRChanged)
        serialNRCombo.toolTip = "Serial NR mode (original Settings -> Serial NR); Custom asks for a range"

        let row0 = NSStackView(views: [
            label("Contest"), contestCombo,
            label("Call"), callField,
            label("Exch"), exchangeField,
            runButton, modeCombo,
            serialNRCombo,
        ])
        row0.orientation = .horizontal
        row0.spacing = 6

        // ---- row 1: band strip
        wpmSlider.target = self
        wpmSlider.action = #selector(wpmChanged)
        pitchCombo.target = self
        pitchCombo.action = #selector(pitchChanged)
        for p in stride(from: 300, through: 1000, by: 50) {
            pitchCombo.addItem(withTitle: "\(p) Hz")
        }
        bwCombo.target = self
        bwCombo.action = #selector(bwChanged)
        for b in stride(from: 100, through: 1000, by: 50) {
            bwCombo.addItem(withTitle: "\(b) Hz")
        }
        activityField.alignment = .right
        durationField.alignment = .right
        durationField.target = self
        durationField.action = #selector(durationChanged)

        // uppercase as-you-type for call / exchange fields
        for field in [callEntry, exch1Entry, exch2Entry] {
            field.formatter = UpperCaseFormatter()
        }

        for (combo, action) in [(maxRxWpmCombo, #selector(rxWpmChanged)), (minRxWpmCombo, #selector(rxWpmChanged))] {
            combo.addItems(withTitles: ["0", "1", "2", "4", "6", "8", "10"])
            combo.target = self
            combo.action = action
        }
        maxRxWpmCombo.toolTip = "CW Max Rx Speed (0 = same as TX speed)"
        minRxWpmCombo.toolTip = "CW Min Rx Speed (0 = same as TX speed)"

        let row1 = NSStackView(views: [
            label("CW Speed"), wpmSlider, wpmLabel,
            label("Pitch"), pitchCombo,
            label("Bandwidth"), bwCombo,
            label("Activity"), activityField,
            label("Duration (min)"), durationField,
            label("RxMax"), maxRxWpmCombo,
            label("RxMin"), minRxWpmCombo,
            ritLabel,
        ])
        row1.orientation = .horizontal
        row1.spacing = 6

        // ---- row 2: conditions
        for (check, action) in [(qsbCheck, #selector(conditionChanged)), (qrmCheck, #selector(conditionChanged)),
                                (qrnCheck, #selector(conditionChanged)), (flutterCheck, #selector(conditionChanged)),
                                (lidsCheck, #selector(conditionChanged))] {
            check.target = self
            check.action = action
        }
        monitorSlider.isContinuous = true
        monitorSlider.target = self
        monitorSlider.action = #selector(monitorChanged)
        outputVolumeSlider.isContinuous = true
        outputVolumeSlider.target = self
        outputVolumeSlider.action = #selector(outputVolumeChanged)
        let row2 = NSStackView(views: [
            qsbCheck, qrmCheck, qrnCheck, flutterCheck, lidsCheck,
            label("Self Monitor"), monitorSlider,
            label("Output"), outputVolumeSlider,
        ])
        row2.orientation = .horizontal
        row2.spacing = 10

        // ---- row 3: QSO entry + function keys
        callEntry.placeholderString = "Call"
        callEntry.target = self
        callEntry.action = #selector(callEntryEntered)
        callEntry.cell?.sendsActionOnEndEditing = false
        exch1Entry.placeholderString = "Exch1"
        exch1Entry.target = self
        exch1Entry.action = #selector(exch1Entered)
        exch1Entry.cell?.sendsActionOnEndEditing = false
        exch2Entry.placeholderString = "Exch2"
        exch2Entry.target = self
        exch2Entry.action = #selector(exch2Entered)
        exch2Entry.cell?.sendsActionOnEndEditing = false

        let fKeys: [(String, StationMessage)] = [
            ("F1 CQ", .cq), ("F2 NR", .nr), ("F3 TU", .tu), ("F4 MyCall", .myCall),
            ("F5 HisCall", .hisCall), ("F6 B4", .b4), ("F7 ?", .qm), ("F8 NIL", .nil_),
        ]
        callEntry.widthAnchor.constraint(equalToConstant: 110).isActive = true
        exch1Entry.widthAnchor.constraint(equalToConstant: 70).isActive = true
        exch2Entry.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let entryRow = NSStackView(views: [label("Call"), callEntry,
                                           exch1Label, exch1Entry,
                                           exch2Label, exch2Entry])
        entryRow.orientation = .horizontal
        entryRow.spacing = 4

        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.spacing = 6
        for (title, msg) in fKeys {
            let b = NSButton(title: title, target: self, action: #selector(msgButtonPressed(_:)))
            b.tag = msg.rawValue
            keyRow.addArrangedSubview(b)
        }

        // ---- row 4: score table + summary
        logTable.addTableColumn(makeColumn("UTC", width: 70))
        logTable.addTableColumn(makeColumn("Call", width: 90))
        logTable.addTableColumn(makeColumn("RST/Exch1", width: 70))
        logTable.addTableColumn(makeColumn("Exch2", width: 80))
        logTable.addTableColumn(makeColumn("Corrections", width: 110))
        logTable.addTableColumn(makeColumn("Wpm", width: 45))
        logTable.usesAlternatingRowBackgroundColors = true
        logTable.rowHeight = 17
        logTable.allowsMultipleSelection = false
        logScroll.documentView = logTable
        logScroll.hasVerticalScroller = true

        func summaryLabel(_ text: String, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            if bold {
                l.font = NSFont.boldSystemFont(ofSize: 12)
            }
            return l
        }
        let summary = NSStackView(views: [
            summaryLabel("Raw", bold: true), rawPtsLabel, rawMultLabel, rawScoreLabel,
            summaryLabel("Verified", bold: true), verPtsLabel, verMultLabel, verScoreLabel,
            summaryLabel("Rate"), rateLabel,
            summaryLabel("Pile-Up"), pileupLabel,
            hstScoreLabel,
        ])
        summary.orientation = .vertical
        summary.alignment = .left
        summary.spacing = 4
        summary.setHuggingPriority(.defaultHigh, for: .horizontal)

        let tableRow = NSStackView(views: [logScroll, summary])
        tableRow.orientation = .horizontal
        tableRow.spacing = 8

        // ---- row 5: status
        statusBar.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusBar.lineBreakMode = .byTruncatingTail
        let statusRow = NSStackView(views: [clockLabel, modeLabel, statusBar])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12

        // ---- assemble
        let stack = NSStackView(views: [row0, row1, row2, entryRow, keyRow, tableRow, statusRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        root.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            logScroll.widthAnchor.constraint(equalToConstant: 560),
            row0.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        vc.view = root
        return vc
    }

    private func makeColumn(_ title: String, width: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
        col.title = title
        col.width = width
        return col
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    // MARK: - setup

    private func setup() {
        Settings.loadFromDefaults()
        logTable.dataSource = self
        logTable.delegate = self
        SimEngine.shared.uiHooks.userName = Settings.hamName
        SimEngine.shared.uiHooks.volume = Float(monitorSlider.doubleValue)

        // engine -> UI hooks
        SimEngine.shared.uiHooks.onScoreTableInsert = { [weak self] row in
            self?.logRows.append(row)
            self?.logTable.reloadData()
            if let n = self?.logRows.count, n > 0 {
                self?.logTable.scrollRowToVisible(n - 1)
            }
        }
        SimEngine.shared.uiHooks.onStatsUpdate = { [weak self] s in
            self?.rawPtsLabel.stringValue = "Pts: \(s.points)"
            self?.rawMultLabel.stringValue = "Mult: \(s.mults)"
            self?.rawScoreLabel.stringValue = "Score: \(s.points * s.mults)"
            self?.verPtsLabel.stringValue = "Pts: \(s.verifiedPoints)"
            self?.verMultLabel.stringValue = "Mult: \(s.verifiedMults)"
            self?.verScoreLabel.stringValue = "Score: \(s.verifiedPoints * s.verifiedMults)"
        }
        SimEngine.shared.uiHooks.onRateUpdate = { [weak self] rate in
            self?.rateLabel.stringValue = "\(rate) qso/hr"
        }
        SimEngine.shared.uiHooks.onClockUpdate = { [weak self] t in
            self?.clockLabel.stringValue = t
        }
        SimEngine.shared.uiHooks.onPileupCount = { [weak self] n in
            self?.pileupLabel.stringValue = "\(n)"
        }
        SimEngine.shared.uiHooks.onStatusBar = { [weak self] text, isError in
            self?.statusBar.stringValue = text
            self?.statusBar.textColor = isError ? .systemRed : .labelColor
        }
        SimEngine.shared.uiHooks.onExchangeLabel = { [weak self] text in
            self?.exch2Label.stringValue = text
        }
        SimEngine.shared.uiHooks.onRecvExchTypes = { [weak self] types in
            guard let self else { return }
            self.exch1Label.stringValue = exchange1Settings[types.exch1]?.caption ?? "Exch1"
            self.exch2Label.stringValue = exchange2Settings[types.exch2]?.caption ?? "Exch2"
            self.exch1Entry.placeholderString = exchange1Settings[types.exch1]?.caption ?? "Exch1"
            self.exch2Entry.placeholderString = exchange2Settings[types.exch2]?.caption ?? "Exch2"
        }
        SimEngine.shared.uiHooks.onWipeBoxes = { [weak self] in
            self?.callEntry.stringValue = ""
            self?.exch1Entry.stringValue = ""
            self?.exch2Entry.stringValue = ""
            self?.window?.makeFirstResponder(self?.callEntry)
        }
        SimEngine.shared.uiHooks.onAdvance = { [weak self] in
            guard let self else { return }
            // original Advance(): auto-fill 599 when the received Exch1 is RST
            let types = SimEngine.shared.uiHooks.recvExchTypes
            if types.exch1 == .rst && Settings.runMode != .hst && self.exch1Entry.stringValue.isEmpty {
                self.exch1Entry.stringValue = "599"
                self.sim.enteredExch1 = "599"
            }
            self.window?.makeFirstResponder(self.exch2Entry)
        }
        SimEngine.shared.uiHooks.onRunState = { [weak self] mode in
            self?.running = mode != .stop
            self?.runButton.title = mode == .stop ? "Run" : "Stop"
            let names = ["", "Pile-Up", "Single Calls", "COMPETITION", "H S T"]
            self?.modeLabel.stringValue = mode == .stop ? "" : names[mode.rawValue]
            self?.modeLabel.textColor = (mode == .wpx || mode == .hst) ? .systemRed : .systemGreen
        }
        SimEngine.shared.uiHooks.onHstScore = { [weak self] score in
            self?.hstScoreLabel.stringValue = "HST Score: \(score)"
        }
        SimEngine.shared.uiHooks.onUserNameChange = { [weak self] name in
            self?.window?.title = name.isEmpty
                ? "Morse Runner for macOS"
                : "Morse Runner for macOS — \(name)"
        }
        SimEngine.shared.uiHooks.onShowScore = { [weak self] in
            self?.showScoreDialog()
        }

        // the engine requests a stop (run expired / FStopPressed)
        SimEngine.shared.uiHooks.onRunStopped = { [weak self] in
            self?.sim.handleRunStopped()
        }

        // debug CW stream to the status bar — only when the debug option is
        // enabled (original: "if BDebugCwDecoder and not (self is TQrmStation)").
        SimEngine.shared.debugCwStream = { [weak self] text in
            guard Settings.debugCwDecoder else { return }
            Log.shared.sbarUpdateDebugMsg(text)
        }
        SimEngine.shared.debugGhosting = { [weak self] text in
            self?.statusBar.stringValue = (text + "; " + (self?.statusBar.stringValue ?? "")).prefix(80).description
        }

        // initial contest + widgets
        sim.setContest(Settings.simContest)
        contestCombo.selectItem(at: Settings.simContest.rawValue)
        callField.stringValue = Settings.call
        exchangeField.stringValue = sim.exchangeEdit
        wpmSlider.doubleValue = Double(Settings.wpm)
        wpmChanged()
        pitchCombo.selectItem(at: (Settings.pitch - 300) / 50)
        bwCombo.selectItem(at: (Settings.bandWidth - 100) / 50)
        activityField.stringValue = String(Settings.activity)
        durationField.stringValue = String(Settings.duration)
        maxRxWpmCombo.selectItem(at: max(0, maxRxWpmCombo.indexOfItem(withTitle: String(Settings.maxRxWpm))))
        minRxWpmCombo.selectItem(at: max(0, minRxWpmCombo.indexOfItem(withTitle: String(Settings.minRxWpm))))
        serialNRCombo.selectItem(at: min(max(0, Settings.serialNR.rawValue), serialNRCombo.numberOfItems - 1))
        qsbCheck.state = Settings.qsb ? .on : .off
        qrmCheck.state = Settings.qrm ? .on : .off
        qrnCheck.state = Settings.qrn ? .on : .off
        flutterCheck.state = Settings.flutter ? .on : .off
        lidsCheck.state = Settings.lids ? .on : .off
        SimEngine.shared.uiHooks.volume = 0.75
        monitorSlider.doubleValue = 0.75
        sim.masterVolume = 0.35
        outputVolumeSlider.doubleValue = 0.35
        updateRitLabel()
        updateColumns(for: Settings.simContest)
        installKeyMonitor()
    }

    /// Copy the entry fields into the controller before sending a message,
    /// so HisCall uses the call currently being typed (not the previous QSO).
    private func syncEntryFields() {
        sim.enteredCall = callEntry.stringValue.uppercased()
        sim.enteredExch1 = exch1Entry.stringValue.uppercased()
        sim.enteredExch2 = exch2Entry.stringValue.uppercased()
    }

    /// Global key handling (port of FormKeyDown/FormKeyPress): function keys
    /// F1-F11, Insert, Esc, and the '.' ';' ',' '[' '+' shortcuts.
    private func installKeyMonitor() {
        // F-key keyCodes on macOS: F1=122, F2=120, F3=99, F4=118, F5=96,
        // F6=97, F7=98, F8=100, F9=101, F10=109, F11=103
        let f1toF8: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100]
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let chars = event.charactersIgnoringModifiers ?? ""
            let mods = event.modifierFlags
            let keyCode = event.keyCode

            // function keys (sync typed call/exchange first)
            if let idx = f1toF8.firstIndex(of: keyCode) {
                self.syncEntryFields()
                let msgs: [StationMessage] = [.cq, .nr, .tu, .myCall, .hisCall, .b4, .qm, .nil_]
                self.sim.sendMsg(msgs[idx])
                return nil
            }
            switch keyCode {
            case 101:  // F9
                if mods.contains(.control) || mods.contains(.option) {
                    self.changeSpeed(-1)
                    return nil
                }
                return event
            case 109:  // F10
                if mods.contains(.control) || mods.contains(.option) {
                    self.changeSpeed(1)
                    return nil
                }
                return event
            case 103:  // F11
                self.sim.wipeBoxes()
                return nil
            default:
                break
            }

            // special keys
            if keyCode == 53 {  // Esc: abort send
                self.sim.abortSend()
                return nil
            }
            if let special = event.specialKey {
                switch special {
                case .insert:
                    self.sim.hisAndNR()
                    return nil
                case .pageUp:
                    self.changeSpeed(1)
                    return nil
                case .pageDown:
                    self.changeSpeed(-1)
                    return nil
                case .upArrow:
                    self.adjustRit(1)
                    return nil
                case .downArrow:
                    self.adjustRit(-1)
                    return nil
                default:
                    return event
                }
            }

            // character shortcuts
            if mods.contains(.control) && chars.lowercased() == "w" {
                self.sim.wipeBoxes()
                return nil
            }
            switch chars {
            case ";":
                self.syncEntryFields()
                self.sim.hisAndNR()
                return nil
            case ".", "+", "[", ",":
                self.syncEntryFields()
                self.sim.tuAndSave()
                return nil
            case " ":
                // advance to the next exchange field
                if self.window?.firstResponder !== self.callEntry.currentEditor() {
                    self.window?.makeFirstResponder(self.exch2Entry)
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func changeSpeed(_ delta: Int) {
        let wpm = max(10, min(120, Settings.wpm + delta * Settings.wpmStepRate))
        wpmSlider.doubleValue = Double(wpm)
        wpmChanged()
    }

    private func adjustRit(_ delta: Int) {
        Settings.rit = max(-500, min(500, Settings.rit + delta * Settings.ritStepIncr))
        sim.setRit(Settings.rit)
        updateRitLabel()
    }

    /// Per-contest score-table columns (port of Log.ScoreTableInit).
    private func updateColumns(for contest: SimContest) {
        let headers: [String]
        switch contest {
        case .cwt: headers = ["UTC", "Call", "Name", "Exch", "Corrections", "Wpm"]
        case .sst: headers = ["UTC", "Call", "Name", "Exch", "Corrections", "Wpm"]
        case .fieldDay: headers = ["UTC", "Call", "Class", "Sect", "Corrections", "Wpm"]
        case .arrlSS: headers = ["UTC", "Call", "Nr", "Pr", "Chk", "Sect", "Corrections", "Wpm"]
        case .naQp: headers = ["UTC", "Call", "Name", "State", "Pref", "Corrections", "Wpm"]
        case .cqww: headers = ["UTC", "Call", "RST", "Zone", "Corrections", "Wpm"]
        case .arrlDx, .allJa, .acag, .iaruHf: headers = ["UTC", "Call", "RST", "Exch", "Corrections", "Wpm"]
        case .wpx: headers = ["UTC", "Call", "RST", "Exch", "Corrections", "Wpm"]
        case .hst: headers = ["UTC", "Call", "RST", "Exch", "Score", "Correct", "Wpm"]
        }
        while logTable.tableColumns.count < headers.count {
            logTable.addTableColumn(makeColumn("", width: 70))
        }
        while logTable.tableColumns.count > headers.count {
            logTable.removeTableColumn(logTable.tableColumns.last!)
        }
        for (i, h) in headers.enumerated() {
            logTable.tableColumns[i].title = h
            logTable.tableColumns[i].width = h == "Corrections" ? 110 : 65
        }
        logRows = []
        logTable.reloadData()
    }

    // MARK: - actions

    @objc private func contestChanged() {
        let idx = contestCombo.indexOfSelectedItem
        if let contest = SimContest(rawValue: idx) {
            sim.setContest(contest)
            exchangeField.stringValue = sim.exchangeEdit
            updateColumns(for: contest)
            Settings.saveToDefaults()
        }
    }

    @objc private func myCallEntered() {
        // save regardless of SetMyCall's exchange-validation result, exactly
        // like the original Edit4Exit (SetMyCall without checking the return)
        _ = sim.setMyCall(callField.stringValue.uppercased())
        Settings.saveToDefaults()
    }

    @objc private func exchangeEntered() {
        _ = sim.setMyExchange(exchangeField.stringValue.uppercased())
        Settings.saveToDefaults()
    }

    @objc private func runToggled() {
        if running {
            sim.stop()
        } else {
            let mode = RunMode(rawValue: modeCombo.indexOfSelectedItem + 1) ?? .pileup
            sim.run(mode)
        }
    }

    @objc private func modeChanged() {
        // modes are enabled only while stopped
        guard !running else { return }
        let mode = RunMode(rawValue: modeCombo.indexOfSelectedItem + 1) ?? .pileup
        if mode == .wpx || mode == .hst {
            Settings.compDuration = Int(durationField.stringValue) ?? Settings.compDuration
        }
    }

    @objc private func wpmChanged() {
        let wpm = Int(wpmSlider.doubleValue.rounded())
        wpmLabel.stringValue = "\(wpm) wpm"
        sim.setWpm(wpm)
    }

    @objc private func pitchChanged() {
        sim.setPitch(300 + pitchCombo.indexOfSelectedItem * 50)
    }

    @objc private func bwChanged() {
        sim.setBandwidth(100 + bwCombo.indexOfSelectedItem * 50)
    }

    @objc private func conditionChanged() {
        Settings.qsb = qsbCheck.state == .on
        Settings.qrm = qrmCheck.state == .on
        Settings.qrn = qrnCheck.state == .on
        Settings.flutter = flutterCheck.state == .on
        Settings.lids = lidsCheck.state == .on
    }

    @objc private func monitorChanged() {
        SimEngine.shared.uiHooks.volume = Float(monitorSlider.doubleValue)
        // persist dB: Db = 60 * (value - 1)
        Settings.monLevel = Int((monitorSlider.doubleValue - 1) * 60)
    }

    @objc private func outputVolumeChanged() {
        sim.masterVolume = Float(outputVolumeSlider.doubleValue)
    }

    /// Settings -> Serial NR (Start/Mid/End of Contest, Custom range).
    @objc private func serialNRChanged() {
        let idx = serialNRCombo.indexOfSelectedItem
        guard let mode = SerialNRType(rawValue: idx) else { return }
        if mode == .customRange {
            let current = Settings.serialNRSettings[.customRange]?.rangeStr ?? "01-99"
            guard let newRange = promptForCustomRange(current: current) else {
                // restore previous selection
                serialNRCombo.selectItem(at: Settings.serialNR.rawValue)
                return
            }
            if let parsed = Settings.serialNRSettings[.customRange],
               let s = parseRange(newRange, into: parsed) {
                Settings.serialNRSettings[.customRange] = s
            } else {
                serialNRCombo.selectItem(at: Settings.serialNR.rawValue)
                return
            }
        }
        Settings.serialNR = mode
        Contest.shared?.serialNrModeChanged()
        Settings.saveToDefaults()
    }

    private func parseRange(_ text: String, into s: SerialNumberSettings) -> SerialNumberSettings? {
        // accept "01-99" or "1-99"
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[0] <= parts[1] else { return nil }
        var copy = s
        copy.rangeStr = text.uppercased()
        copy.minVal = parts[0]
        copy.maxVal = parts[1]
        copy.minDigits = max(1, String(parts[0]).count)
        copy.maxDigits = max(1, String(parts[1]).count)
        return copy
    }

    private func promptForCustomRange(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Custom Serial NR Range"
        alert.informativeText = "Enter a range, e.g. 01-99"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: current)
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    /// Run duration in minutes (original SpinEdit2 / Settings -> Duration).
    @objc private func durationChanged() {
        if let v = Int(durationField.stringValue) {
            Settings.duration = max(1, min(180, v))
            durationField.stringValue = String(Settings.duration)
            Settings.saveToDefaults()
        }
    }

    /// Settings -> CW Max/Min Rx Speed (original menu options 0,1,2,4,6,8,10).
    @objc private func rxWpmChanged() {
        let items = [0, 1, 2, 4, 6, 8, 10]
        let idxMax = maxRxWpmCombo.indexOfSelectedItem
        let idxMin = minRxWpmCombo.indexOfSelectedItem
        if items.indices.contains(idxMax) { Settings.maxRxWpm = items[idxMax] }
        if items.indices.contains(idxMin) { Settings.minRxWpm = items[idxMin] }
        Settings.saveToDefaults()
    }

    @objc private func callEntryEntered() {
        sim.enteredCall = callEntry.stringValue.uppercased()
        if NSEvent.modifierFlags.contains(.control) || NSEvent.modifierFlags.contains(.shift)
            || NSEvent.modifierFlags.contains(.option) {
            sim.saveQsoShortcut()
        } else {
            sim.enterKeyPressed()
        }
    }

    @objc private func exch1Entered() {
        sim.enteredCall = callEntry.stringValue.uppercased()
        sim.enteredExch1 = exch1Entry.stringValue.uppercased()
        sim.enterKeyPressed()
    }

    @objc private func exch2Entered() {
        sim.enteredCall = callEntry.stringValue.uppercased()
        sim.enteredExch1 = exch1Entry.stringValue.uppercased()
        sim.enteredExch2 = exch2Entry.stringValue.uppercased()
        sim.enterKeyPressed()
    }

    @objc private func msgButtonPressed(_ sender: NSButton) {
        syncEntryFields()
        if let msg = StationMessage(rawValue: sender.tag) {
            sim.sendMsg(msg)
        }
    }

    @objc private func conditionCheckChanged() {
        conditionChanged()
    }

    private func updateRitLabel() {
        ritLabel.stringValue = "RIT \(Settings.rit)"
    }

    // MARK: - table data source

    private var logRows: [ScoreTableRow] = []

    public func numberOfRows(in tableView: NSTableView) -> Int {
        logRows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < logRows.count else { return nil }
        let cols = logRows[row].columns
        let idx = tableView.tableColumns.firstIndex { $0 === tableColumn } ?? 0
        guard idx < cols.count else { return nil }
        let cell = NSTextField(labelWithString: cols[idx])
        cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        return cell
    }

    /// End-of-run score dialog (port of PopupScoreWpx / PopupScoreHst).
    private func showScoreDialog() {
        let log = Log.shared
        let verifiedScore = log.verifiedPoints * log.verifiedMultList.count
        let rawScore = log.rawPoints * log.rawMultList.count
        let mode = Settings.runMode == .hst ? "HST" : "Competition"
        let message: String
        if Settings.runMode == .hst {
            message = "HST Score: \(log.rawPoints)\nVerified: \(log.verifiedPoints)"
        } else {
            message = """
            \(mode) complete.

            Raw:      \(log.rawPoints) pts × \(log.rawMultList.count) mults = \(rawScore)
            Verified: \(log.verifiedPoints) pts × \(log.verifiedMultList.count) mults = \(verifiedScore)
            """
        }
        let alert = NSAlert()
        alert.messageText = "Morse Runner — \(mode) Results"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
