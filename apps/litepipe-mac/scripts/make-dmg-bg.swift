// Generates Resources/dmg-background.png (660x400 @2x) for the installer window:
// near-white canvas, snake + wordmark up top, an arrow from the app position to
// the Applications position. Run from apps/litepipe-mac:
//   swift scripts/make-dmg-bg.swift
import AppKit
import CoreGraphics
import CoreText
import ImageIO

let W: CGFloat = 660, H: CGFloat = 400, SCALE: CGFloat = 2

// Same expanded snake path as scripts/make-icon.swift (SVG viewBox 0 0 24 24).
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

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W * SCALE), height: Int(H * SCALE),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: SCALE, y: SCALE)

// Canvas. (Point coordinates below are y-up; yTop converts from design y-down.)
func yTop(_ y: CGFloat) -> CGFloat { H - y }
ctx.setFillColor(CGColor(srgbRed: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xF8 / 255.0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let ink = CGColor(srgbRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x28 / 255.0, alpha: 1)

// Wordmark: small snake + "litepipe", centered near the top.
let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
let text = NSAttributedString(string: "litepipe", attributes: [
    .font: font, .foregroundColor: NSColor(cgColor: ink)!,
])
let line = CTLineCreateWithAttributedString(text)
let textW = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
let markGap: CGFloat = 10
let snakeW: CGFloat = 34
let totalW = snakeW + markGap + textW
let markX = (W - totalW) / 2
let markY: CGFloat = 52 // design y from top, text baseline

let k = snakeW / 24
var t = CGAffineTransform(translationX: markX, y: yTop(markY) + 8 + 12 * k)
    .scaledBy(x: k, y: -k)
ctx.addPath(snakePath().copy(using: &t)!)
ctx.setStrokeColor(ink)
ctx.setLineWidth(2.4 * k)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

ctx.textPosition = CGPoint(x: markX + snakeW + markGap, y: yTop(markY))
CTLineDraw(line, ctx)

// Arrow between the two icon slots (app at x=165, Applications at x=495, both
// centered at design y=190; make-dmg.sh places the Finder icons there).
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 245, y: yTop(180)))
arrow.addQuadCurve(to: CGPoint(x: 415, y: yTop(180)),
                   control: CGPoint(x: 330, y: yTop(140)))
ctx.addPath(arrow)
ctx.setLineWidth(5)
ctx.strokePath()
// Arrowhead at the right end, following the curve's incoming direction.
let tip = CGPoint(x: 419, y: yTop(182))
let head = CGMutablePath()
head.move(to: CGPoint(x: tip.x - 16, y: tip.y + 12))
head.addLine(to: tip)
head.addLine(to: CGPoint(x: tip.x - 18, y: tip.y - 8))
ctx.addPath(head)
ctx.strokePath()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: "Resources/dmg-background.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
// 144 dpi so Finder treats the 1320x800 pixels as 660x400 points (retina-crisp).
CGImageDestinationAddImage(dest, image, [
    kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144,
] as CFDictionary)
CGImageDestinationFinalize(dest)
print("wrote Resources/dmg-background.png")
