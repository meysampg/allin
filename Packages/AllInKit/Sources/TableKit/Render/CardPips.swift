import CoreGraphics
import PokerCore

/// Standard pip layouts for ranks 2 through 10. `column` is -1, 0 or 1; `row` runs 0 (top) to 1 (bottom).
enum CardPips {
  struct Pip: Equatable {
    var column: Int
    var row: CGFloat
  }

  static func layout(rank: Rank) -> [Pip] {
    func side(_ rows: [CGFloat]) -> [Pip] {
      rows.flatMap { [Pip(column: -1, row: $0), Pip(column: 1, row: $0)] }
    }
    let mid: (CGFloat) -> Pip = { Pip(column: 0, row: $0) }
    switch rank {
    case .two: return [mid(0), mid(1)]
    case .three: return [mid(0), mid(0.5), mid(1)]
    case .four: return side([0, 1])
    case .five: return side([0, 1]) + [mid(0.5)]
    case .six: return side([0, 0.5, 1])
    case .seven: return side([0, 0.5, 1]) + [mid(0.25)]
    case .eight: return side([0, 0.5, 1]) + [mid(0.25), mid(0.75)]
    case .nine: return side([0, 1.0 / 3, 2.0 / 3, 1]) + [mid(0.5)]
    case .ten: return side([0, 1.0 / 3, 2.0 / 3, 1]) + [mid(1.0 / 6), mid(5.0 / 6)]
    case .ace: return [mid(0.5)]
    case .jack, .queen, .king: return []
    }
  }

  /// Draws the pips of `card` (ranks 2...10 and the ace) in the 250x350 y-down design space.
  static func draw(_ card: Card, color: CGColor, in ctx: CGContext) {
    let suit = CardSuitPaths.path(for: card.suit)
    if card.rank == .ace {
      let rect = CGRect(x: 125 - 40, y: 175 - 40, width: 80, height: 80)
      CardDrawing.fill(CardDrawing.place(suit, in: rect, upright: true), color: color, in: ctx)
      return
    }
    let size: CGFloat = 36
    for pip in layout(rank: card.rank) {
      let cx = 125 + CGFloat(pip.column) * 36
      let cy = 64 + pip.row * 222
      let rect = CGRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
      CardDrawing.fill(CardDrawing.place(suit, in: rect, upright: pip.row <= 0.5), color: color, in: ctx)
    }
  }
}

/// Shared drawing helpers. Card art is drawn in a 250x350 y-down design space; paths are authored y-up.
enum CardDrawing {
  static let designSize = CGSize(width: 250, height: 350)

  /// Fits a y-up path into `rect` (aspect preserved, centered). `upright: false` rotates it 180 degrees.
  static func place(_ path: CGPath, in rect: CGRect, upright: Bool) -> CGPath {
    let box = path.boundingBoxOfPath
    guard box.width > 0, box.height > 0 else { return path }
    let s = min(rect.width / box.width, rect.height / box.height)
    var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
    t = t.scaledBy(x: upright ? s : -s, y: upright ? -s : s)
    t = t.translatedBy(x: -box.midX, y: -box.midY)
    return path.copy(using: &t) ?? path
  }

  /// Scales a y-up text path to `height`, centered on `centerX`, with its top at `top`; shrinks to fit `maxWidth`.
  static func placeText(_ path: CGPath, centerX: CGFloat, top: CGFloat, height: CGFloat, maxWidth: CGFloat) -> CGPath {
    let box = path.boundingBoxOfPath
    guard box.width > 0, box.height > 0 else { return path }
    let s = min(height / box.height, maxWidth / box.width)
    let h = box.height * s
    let rect = CGRect(x: centerX - box.width * s / 2, y: top + (height - h) / 2, width: box.width * s, height: h)
    return place(path, in: rect, upright: true)
  }

  static func fill(_ path: CGPath, color: CGColor, in ctx: CGContext) {
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
  }

  static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  /// Opens a y-down context in the design space for an image of `pixelWidth` x `pixelHeight`.
  static func beginDesignSpace(_ ctx: CGContext, pixelWidth: Int, pixelHeight: Int) {
    ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
    ctx.scaleBy(x: CGFloat(pixelWidth) / designSize.width, y: -CGFloat(pixelHeight) / designSize.height)
  }

  /// HSB to RGB color (components 0...1).
  static func hsb(_ h: Double, _ s: Double, _ b: Double, alpha: Double = 1) -> CGColor {
    let hue = (h - h.rounded(.down)) * 6
    let i = Int(hue)
    let f = hue - Double(i)
    let p = b * (1 - s)
    let q = b * (1 - s * f)
    let t = b * (1 - s * (1 - f))
    let (r, g, bl): (Double, Double, Double)
    switch i % 6 {
    case 0: (r, g, bl) = (b, t, p)
    case 1: (r, g, bl) = (q, b, p)
    case 2: (r, g, bl) = (p, b, t)
    case 3: (r, g, bl) = (p, q, b)
    case 4: (r, g, bl) = (t, p, b)
    default: (r, g, bl) = (b, p, q)
    }
    return CGColor(srgbRed: r, green: g, blue: bl, alpha: alpha)
  }
}
