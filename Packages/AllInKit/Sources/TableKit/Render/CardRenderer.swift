import CoreGraphics
import Foundation
import PokerCore
import ThemeKit

extension Card {
  /// The ThemeKit key for this card (raw values match PokerCore).
  public var themeKey: CardKey { CardKey(rank: rank.rawValue, suit: suit.rawValue)! }
}

/// Draws card faces and backs with Core Graphics. No SpriteKit: the result is a plain `CGImage`.
public struct CardRenderer: Sendable {
  public static let aspect: CGFloat = 5.0 / 7.0

  public let resolver: ThemeResolver
  public var options: CardRenderOptions

  public init(resolver: ThemeResolver, options: CardRenderOptions = CardRenderOptions()) {
    self.resolver = resolver
    self.options = options
  }

  public func face(_ card: Card) -> CGImage {
    let (width, height) = pixelDimensions
    let ctx = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    let key = card.themeKey

    var frame = "gilded"
    switch resolver.resolve(.cardFaceOverride(key)) {
    case .file(let url):
      if let image = ThemeImageIO.loadImage(at: url) { return scaled(image, width: width, height: height) }
    case .files(let urls):
      if let url = urls.first, let image = ThemeImageIO.loadImage(at: url) {
        return scaled(image, width: width, height: height)
      }
    case .procedural(_, let params):
      frame = params.string("frame", default: "gilded")
    }

    var courtImage: CGImage?
    if card.rank.rawValue >= Rank.jack.rawValue, card.rank.rawValue <= Rank.king.rawValue {
      switch resolver.resolve(.cardCourt(key)) {
      case .file(let url): courtImage = ThemeImageIO.loadImage(at: url)
      case .files(let urls): courtImage = urls.first.flatMap { ThemeImageIO.loadImage(at: $0) }
      case .procedural: break
      }
    }

    let palette = resolver.palette
    let gold = palette[.gold].cgColor
    let ink = palette[.ink].cgColor
    let color = suitColor(card.suit, palette: palette)

    CardDrawing.beginDesignSpace(ctx, pixelWidth: width, pixelHeight: height)
    let outer = CGRect(origin: .zero, size: CardDrawing.designSize)
    let shape = CardDrawing.roundedRect(outer.insetBy(dx: 1, dy: 1), radius: 16)
    ctx.addPath(shape)
    ctx.setFillColor(palette[.cardFace].cgColor)
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.setStrokeColor(gold)
    ctx.setLineWidth(frame == "plain" ? 3 : 5)
    ctx.addPath(CardDrawing.roundedRect(outer.insetBy(dx: 3, dy: 3), radius: 14))
    ctx.strokePath()
    if frame != "plain" {
      ctx.setLineWidth(1)
      ctx.addPath(CardDrawing.roundedRect(outer.insetBy(dx: 9, dy: 9), radius: 9))
      ctx.strokePath()
    }
    ctx.restoreGState()

    drawIndex(card, color: color, in: ctx)
    if card.rank.rawValue >= Rank.jack.rawValue, card.rank.rawValue <= Rank.king.rawValue {
      CardCourtArt.draw(card, suitColor: color, gold: gold, ink: ink, centerImage: courtImage, in: ctx)
    } else {
      CardPips.draw(card, color: color, in: ctx)
    }
    return ctx.makeImage()!
  }

  public func back(rewardID: String? = nil) -> CGImage {
    let (width, height) = pixelDimensions
    let slot: AssetSlot = rewardID.map { .cardBackReward($0) } ?? .cardBack
    var hue = 0.08
    switch resolver.resolve(slot) {
    case .file(let url):
      if let image = ThemeImageIO.loadImage(at: url) { return scaled(image, width: width, height: height) }
    case .files(let urls):
      if let url = urls.first, let image = ThemeImageIO.loadImage(at: url) {
        return scaled(image, width: width, height: height)
      }
    case .procedural(_, let params):
      hue = params.double("hue", default: 0.08)
    }
    let ctx = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    CardDrawing.beginDesignSpace(ctx, pixelWidth: width, pixelHeight: height)
    CardBackArt.draw(hue: hue, cardFace: resolver.palette[.cardFace].cgColor, in: ctx)
    return ctx.makeImage()!
  }

  // MARK: - Private

  private var pixelDimensions: (Int, Int) {
    (max(1, Int(options.pixelSize.width.rounded())), max(1, Int(options.pixelSize.height.rounded())))
  }

  private func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage {
    let ctx = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
  }

  private func suitColor(_ suit: Suit, palette: ThemePalette) -> CGColor {
    switch suit {
    case .hearts: return palette[.suitRed].cgColor
    case .spades: return palette[.suitBlack].cgColor
    case .diamonds: return (options.fourColor ? palette[.suitBlue] : palette[.suitRed]).cgColor
    case .clubs: return (options.fourColor ? palette[.suitGreen] : palette[.suitBlack]).cgColor
    }
  }

  /// Corner index: rank over a small suit at top-left, repeated rotated 180 degrees at bottom-right.
  /// The block is 66 design units tall, which is 18.9% of the card height.
  private func drawIndex(_ card: Card, color: CGColor, in ctx: CGContext) {
    let text = card.rank == .ten ? "10" : String(card.rank.symbol)
    let rank = CardDrawing.placeText(
      CardSuitPaths.textPath(text), centerX: 31, top: 14, height: 34, maxWidth: 44)
    let suit = CardDrawing.place(
      CardSuitPaths.path(for: card.suit), in: CGRect(x: 18, y: 54, width: 26, height: 26), upright: true)
    for turned in [false, true] {
      ctx.saveGState()
      if turned {
        ctx.translateBy(x: CardDrawing.designSize.width, y: CardDrawing.designSize.height)
        ctx.rotate(by: .pi)
      }
      CardDrawing.fill(rank, color: color, in: ctx)
      CardDrawing.fill(suit, color: color, in: ctx)
      ctx.restoreGState()
    }
  }
}
