import CoreGraphics

/// The rune-knot card back: a hue-shifted field, a diamond lattice, an interlaced knot and a gold border.
enum CardBackArt {
  static func draw(hue: Double, cardFace: CGColor, in ctx: CGContext) {
    let outer = CGRect(origin: .zero, size: CardDrawing.designSize)
    let radius: CGFloat = 16
    ctx.addPath(CardDrawing.roundedRect(outer, radius: radius))
    ctx.clip()
    ctx.setFillColor(cardFace)
    ctx.fill(outer)

    let field = outer.insetBy(dx: 12, dy: 12)
    let base = CardDrawing.hsb(hue, 0.65, 0.26)
    let mid = CardDrawing.hsb(hue, 0.6, 0.38)
    let accent = CardDrawing.hsb(hue + 0.02, 0.62, 0.88)
    ctx.addPath(CardDrawing.roundedRect(field, radius: 8))
    ctx.setFillColor(base)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(CardDrawing.roundedRect(field, radius: 8))
    ctx.clip()
    // Diamond lattice.
    ctx.setStrokeColor(mid)
    ctx.setLineWidth(2)
    let step: CGFloat = 28
    var offset: CGFloat = -field.height
    while offset < field.width + field.height {
      ctx.move(to: CGPoint(x: field.minX + offset, y: field.minY))
      ctx.addLine(to: CGPoint(x: field.minX + offset + field.height, y: field.maxY))
      ctx.move(to: CGPoint(x: field.minX + offset, y: field.maxY))
      ctx.addLine(to: CGPoint(x: field.minX + offset + field.height, y: field.minY))
      offset += step
    }
    ctx.strokePath()
    // Lattice nodes.
    ctx.setFillColor(accent.copy(alpha: 0.55) ?? accent)
    var y = field.minY
    while y <= field.maxY {
      var x = field.minX
      while x <= field.maxX {
        let cx = x + (Int((y - field.minY) / step) % 2 == 0 ? 0 : step / 2)
        ctx.fillEllipse(in: CGRect(x: cx - 2, y: y - 2, width: 4, height: 4))
        x += step
      }
      y += step
    }
    ctx.restoreGState()

    drawKnot(center: CGPoint(x: outer.midX, y: outer.midY), base: base, accent: accent, in: ctx)

    // Borders: gold line around the field and a fine line near the edge.
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(3)
    ctx.addPath(CardDrawing.roundedRect(field, radius: 8))
    ctx.strokePath()
    ctx.setLineWidth(1)
    ctx.addPath(CardDrawing.roundedRect(field.insetBy(dx: 7, dy: 7), radius: 5))
    ctx.strokePath()
  }

  /// Three interlaced loops around a diamond: each loop is a dark under-stroke plus a gold stroke, with every
  /// second crossing re-drawn on top to read as over/under.
  private static func drawKnot(center: CGPoint, base: CGColor, accent: CGColor, in ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    let angles: [CGFloat] = [0, .pi / 3, 2 * .pi / 3]
    let rx: CGFloat = 62
    let ry: CGFloat = 26
    func loop(_ angle: CGFloat) {
      ctx.saveGState()
      ctx.rotate(by: angle)
      ctx.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
      ctx.restoreGState()
    }
    for angle in angles {
      ctx.setStrokeColor(base)
      ctx.setLineWidth(9)
      loop(angle)
      ctx.strokePath()
      ctx.setStrokeColor(accent)
      ctx.setLineWidth(4)
      loop(angle)
      ctx.strokePath()
    }
    // Over/under: re-stroke a short arc of each loop over the next one.
    for angle in angles {
      ctx.saveGState()
      ctx.rotate(by: angle)
      let arc = CGMutablePath()
      arc.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
      ctx.addRect(CGRect(x: rx * 0.35, y: -ry - 4, width: rx, height: ry * 2 + 8))
      ctx.clip()
      ctx.setStrokeColor(base)
      ctx.setLineWidth(9)
      ctx.addPath(arc)
      ctx.strokePath()
      ctx.setStrokeColor(accent)
      ctx.setLineWidth(4)
      ctx.addPath(arc)
      ctx.strokePath()
      ctx.restoreGState()
    }
    // Center diamond.
    let d = CGMutablePath()
    d.move(to: CGPoint(x: 0, y: -16))
    d.addLine(to: CGPoint(x: 11, y: 0))
    d.addLine(to: CGPoint(x: 0, y: 16))
    d.addLine(to: CGPoint(x: -11, y: 0))
    d.closeSubpath()
    ctx.addPath(d)
    ctx.setFillColor(base)
    ctx.fillPath()
    ctx.addPath(d)
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    ctx.restoreGState()
  }
}
