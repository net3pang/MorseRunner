import AppKit

// MorseRunner for macOS — native port of the classic CW contest simulator.
// Entry point: builds the app object, wires the delegate, runs the event loop.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
