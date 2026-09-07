import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size = points * scale
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    let bg = NSBezierPath(roundedRect: NSRect(x: 35, y: 35, width: 954, height: 954), xRadius: 210, yRadius: 210)
    NSColor(srgbRed: 0.12, green: 0.16, blue: 0.13, alpha: 1).setFill(); bg.fill()
    NSColor(srgbRed: 0.25, green: 0.32, blue: 0.24, alpha: 1).setStroke(); bg.lineWidth = 3; bg.stroke()
    let arm = NSBezierPath(); arm.move(to: NSPoint(x: 310, y: 245)); arm.line(to: NSPoint(x: 290, y: 495)); arm.line(to: NSPoint(x: 535, y: 740)); arm.line(to: NSPoint(x: 750, y: 530))
    arm.lineWidth = 106; arm.lineCapStyle = .round; arm.lineJoinStyle = .round
    NSColor(srgbRed: 0.76, green: 0.90, blue: 0.30, alpha: 1).setStroke(); arm.stroke()
    for point in [NSPoint(x: 310, y: 245), NSPoint(x: 290, y: 495), NSPoint(x: 535, y: 740)] {
        NSColor(srgbRed: 0.20, green: 0.25, blue: 0.21, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 36, y: point.y - 36, width: 72, height: 72)).fill()
        NSColor(srgbRed: 0.68, green: 0.73, blue: 0.67, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)).fill()
    }
    NSColor(srgbRed: 0.80, green: 0.84, blue: 0.79, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 192, y: 155, width: 236, height: 66), xRadius: 15, yRadius: 15).fill()
    let fingers = NSBezierPath(); fingers.move(to: NSPoint(x: 700, y: 503)); fingers.line(to: NSPoint(x: 700, y: 400)); fingers.line(to: NSPoint(x: 737, y: 363)); fingers.move(to: NSPoint(x: 800, y: 503)); fingers.line(to: NSPoint(x: 800, y: 400)); fingers.line(to: NSPoint(x: 763, y: 363))
    fingers.lineWidth = 34; fingers.lineCapStyle = .round; fingers.lineJoinStyle = .round
    NSColor(srgbRed: 0.80, green: 0.84, blue: 0.79, alpha: 1).setStroke(); fingers.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
