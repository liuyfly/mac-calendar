import AppKit
import Foundation

// Draws the app icon: a calendar page with a red header band and a grid of
// day dots. Rendered at 1024pt and downsampled by the build script.

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}
context.setShouldAntialias(true)

// macOS icons leave a margin inside their canvas.
let inset: CGFloat = size * 0.09
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner = rect.width * 0.22

// Page.
let page = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
NSColor.white.setFill()
page.fill()

// Header band, clipped to the page's rounded top.
context.saveGState()
page.addClip()
let bandHeight = rect.height * 0.27
let band = NSRect(x: rect.minX, y: rect.maxY - bandHeight, width: rect.width, height: bandHeight)
NSColor(calibratedRed: 0.91, green: 0.27, blue: 0.24, alpha: 1).setFill()
band.fill()
context.restoreGState()

// Binding rings.
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
let ringWidth = rect.width * 0.055
let ringHeight = rect.height * 0.09
for fraction in [0.3, 0.7] {
    let x = rect.minX + rect.width * CGFloat(fraction) - ringWidth / 2
    let ring = NSRect(x: x, y: rect.maxY - bandHeight * 0.62,
                      width: ringWidth, height: ringHeight)
    NSBezierPath(roundedRect: ring, xRadius: ringWidth / 2, yRadius: ringWidth / 2).fill()
}

// Day dots: 4 rows x 5 columns, with one accent dot for "today".
let gridTop = rect.maxY - bandHeight - rect.height * 0.13
let gridLeft = rect.minX + rect.width * 0.16
let gridWidth = rect.width * 0.68
let columns = 5, rows = 4
let stepX = gridWidth / CGFloat(columns - 1)
let stepY = rect.height * 0.135
let dot = rect.width * 0.062

for row in 0..<rows {
    for column in 0..<columns {
        let center = NSPoint(x: gridLeft + CGFloat(column) * stepX,
                             y: gridTop - CGFloat(row) * stepY)
        let isToday = (row == 1 && column == 2)
        if isToday {
            NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1).setFill()
        } else {
            NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
        }
        let box = NSRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
        NSBezierPath(ovalIn: box).fill()
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon.png"
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
