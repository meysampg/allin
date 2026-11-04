#!/usr/bin/env swift
// Renders the All-In macOS app icon into AllIn/Resources/Assets.xcassets/AppIcon.appiconset (16...1024 px).
// "Ace over the hearth": two gilded cards fanned over a rune-ringed felt disc on a dark night squircle.
// Sizes 16 and 32 (1x and 2x) use a simplified master without the coin, rune gaps and card details.
// Run from the repository root:  swift Tools/make_app_icon.swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let assetsDir = "AllIn/Resources/Assets.xcassets"
let outDir = "\(assetsDir)/AppIcon.appiconset"

struct Variant {
  let detail: Bool
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [
    CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
  ])!
}

let gold: UInt32 = 0xD9A441
let ink: UInt32 = 0x1B1B1B
let rune: UInt32 = 0x7FE3FF

// MARK: - Suit paths (copied from CardSuitPaths.swift; y-up unit box)

func heartPath() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 0.5, y: 0))
  p.addCurve(to: CGPoint(x: 0, y: 0.68), control1: CGPoint(x: 0.35, y: 0.18), control2: CGPoint(x: 0, y: 0.42))
  p.addCurve(to: CGPoint(x: 0.5, y: 0.78), control1: CGPoint(x: 0, y: 0.92), control2: CGPoint(x: 0.32, y: 1.0))
  p.addCurve(to: CGPoint(x: 1, y: 0.68), control1: CGPoint(x: 0.68, y: 1.0), control2: CGPoint(x: 1, y: 0.92))
  p.addCurve(to: CGPoint(x: 0.5, y: 0), control1: CGPoint(x: 1, y: 0.42), control2: CGPoint(x: 0.65, y: 0.18))
  p.closeSubpath()
  return p
}

func spadePath() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 0.5, y: 1))
  p.addCurve(to: CGPoint(x: 0, y: 0.38), control1: CGPoint(x: 0.35, y: 0.82), control2: CGPoint(x: 0, y: 0.58))
  p.addCurve(to: CGPoint(x: 0.5, y: 0.26), control1: CGPoint(x: 0, y: 0.12), control2: CGPoint(x: 0.32, y: 0.04))
  p.addCurve(to: CGPoint(x: 1, y: 0.38), control1: CGPoint(x: 0.68, y: 0.04), control2: CGPoint(x: 1, y: 0.12))
  p.addCurve(to: CGPoint(x: 0.5, y: 1), control1: CGPoint(x: 1, y: 0.58), control2: CGPoint(x: 0.65, y: 0.82))
  p.closeSubpath()
  p.move(to: CGPoint(x: 0.5, y: 0.4))
  p.addLine(to: CGPoint(x: 0.64, y: 0))
  p.addLine(to: CGPoint(x: 0.36, y: 0))
  p.closeSubpath()
  return p
}

/// Outline of `text` in the bold system font; y-up, baseline at y = 0.
func textPath(_ text: String, fontSize: CGFloat) -> CGPath {
  let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
    ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
  let attributed = CFAttributedStringCreateMutable(nil, 0)!
  CFAttributedStringReplaceString(attributed, CFRangeMake(0, 0), text as CFString)
  CFAttributedStringSetAttribute(attributed, CFRangeMake(0, text.utf16.count), kCTFontAttributeName, font)
  let line = CTLineCreateWithAttributedString(attributed)
  let result = CGMutablePath()
  for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
    CTRunGetPositions(run, CFRangeMake(0, 0), &positions)
    for i in 0..<count {
      guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
      result.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
    }
  }
  return result
}

// MARK: - Drawing helpers

func fill(_ ctx: CGContext, _ path: CGPath, _ hex: UInt32, alpha: CGFloat = 1) {
  ctx.setFillColor(color(hex, alpha: alpha))
  ctx.addPath(path)
  ctx.fillPath()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ hex: UInt32, width: CGFloat, alpha: CGFloat = 1) {
  ctx.setStrokeColor(color(hex, alpha: alpha))
  ctx.setLineWidth(width)
  ctx.addPath(path)
  ctx.strokePath()
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
  CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

func diamond(_ c: CGPoint, _ s: CGFloat, angle: CGFloat = 0) -> CGPath {
  let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 0, y: s / 2))
  p.addLine(to: CGPoint(x: s / 3, y: 0))
  p.addLine(to: CGPoint(x: 0, y: -s / 2))
  p.addLine(to: CGPoint(x: -s / 3, y: 0))
  p.closeSubpath()
  return p.copy(using: [t])!
}

/// Suit path scaled to `width` and centred on `c`.
func suit(_ unit: CGPath, width: CGFloat, at c: CGPoint) -> CGPath {
  var t = CGAffineTransform(translationX: c.x - width / 2, y: c.y - width / 2).scaledBy(x: width, y: width)
  return unit.copy(using: &t)!
}

/// A card in its local frame: pivot at bottom centre, then rotated by `degrees` about `pivot`.
func drawCard(_ ctx: CGContext, pivot: CGPoint, degrees: CGFloat, detail: Bool, content: (CGContext) -> Void) {
  ctx.saveGState()
  ctx.translateBy(x: pivot.x, y: pivot.y)
  ctx.rotate(by: degrees * .pi / 180)
  let rect = CGRect(x: -150, y: 0, width: 300, height: 420)
  let face = CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, alpha: 0.45))
  fill(ctx, face, 0xFBF6EA)
  ctx.restoreGState()
  let frameWidth: CGFloat = detail ? 12 : 20
  let frameRect = rect.insetBy(dx: 18, dy: 18)
  stroke(ctx, CGPath(roundedRect: frameRect, cornerWidth: 20, cornerHeight: 20, transform: nil), gold,
         width: frameWidth)
  if detail {
    let inner = frameRect.insetBy(dx: frameWidth / 2 + 4, dy: frameWidth / 2 + 4)
    stroke(ctx, CGPath(roundedRect: inner, cornerWidth: 12, cornerHeight: 12, transform: nil), 0x2A1E14,
           width: 3, alpha: 0.5)
  }
  content(ctx)
  ctx.restoreGState()
}

// MARK: - Artwork

/// Draws the full-bleed 1024x1024 artwork.
func artwork(_ v: Variant) -> CGImage {
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  let mid = CGPoint(x: 512, y: 512)

  let bg = CGGradient(colorsSpace: space, colors: [color(0x2A1E14), color(0x14100C)] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
  let glow = CGGradient(colorsSpace: space, colors: [color(gold, alpha: 0.18), color(gold, alpha: 0)] as CFArray,
                        locations: [0, 1])!
  ctx.drawRadialGradient(glow, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: 420, options: [])

  // Felt disc with rail and gold hairline.
  let feltC = CGPoint(x: 512, y: 500)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, alpha: 0.4))
  fill(ctx, circle(feltC, 300), 0x6B4423)
  ctx.restoreGState()
  stroke(ctx, circle(feltC, 293), 0x6B4423, width: 14)
  ctx.saveGState()
  ctx.addPath(circle(feltC, 286))
  ctx.clip()
  let felt = CGGradient(colorsSpace: space, colors: [color(0x2B6A50), color(0x1F4D3A)] as CFArray, locations: [0, 1])!
  ctx.drawRadialGradient(felt, startCenter: feltC, startRadius: 0, endCenter: feltC, endRadius: 286, options: [])
  ctx.restoreGState()
  if v.detail { stroke(ctx, circle(feltC, 284), gold, width: 4) }

  // Rune ring: 12 arcs of 22 degrees, diamond tick in each gap, glowing.
  ctx.saveGState()
  ctx.setShadow(offset: .zero, blur: 18, color: color(rune, alpha: 0.6))
  if v.detail {
    let step = CGFloat.pi / 6, arc = 22 * CGFloat.pi / 180
    ctx.setLineCap(.butt)
    for i in 0..<12 {
      let midA = CGFloat(i) * step
      let p = CGMutablePath()
      p.addArc(center: feltC, radius: 262, startAngle: midA - arc / 2, endAngle: midA + arc / 2, clockwise: false)
      stroke(ctx, p, rune, width: 10, alpha: 0.85)
      let gapA = midA + step / 2
      let tc = CGPoint(x: feltC.x + 262 * cos(gapA), y: feltC.y + 262 * sin(gapA))
      fill(ctx, diamond(tc, 12, angle: gapA), rune, alpha: 0.9)
    }
  } else {
    stroke(ctx, circle(feltC, 262), rune, width: 16, alpha: 0.85)
  }
  ctx.restoreGState()

  // Back card: heart.
  drawCard(ctx, pivot: CGPoint(x: 470, y: 300), degrees: 14, detail: v.detail) { c in
    fill(c, suit(heartPath(), width: 190, at: CGPoint(x: 0, y: 210)), 0xB3261E)
  }
  // Front card: spade and index.
  drawCard(ctx, pivot: CGPoint(x: 560, y: 300), degrees: -10, detail: v.detail) { c in
    fill(c, suit(spadePath(), width: 170, at: CGPoint(x: 0, y: 200)), ink)
    if v.detail {
      let a = textPath("A", fontSize: 84)
      var t = CGAffineTransform(translationX: -150 + 40, y: 420 - 40 - 84 * 0.72)
      fill(c, a.copy(using: &t)!, ink)
    }
  }

  // Gold coin.
  if v.detail {
    let cc = CGPoint(x: 700, y: 330)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x000000, alpha: 0.45))
    fill(ctx, circle(cc, 70), gold)
    ctx.restoreGState()
    stroke(ctx, circle(cc, 66), 0xA87A26, width: 8)
    for i in 0..<8 {
      let a = CGFloat(i) * .pi / 4 + .pi / 8
      let p = CGPoint(x: cc.x + 66 * cos(a), y: cc.y + 66 * sin(a))
      fill(ctx, CGPath(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8), transform: nil), 0xF3E6C8)
    }
    fill(ctx, diamond(cc, 44), rune)
  }
  return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("failed to write \(url.path)\n".utf8))
    exit(1)
  }
  print("wrote \(url.path)")
}

// MARK: - macOS icon

/// macOS icon master: the artwork clipped to a rounded rectangle (824 pt body on a 1024 canvas, corner
/// radius 185) with a soft drop shadow, on a transparent background.
func macMaster(_ art: CGImage) -> CGImage {
  let rgba = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
  rgba.saveGState()
  rgba.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.35))
  rgba.setFillColor(color(0x14100C))
  rgba.addPath(shape)
  rgba.fillPath()
  rgba.restoreGState()
  rgba.saveGState()
  rgba.addPath(shape)
  rgba.clip()
  rgba.interpolationQuality = .high
  rgba.draw(art, in: CGRect(x: 0, y: 0, width: size, height: size))
  rgba.restoreGState()
  // A hairline highlight along the top edge keeps the shape readable on dark backgrounds.
  rgba.saveGState()
  rgba.addPath(shape)
  rgba.setStrokeColor(color(0xFFFFFF, alpha: 0.12))
  rgba.setLineWidth(2)
  rgba.strokePath()
  rgba.restoreGState()
  return rgba.makeImage()!
}

func scaled(_ image: CGImage, to px: Int) -> CGImage {
  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
  return ctx.makeImage()!
}

func renderMac() {
  let full = macMaster(artwork(Variant(detail: true)))
  let simple = macMaster(artwork(Variant(detail: false)))
  let dir = URL(fileURLWithPath: outDir)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  var images: [[String: String]] = []
  for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
      let px = points * scale
      let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
      let master = points <= 32 ? simple : full
      write(px == 1024 ? master : scaled(master, to: px), to: dir.appendingPathComponent(name))
      images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
  }
  let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
  let data = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  try! data.write(to: dir.appendingPathComponent("Contents.json"))
  let catalog = URL(fileURLWithPath: "\(assetsDir)/Contents.json")
  if !FileManager.default.fileExists(atPath: catalog.path) {
    try! Data("{ \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }\n".utf8).write(to: catalog)
  }
}

renderMac()
