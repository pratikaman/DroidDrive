// Generates AppIcon.icns: macOS-style rounded square with an android head + USB hint.
// Run: swift packaging/make_icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Background: rounded square, green gradient (standard macOS icon inset ~10%).
let inset: CGFloat = size * 0.10
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.30, green: 0.78, blue: 0.42, alpha: 1),
        CGColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size - inset),
    end: CGPoint(x: size / 2, y: inset),
    options: []
)

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

// Android head: half-disc.
let headCenter = CGPoint(x: size / 2, y: size * 0.47)
let headRadius = size * 0.21
ctx.beginPath()
ctx.addArc(center: headCenter, radius: headRadius, startAngle: 0, endAngle: .pi, clockwise: false)
ctx.closePath()
ctx.fillPath()

// Antennae.
ctx.setLineWidth(size * 0.022)
ctx.setLineCap(.round)
for direction: CGFloat in [-1, 1] {
    let angle: CGFloat = .pi / 2 + direction * .pi / 5.5
    let start = CGPoint(
        x: headCenter.x + cos(angle) * headRadius * 0.92,
        y: headCenter.y + sin(angle) * headRadius * 0.92
    )
    let end = CGPoint(
        x: headCenter.x + cos(angle) * headRadius * 1.28,
        y: headCenter.y + sin(angle) * headRadius * 1.28
    )
    ctx.beginPath()
    ctx.move(to: start)
    ctx.addLine(to: end)
    ctx.strokePath()
}

// Eyes (punched out of the head).
ctx.setBlendMode(.clear)
for direction: CGFloat in [-1, 1] {
    let eye = CGRect(
        x: headCenter.x + direction * headRadius * 0.42 - size * 0.021,
        y: headCenter.y + headRadius * 0.38 - size * 0.021,
        width: size * 0.042, height: size * 0.042
    )
    ctx.fillEllipse(in: eye)
}
ctx.setBlendMode(.normal)

// USB hint: cable line with plug below the head.
let cableY = size * 0.335
ctx.setLineWidth(size * 0.026)
ctx.beginPath()
ctx.move(to: CGPoint(x: size * 0.30, y: cableY))
ctx.addLine(to: CGPoint(x: size * 0.62, y: cableY))
ctx.strokePath()
let plug = CGRect(x: size * 0.62, y: cableY - size * 0.032, width: size * 0.09, height: size * 0.064)
ctx.fill(CGPath(roundedRect: plug, cornerWidth: size * 0.012, cornerHeight: size * 0.012, transform: nil).boundingBox)

let image = ctx.makeImage()!

// Write the iconset at every required size.
let iconsetURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let repCtx = NSGraphicsContext(bitmapImageRep: rep)!
    repCtx.cgContext.interpolationQuality = .high
    repCtx.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try! rep.representation(using: .png, properties: [:])!
        .write(to: iconsetURL.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o",
                      URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)
print("AppIcon.icns written to \(outputDir)")
