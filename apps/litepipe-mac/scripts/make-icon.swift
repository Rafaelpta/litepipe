// Generates Resources/AppIcon.icns: the litepipe snake stroked on a black
// rounded-square plate, rendered as vectors at every iconset size.
// Run from apps/litepipe-mac:  swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import ImageIO

// The four-lobe snake from design/mockup.html (viewBox 0 0 24 24), with the SVG
// smooth-curve (S/s) commands expanded to absolute cubics. SVG is y-down; the
// y-flip to CoreGraphics happens in the transform below.
func snakePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 2, y: 15))
    p.addCurve(to: CGPoint(x: 6.4, y: 9),
               control1: CGPoint(x: 4.2, y: 15), control2: CGPoint(x: 4.2, y: 9))
    p.addCurve(to: CGPoint(x: 10.8, y: 17),
               control1: CGPoint(x: 8.6, y: 9), control2: CGPoint(x: 8.6, y: 17))
    p.addCurve(to: CGPoint(x: 15.2, y: 7),
               control1: CGPoint(x: 13, y: 17), control2: CGPoint(x: 13, y: 7))
    p.addCurve(to: CGPoint(x: 19.6, y: 13),
               control1: CGPoint(x: 17.4, y: 7), control2: CGPoint(x: 17.4, y: 13))
    p.addLine(to: CGPoint(x: 22, y: 13))
    return p
}

func render(px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw everything in a 1024-unit canvas and scale once per size.
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Plate on Apple's icon grid: 824/1024 centered, transparent margin outside.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()

    // Snake centered on the plate, ~59% of canvas width, y flipped from SVG space.
    let k: CGFloat = 600.0 / 24.0
    var t = CGAffineTransform(translationX: 512 - 12 * k, y: 512 + 12 * k)
        .scaledBy(x: k, y: -k)
    let snake = snakePath().copy(using: &t)!
    ctx.addPath(snake)
    ctx.setStrokeColor(CGColor(srgbRed: 0xF2 / 255.0, green: 0xF4 / 255.0,
                               blue: 0xF2 / 255.0, alpha: 1))
    ctx.setLineWidth(2.4 * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    writePNG(render(px: px), to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
