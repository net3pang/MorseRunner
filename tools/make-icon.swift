// Generates the Morse Runner app icon (1024x1024 PNG).
// Usage: swift tools/make-icon.swift <output.png>
//
// Design: rounded-square macOS icon, deep-blue gradient, a CW keying
// waveform spelling "MR" (M = --, R = .-.) and the letters "MR" below.

import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// ---- background: rounded rect + gradient
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                      xRadius: 180, yRadius: 180)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.30, alpha: 1),   // deep navy
    NSColor(calibratedRed: 0.11, green: 0.36, blue: 0.55, alpha: 1),   // blue
])!
gradient.draw(in: bg, angle: -70)

// ---- subtle glow ring
let ring = NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: size - 36, height: size - 36),
                        xRadius: 165, yRadius: 165)
NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.10).setStroke()
ring.lineWidth = 8
ring.stroke()

// ---- CW waveform (M = -- , R = .-.)
let lineY: CGFloat = 620
let dashW: CGFloat = 120
let dotW: CGFloat = 52
let gap: CGFloat = 52
let charGap: CGFloat = 140
let strokeW: CGFloat = 80

NSColor.white.setFill()
NSColor.white.setStroke()

// Morse for MR:  --  .-.
// Visual width = dash + gap + dash + charGap + dot + gap + dash + gap + dot
let total: CGFloat = dashW + gap + dashW + charGap + dotW + gap + dashW + gap + dotW
var x: CGFloat = (size - total) / 2   // centred, both ends keep the stroke radius

func drawElement(_ w: CGFloat) {
    if w > 0 {
        let r = NSRect(x: x, y: lineY - strokeW / 2, width: w, height: strokeW)
        NSBezierPath(roundedRect: r, xRadius: strokeW / 2, yRadius: strokeW / 2).fill()
        x += w + gap
    } else {
        x += charGap
    }
}
drawElement(dashW)   // M: dash
drawElement(dashW)   // M: dash
drawElement(0)       // inter-character space
drawElement(dotW)    // R: dot
drawElement(dashW)   // R: dash
drawElement(dotW)    // R: dot

// ---- "MR" letters
let text = "MR"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 210, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.95),
]
let str = NSAttributedString(string: text, attributes: attrs)
let textSize = str.size()
str.draw(at: NSPoint(x: (size - textSize.width) / 2, y: 90))

image.unlockFocus()

// ---- write PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
