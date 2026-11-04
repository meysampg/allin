import CoreGraphics
import CoreText
import PokerCore

/// Vector suit shapes and glyph outlines. All paths are y-up in roughly the unit box; they are placed with `CardDrawing`.
enum CardSuitPaths {
  static func path(for suit: Suit) -> CGPath {
    switch suit {
    case .clubs: return club
    case .diamonds: return diamond
    case .hearts: return heart
    case .spades: return spade
    }
  }

  static var heart: CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.5, y: 0))
    p.addCurve(to: CGPoint(x: 0, y: 0.68), control1: CGPoint(x: 0.35, y: 0.18), control2: CGPoint(x: 0, y: 0.42))
    p.addCurve(to: CGPoint(x: 0.5, y: 0.78), control1: CGPoint(x: 0, y: 0.92), control2: CGPoint(x: 0.32, y: 1.0))
    p.addCurve(to: CGPoint(x: 1, y: 0.68), control1: CGPoint(x: 0.68, y: 1.0), control2: CGPoint(x: 1, y: 0.92))
    p.addCurve(to: CGPoint(x: 0.5, y: 0), control1: CGPoint(x: 1, y: 0.42), control2: CGPoint(x: 0.65, y: 0.18))
    p.closeSubpath()
    return p
  }

  static var diamond: CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.5, y: 0))
    p.addLine(to: CGPoint(x: 0.84, y: 0.5))
    p.addLine(to: CGPoint(x: 0.5, y: 1))
    p.addLine(to: CGPoint(x: 0.16, y: 0.5))
    p.closeSubpath()
    return p
  }

  static var spade: CGPath {
    let p = CGMutablePath()
    // Inverted heart body, then a stem; both subpaths wind the same way so the union fills.
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

  static var club: CGPath {
    let p = CGMutablePath()
    let r = 0.25
    for c in [CGPoint(x: 0.5, y: 0.75), CGPoint(x: 0.25, y: 0.42), CGPoint(x: 0.75, y: 0.42)] {
      p.move(to: CGPoint(x: c.x + r, y: c.y))
      p.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
      p.closeSubpath()
    }
    p.move(to: CGPoint(x: 0.5, y: 0.5))
    p.addLine(to: CGPoint(x: 0.5 - 0.24, y: 0.3))
    p.addLine(to: CGPoint(x: 0.5 + 0.24, y: 0.3))
    p.closeSubpath()
    // Stem, wound counter-clockwise like the circles.
    p.move(to: CGPoint(x: 0.5, y: 0.45))
    p.addLine(to: CGPoint(x: 0.35, y: 0))
    p.addLine(to: CGPoint(x: 0.65, y: 0))
    p.closeSubpath()
    return p
  }

  /// Outline of `text` set in Georgia Bold (system bold when missing); y-up, baseline at y = 0.
  static func textPath(_ text: String, fontSize: CGFloat = 100) -> CGPath {
    var font = CTFontCreateWithName("Georgia-Bold" as CFString, fontSize, nil)
    if CTFontCopyFamilyName(font) as String != "Georgia" {
      font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? font
    }
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
}
