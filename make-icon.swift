// Generate AppIcon.icns from a single Swift script. Run from swift/ dir.
import AppKit
import Foundation

let baseDir = FileManager.default.currentDirectoryPath
let iconsetDir = baseDir + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

struct IconSize { let pt: Int; let scale: Int
    var px: Int { pt * scale }
    var filename: String { "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png" }
}

let sizes: [IconSize] = [
    .init(pt: 16,  scale: 1), .init(pt: 16,  scale: 2),
    .init(pt: 32,  scale: 1), .init(pt: 32,  scale: 2),
    .init(pt: 128, scale: 1), .init(pt: 128, scale: 2),
    .init(pt: 256, scale: 1), .init(pt: 256, scale: 2),
    .init(pt: 512, scale: 1), .init(pt: 512, scale: 2),
]

func drawIcon(px: Int) -> Data? {
    let size = CGFloat(px)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let radius = size * 0.225
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: radius, yRadius: radius)
    bg.addClip()

    // Background: subtle dark gradient (matches the app's pane background)
    let gradient = NSGradient(starting: NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1),
                              ending:   NSColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1))!
    gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 270)

    // Bold white "B"
    let fontSize = size * 0.58
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let str = NSAttributedString(string: "B", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
    ])
    let strBox = str.size()
    str.draw(at: NSPoint(x: (size - strBox.width) / 2,
                         y: size * 0.31))

    // Translation underline — blue half + green half (source/translation accents)
    let barWidth  = size * 0.50
    let barHeight = max(2, size * 0.045)
    let barX = (size - barWidth) / 2
    let barY = size * 0.22
    let halfRect = NSRect(x: barX, y: barY, width: barWidth / 2, height: barHeight)
    let blue  = NSColor(red: 0.34, green: 0.62, blue: 1.00, alpha: 1)
    let green = NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1)
    blue.setFill()
    NSBezierPath(roundedRect: halfRect,
                 xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    let rightRect = halfRect.offsetBy(dx: barWidth / 2, dy: 0)
    green.setFill()
    NSBezierPath(roundedRect: rightRect,
                 xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png
}

for s in sizes {
    guard let data = drawIcon(px: s.px) else { continue }
    let url = URL(fileURLWithPath: iconsetDir + "/" + s.filename)
    try? data.write(to: url)
    print("✓ \(s.filename) (\(s.px) px)")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir, "-o", baseDir + "/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ AppIcon.icns" : "✗ iconutil failed")
