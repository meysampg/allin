import CoreGraphics
import PokerCore

/// Court card (J, Q, K) art: a gilded inner frame with a vector crest, the letter and the suit.
enum CardCourtArt {
  static let frameRect = CGRect(x: 68, y: 48, width: 114, height: 254)

  static func draw(
    _ card: Card, suitColor: CGColor, gold: CGColor, ink: CGColor, centerImage: CGImage?, in ctx: CGContext
  ) {
    let frame = frameRect
    ctx.setFillColor(gold.copy(alpha: 0.14) ?? gold)
    ctx.addPath(CardDrawing.roundedRect(frame, radius: 6))
    ctx.fillPath()
    ctx.setStrokeColor(gold)
    ctx.setLineWidth(3)
    ctx.addPath(CardDrawing.roundedRect(frame, radius: 6))
    ctx.strokePath()
    ctx.setLineWidth(1)
    ctx.addPath(CardDrawing.roundedRect(frame.insetBy(dx: 5, dy: 5), radius: 3))
    ctx.strokePath()

    if let image = centerImage {
      let inner = frame.insetBy(dx: 8, dy: 8)
      ctx.saveGState()
      ctx.addPath(CardDrawing.roundedRect(inner, radius: 3))
      ctx.clip()
      // The context is y-down here, so flip locally to draw the image upright.
      ctx.translateBy(x: inner.minX, y: inner.maxY)
      ctx.scaleBy(x: 1, y: -1)
      let s = max(inner.width / CGFloat(image.width), inner.height / CGFloat(image.height))
      let w = CGFloat(image.width) * s
      let h = CGFloat(image.height) * s
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x: (inner.width - w) / 2, y: (inner.height - h) / 2, width: w, height: h))
      ctx.restoreGState()
      return
    }

    let crestBox = CGRect(x: frame.midX - 40, y: frame.minY + 22, width: 80, height: 70)
    let crest: CGPath
    switch card.rank {
    case .jack: crest = circlet
    case .queen: crest = crown
    default: crest = helm
    }
    CardDrawing.fill(CardDrawing.place(crest, in: crestBox, upright: true), color: gold, in: ctx)
    // Dark detail strokes give the crest some depth.
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(1.5)
    ctx.addPath(CardDrawing.place(crest, in: crestBox, upright: true))
    ctx.strokePath()

    let letter = CardSuitPaths.textPath(String(card.rank.symbol))
    CardDrawing.fill(
      CardDrawing.placeText(letter, centerX: frame.midX, top: frame.minY + 108, height: 70, maxWidth: 70),
      color: suitColor, in: ctx)
    let suit = CardSuitPaths.path(for: card.suit)
    CardDrawing.fill(
      CardDrawing.place(
        suit, in: CGRect(x: frame.midX - 20, y: frame.minY + 190, width: 40, height: 40), upright: true),
      color: suitColor, in: ctx)
  }

  /// Circlet: a band with three jewel points (y-up, unit-ish box).
  static var circlet: CGPath {
    let p = CGMutablePath()
    p.addRect(CGRect(x: 0, y: 0, width: 1, height: 0.22))
    for x in [0.14, 0.5, 0.86] {
      p.move(to: CGPoint(x: x - 0.1, y: 0.22))
      p.addLine(to: CGPoint(x: x, y: 0.62))
      p.addLine(to: CGPoint(x: x + 0.1, y: 0.22))
      p.closeSubpath()
    }
    return p
  }

  /// Crown: five points with ball tips over a band.
  static var crown: CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addLine(to: CGPoint(x: 1, y: 0))
    p.addLine(to: CGPoint(x: 1, y: 0.3))
    p.addLine(to: CGPoint(x: 0.9, y: 0.78))
    p.addLine(to: CGPoint(x: 0.7, y: 0.45))
    p.addLine(to: CGPoint(x: 0.5, y: 0.9))
    p.addLine(to: CGPoint(x: 0.3, y: 0.45))
    p.addLine(to: CGPoint(x: 0.1, y: 0.78))
    p.addLine(to: CGPoint(x: 0, y: 0.3))
    p.closeSubpath()
    for x in [0.1, 0.5, 0.9] {
      let y = x == 0.5 ? 0.97 : 0.85
      p.move(to: CGPoint(x: x + 0.07, y: y))
      p.addArc(center: CGPoint(x: x, y: y), radius: 0.07, startAngle: 0, endAngle: .pi * 2, clockwise: false)
      p.closeSubpath()
    }
    return p
  }

  /// Helm: a dome over a visored face guard with a crest ridge.
  static var helm: CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0.1, y: 0))
    p.addLine(to: CGPoint(x: 0.1, y: 0.42))
    p.addArc(
      center: CGPoint(x: 0.5, y: 0.42), radius: 0.4, startAngle: .pi, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: 0.9, y: 0))
    p.addLine(to: CGPoint(x: 0.62, y: 0))
    p.addLine(to: CGPoint(x: 0.62, y: 0.24))
    p.addLine(to: CGPoint(x: 0.38, y: 0.24))
    p.addLine(to: CGPoint(x: 0.38, y: 0))
    p.closeSubpath()
    // Plume.
    p.move(to: CGPoint(x: 0.44, y: 0.82))
    p.addQuadCurve(to: CGPoint(x: 0.9, y: 1.0), control: CGPoint(x: 0.5, y: 1.15))
    p.addQuadCurve(to: CGPoint(x: 0.56, y: 0.82), control: CGPoint(x: 0.7, y: 0.9))
    p.closeSubpath()
    return p
  }
}
