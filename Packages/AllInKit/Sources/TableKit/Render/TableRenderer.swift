import CoreGraphics
import CoreText
import Foundation
import PokerCore
import ThemeKit

/// Draws the table (oak rail, cloth felt, candle vignette) and the dealer button in code.
public struct TableRenderer: Sendable {
  /// Normalized, y-down: the felt oval's bounding box inside the table canvas.
  public static let feltRect = CGRect(x: 0.14, y: 0.13, width: 0.72, height: 0.52)
  /// Rail thickness as a share of the canvas width.
  static let railWidth: CGFloat = 0.04

  private let resolver: ThemeResolver

  public init(resolver: ThemeResolver) { self.resolver = resolver }

  /// Oval cloth with noise, transparent outside the oval. The image covers the full canvas.
  public func feltImage(pixelSize: CGSize) -> CGImage {
    let (w, h) = Self.dimensions(pixelSize)
    let context = ThemeImageIO.makeContext(pixelWidth: w, pixelHeight: h)
    let oval = Self.feltOval(width: w, height: h)
    let palette = resolver.palette
    var color = palette[.felt]
    if case .procedural(_, let params) = resolver.resolve(.tableFelt) {
      color = params.color("color", default: color)
    }
    context.saveGState()
    context.addEllipse(in: oval)
    context.clip()
    if case .file(let url) = resolver.resolve(.tableFelt), let image = ThemeImageIO.loadImage(at: url) {
      context.draw(image, in: oval)
    } else {
      context.setFillColor(color.cgColor)
      context.fill(oval)
    }
    context.restoreGState()
    Self.addClothNoise(to: context, width: w, height: h, oval: oval)
    return context.makeImage()!
  }

  /// Carved oak ring around the felt oval, transparent elsewhere.
  public func railImage(pixelSize: CGSize) -> CGImage {
    let (w, h) = Self.dimensions(pixelSize)
    let context = ThemeImageIO.makeContext(pixelWidth: w, pixelHeight: h)
    let inner = Self.feltOval(width: w, height: h)
    let thickness = CGFloat(w) * Self.railWidth
    let outer = inner.insetBy(dx: -thickness, dy: -thickness)
    let base = resolver.palette[.rail]
    let gold = resolver.palette[.gold]

    context.saveGState()
    let ring = CGMutablePath()
    ring.addEllipse(in: outer)
    ring.addEllipse(in: inner)
    context.addPath(ring)
    context.clip(using: .evenOdd)
    if case .file(let url) = resolver.resolve(.tableRail), let image = ThemeImageIO.loadImage(at: url) {
      context.draw(image, in: outer)
    } else {
      Self.drawWoodGrain(in: context, bounds: outer, base: base)
    }
    context.restoreGState()

    // Shading: dark outer edge, light highlight just inside, gold bevel line against the felt.
    context.setLineWidth(max(thickness * 0.10, 1))
    context.setStrokeColor(Self.shade(base, 0.45).cgColor)
    context.strokeEllipse(in: outer.insetBy(dx: thickness * 0.05, dy: thickness * 0.05))
    context.setLineWidth(max(thickness * 0.06, 1))
    context.setStrokeColor(Self.shade(base, 1.35).cgColor)
    context.strokeEllipse(in: outer.insetBy(dx: thickness * 0.16, dy: thickness * 0.16))
    context.setLineWidth(max(thickness * 0.08, 1.5))
    context.setStrokeColor(gold.cgColor)
    context.strokeEllipse(in: inner.insetBy(dx: -thickness * 0.06, dy: -thickness * 0.06))
    context.setLineWidth(max(thickness * 0.05, 1))
    context.setStrokeColor(Self.shade(base, 0.35).cgColor)
    context.strokeEllipse(in: inner.insetBy(dx: -thickness * 0.14, dy: -thickness * 0.14))
    return context.makeImage()!
  }

  /// Night background, rail, felt and a warm candle vignette, full canvas.
  public func tableImage(pixelSize: CGSize) -> CGImage {
    let (w, h) = Self.dimensions(pixelSize)
    let context = ThemeImageIO.makeContext(pixelWidth: w, pixelHeight: h)
    let canvas = CGRect(x: 0, y: 0, width: w, height: h)
    let palette = resolver.palette
    context.setFillColor(palette[.night].cgColor)
    context.fill(canvas)
    context.draw(railImage(pixelSize: pixelSize), in: canvas)
    context.draw(feltImage(pixelSize: pixelSize), in: canvas)

    var warmth = 0.7
    if case .procedural(_, let params) = resolver.resolve(.tableLight) {
      warmth = params.double("warmth", default: 0.7)
    }
    warmth = min(max(warmth, 0), 1)
    let centre = CGPoint(x: canvas.midX, y: canvas.midY + CGFloat(h) * 0.04)
    let reach = hypot(CGFloat(w), CGFloat(h)) * 0.55
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let night = palette[.night]
    let colors =
      [
        CGColor(red: 1.0, green: 0.78 + 0.1 * warmth, blue: 0.45 + 0.2 * (1 - warmth), alpha: 0.22 * warmth + 0.04),
        CGColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 0.0),
        CGColor(red: night.red, green: night.green, blue: night.blue, alpha: 0.55),
      ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
      context.drawRadialGradient(
        gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: reach,
        options: [.drawsAfterEndLocation])
    }
    return context.makeImage()!
  }

  /// Ivory disc with a gold ring and a "D".
  public func dealerButtonImage(pixelDiameter: Int) -> CGImage {
    let d = max(pixelDiameter, 8)
    let context = ThemeImageIO.makeContext(pixelWidth: d, pixelHeight: d)
    let palette = resolver.palette
    let size = CGFloat(d)
    let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.04, dy: size * 0.04)
    context.setFillColor(palette[.ink].cgColor)
    context.fillEllipse(in: rect)
    context.setFillColor(palette[.cardFace].cgColor)
    context.fillEllipse(in: rect.insetBy(dx: size * 0.03, dy: size * 0.03))
    context.setStrokeColor(palette[.gold].cgColor)
    context.setLineWidth(size * 0.05)
    context.strokeEllipse(in: rect.insetBy(dx: size * 0.1, dy: size * 0.1))
    context.setLineWidth(max(size * 0.012, 1))
    context.strokeEllipse(in: rect.insetBy(dx: size * 0.16, dy: size * 0.16))
    TextDrawing.drawCentered(
      "D", in: context, center: CGPoint(x: size / 2, y: size / 2), fontSize: size * 0.46, color: palette[.ink])
    return context.makeImage()!
  }

  // MARK: Helpers

  static func dimensions(_ size: CGSize) -> (Int, Int) {
    (max(Int(size.width.rounded()), 1), max(Int(size.height.rounded()), 1))
  }

  /// The felt oval in context (y-up) pixel coordinates.
  static func feltOval(width: Int, height: Int) -> CGRect {
    let f = feltRect
    let w = CGFloat(width)
    let h = CGFloat(height)
    return CGRect(x: f.minX * w, y: (1 - f.maxY) * h, width: f.width * w, height: f.height * h)
  }

  static func shade(_ color: ThemeColor, _ factor: Double) -> ThemeColor {
    ThemeColor(
      red: min(max(color.red * factor, 0), 1), green: min(max(color.green * factor, 0), 1),
      blue: min(max(color.blue * factor, 0), 1), alpha: color.alpha)
  }

  /// Deterministic per-pixel brightness noise plus a gentle darkening toward the oval's edge.
  private static func addClothNoise(to context: CGContext, width: Int, height: Int, oval: CGRect) {
    guard let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let stride = context.bytesPerRow
    var rng = SeededRNG(seed: 0xFE17)
    let cx = oval.midX
    let cy = oval.midY
    let rx = max(oval.width / 2, 1)
    let ry = max(oval.height / 2, 1)
    for y in 0..<height {
      let row = bytes + y * stride
      // The bitmap's first row is the top of the image; the oval is symmetric so only the mapping matters.
      let dy = (CGFloat(height - 1 - y) + 0.5 - cy) / ry
      for x in 0..<width {
        let px = row + x * 4
        let alpha = Int(px[3])
        let noise = Int(rng.next() % 17) - 8
        if alpha == 0 { continue }
        let dx = (CGFloat(x) + 0.5 - cx) / rx
        let edge = min(max(dx * dx + dy * dy, 0), 1)
        let darken = Double(edge * edge) * 0.28
        // Weave: faint criss-cross threads.
        let weave = ((x / 3 + y / 3) % 2 == 0) ? 3 : -3
        for c in 0..<3 {
          let value = Double(px[c]) * (1 - darken) + Double((noise + weave) * alpha) / 255
          px[c] = UInt8(min(max(value, 0), Double(alpha)))
        }
      }
    }
  }

  /// Seeded sine stripes in shades of the rail color, with slow warps like plank grain.
  private static func drawWoodGrain(in context: CGContext, bounds: CGRect, base: ThemeColor) {
    var rng = SeededRNG(seed: 0x0A4B)
    var phase: [Double] = []
    for _ in 0..<4 { phase.append(Double(rng.next() % 6283) / 1000) }
    context.setFillColor(base.cgColor)
    context.fill(bounds)
    let step: CGFloat = max(bounds.height / 220, 1)
    var y = bounds.minY
    var line = 0
    while y < bounds.maxY {
      let t = Double(y - bounds.minY) / Double(bounds.height) * 90
      let tone =
        0.5 * sin(t * 1.3 + phase[0]) + 0.3 * sin(t * 3.1 + phase[1]) + 0.2 * sin(t * 7.7 + phase[2])
        + 0.1 * sin(Double(line) * 0.9 + phase[3])
      let color = shade(base, 1 + tone * 0.22)
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(step * 1.2)
      // Slightly wavy horizontal stroke across the full width.
      context.beginPath()
      context.move(to: CGPoint(x: bounds.minX, y: y))
      let segments = 12
      for i in 1...segments {
        let x = bounds.minX + bounds.width * CGFloat(i) / CGFloat(segments)
        let wobble = CGFloat(sin(Double(i) * 0.9 + t * 0.3 + phase[0])) * step * 0.8
        context.addLine(to: CGPoint(x: x, y: y + wobble))
      }
      context.strokePath()
      y += step
      line += 1
    }
  }
}

/// CoreText helpers shared by the table and chip renderers.
enum TextDrawing {
  static func drawCentered(
    _ text: String, in context: CGContext, center: CGPoint, fontSize: CGFloat, color: ThemeColor
  ) {
    let font = CTFontCreateWithName("Georgia-Bold" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.saveGState()
    context.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
