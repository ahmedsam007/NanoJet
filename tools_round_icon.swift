import AppKit
import Foundation

let inPath = "/Users/ahmed/Documents/IDMMac/IDMMacApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let outPath = inPath // overwrite
let targetSize: CGFloat = 1024
let cornerRadius: CGFloat = 196 // approx macOS squircle corner radius
let contentScale: CGFloat = 0.86 // shrink artwork to ~86% of canvas to match Apple icon visual weight

guard let img = NSImage(contentsOf: URL(fileURLWithPath: inPath)) else {
    fputs("Failed to load AppIcon.png\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(targetSize),
    pixelsHigh: Int(targetSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: targetSize, height: targetSize)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.shouldAntialias = true

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: targetSize, height: targetSize)).fill()

let clipPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: targetSize, height: targetSize), xRadius: cornerRadius, yRadius: cornerRadius)
clipPath.addClip()

// Compute target content rect (centered) with inset scale
let insetW = targetSize * contentScale
let insetH = targetSize * contentScale
let insetX = (targetSize - insetW) / 2
let insetY = (targetSize - insetH) / 2
let targetRect = NSRect(x: insetX, y: insetY, width: insetW, height: insetH)

// Scale image to contain within targetRect, preserving aspect ratio
let imgSize = img.size
let scale = min(targetRect.width / imgSize.width, targetRect.height / imgSize.height)
let drawW = imgSize.width * scale
let drawH = imgSize.height * scale
let drawX = targetRect.midX - drawW / 2
let drawY = targetRect.midY - drawH / 2
img.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH), from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(2)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outPath))
    print("Rounded & inset AppIcon written")
} catch {
    fputs("Write failed: \(error)\n", stderr)
    exit(3)
}
