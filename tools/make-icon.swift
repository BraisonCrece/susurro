import CoreGraphics
import Foundation
import ImageIO

// Minimalist app icon: macOS squircle with an indigo gradient and the same rounded
// equalizer bars shown in the recording overlay, so the icon and the live UI match.

func render(size: Int, to url: URL) {
    let s = CGFloat(size)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let margin = s * 0.09
    let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = body.width * 0.2237
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        CGColor(red: 0.486, green: 0.424, blue: 0.961, alpha: 1.0), // top  #7C6CF5
        CGColor(red: 0.357, green: 0.271, blue: 0.878, alpha: 1.0)  // base #5B45E0
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY),
                           options: [])
    ctx.restoreGState()

    let heights: [CGFloat] = [0.30, 0.54, 0.80, 0.54, 0.30]
    let alphas: [CGFloat] = [0.85, 0.93, 1.0, 0.93, 0.85]
    let count = heights.count
    let barWidth = body.width * 0.085
    let gap = body.width * 0.075
    let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
    let startX = body.midX - totalWidth / 2

    for i in 0..<count {
        let height = body.height * heights[i]
        let x = startX + CGFloat(i) * (barWidth + gap)
        let rect = CGRect(x: x, y: body.midY - height / 2, width: barWidth, height: height)
        let bar = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alphas[i]))
        ctx.addPath(bar)
        ctx.fillPath()
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in variants {
    render(size: size, to: outDir.appendingPathComponent("\(name).png"))
}
print("Wrote \(variants.count) PNGs to \(outDir.path)")
