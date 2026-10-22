#!/usr/bin/env swift
import AppKit

// Coordinates match the Finder icon layout in configure-dmg.applescript.
guard CommandLine.arguments.count == 2 else { exit(2) }
let size = NSSize(width: 640, height: 440)
let image = NSImage(size: size)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    let transform = NSAffineTransform()
    transform.scaleX(by: CGFloat(scale), yBy: CGFloat(scale))
    transform.translateX(by: 0, yBy: size.height)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat,
              _ fontSize: CGFloat, _ weight: NSFont.Weight = .regular,
              _ color: NSColor = NSColor(calibratedWhite: 0.22, alpha: 1)) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        (value as NSString).draw(with: NSRect(x: x, y: y, width: width, height: 90),
            options: [.usesLineFragmentOrigin], attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color, .paragraphStyle: style])
    }
    text("Drag Jolt to Applications, then open it from there.", 40, 28, 560, 16)
    text("→", 295, 93, 70, 42, .medium,
         NSColor(calibratedRed: 0.24, green: 0.43, blue: 0.85, alpha: 1))

    text("If macOS blocks Jolt", 40, 226, 560, 18, .semibold)
    text("1", 40, 268, 25, 15, .semibold)
    text("Click Done in the alert.", 70, 268, 530, 15)
    text("2", 40, 307, 25, 15, .semibold)
    text("Open System Settings → Privacy & Security.\nScroll to Security and click Open Anyway for Jolt.", 70, 307, 530, 15)
    text("3", 40, 368, 25, 15, .semibold)
    text("Confirm and enter your Mac login password if asked.", 70, 368, 530, 15)
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = size
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
