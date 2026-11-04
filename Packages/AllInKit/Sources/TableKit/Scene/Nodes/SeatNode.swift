import CoreGraphics
import PokerCore
import SpriteKit
import ThemeKit

/// One seat: medallion, name and stack box, style hint, two cards and the bet stack.
@MainActor final class SeatNode: SKNode {
  static let boxSize = CGSize(width: 138, height: 24)

  let seatIndex: Int
  let isHero: Bool
  let medallion: MedallionNode
  let cardSprites: [SKSpriteNode]
  let betStack = ChipStackNode(labelPrefix: "bet")
  /// Where the bet stack rests, relative to the seat.
  let betOffset: CGPoint

  private let box: SKSpriteNode
  private let boxLabel = SKLabelNode()
  private let hintLabel = SKLabelNode()
  private let gold: SKColor
  private let cardSize: CGSize

  init(info: TableSeatInfo, betOffset: CGPoint, resolver: ThemeResolver) {
    seatIndex = info.seat
    isHero = info.isHero
    self.betOffset = betOffset
    medallion = MedallionNode(info: info, resolver: resolver)
    box = SKSpriteNode(texture: Self.boxTexture(resolver: resolver), size: Self.boxSize)
    let gold = resolver.palette[.gold]
    self.gold = SKColor(srgbRed: gold.red, green: gold.green, blue: gold.blue, alpha: 1)
    let cardSize = info.isHero ? CGSize(width: 50, height: 70) : CGSize(width: 38, height: 53)
    self.cardSize = cardSize
    cardSprites = (0..<2).map { _ in SKSpriteNode(color: .clear, size: cardSize) }
    super.init()
    name = "seat.\(info.seat)"

    for (index, sprite) in cardSprites.enumerated() {
      let sign: CGFloat = index == 0 ? -1 : 1
      sprite.position = restPosition(index)
      sprite.zRotation = -sign * 0.08
      sprite.zPosition = CGFloat(index)
      sprite.isHidden = true
      addChild(sprite)
    }
    medallion.zPosition = 4
    addChild(medallion)

    box.position = CGPoint(x: 0, y: -44)
    box.zPosition = 5
    addChild(box)
    boxLabel.fontName = "Georgia-Bold"
    boxLabel.fontSize = 13
    boxLabel.fontColor = .white
    boxLabel.verticalAlignmentMode = .center
    boxLabel.position = CGPoint(x: 0, y: 0)
    box.addChild(boxLabel)
    hintLabel.fontName = "Georgia-Italic"
    hintLabel.fontSize = 11
    hintLabel.fontColor = SKColor(white: 1, alpha: 0.82)
    hintLabel.verticalAlignmentMode = .top
    hintLabel.position = CGPoint(x: 0, y: -58)
    hintLabel.zPosition = 5
    addChild(hintLabel)

    betStack.position = self.betOffset
    addChild(betStack)
    boxLabel.text = info.name
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  func restPosition(_ index: Int) -> CGPoint {
    let sign: CGFloat = index == 0 ? -1 : 1
    let spread = cardSize.width * 0.55
    return CGPoint(x: sign * spread, y: isHero ? 52 : 40)
  }

  /// Brings every label, card and tint to the snapshot. Safe to call at any time.
  func apply(
    _ seat: SeatSnapshot, hud: TableHUD, mode: TableSceneMode, breathing: Bool, textures: SeatTextures,
    lifted: Set<Card>, dimmed: Set<Card>
  ) {
    let miniature = mode == .miniature
    alpha = seat.status == .folded ? 0.5 : (seat.status == .empty ? 0.35 : 1)

    box.isHidden = miniature
    let stackText = seat.status == .empty ? "-" : "\(seat.stack)"
    if isHero {
      let position = seat.positionName.map { " · \($0)" } ?? ""
      boxLabel.text = "\(seat.info.name)\(position) · \(stackText)"
    } else {
      boxLabel.text = "\(seat.info.name) · \(stackText)"
    }
    box.color = gold
    box.colorBlendFactor = (seat.isToAct || seat.isWinner) ? 0.55 : 0

    var hint: String?
    switch hud {
    case .off: hint = seat.lastAction
    case .basic: hint = seat.lastAction ?? seat.info.styleHint
    case .full:
      hint = [seat.info.styleHint, seat.lastAction].compactMap { $0 }.joined(separator: " · ")
    }
    hintLabel.text = hint
    hintLabel.isHidden = miniature || (hint ?? "").isEmpty

    medallion.setBreathing(breathing && seat.isToAct && !isHero)

    betStack.removeAllActions()
    betStack.position = self.betOffset
    betStack.alpha = 1
    betStack.setAmount(seat.committed, textures: textures.chips)
    betStack.isHidden = seat.committed <= 0

    let faces = seat.holeCards
    for (index, sprite) in cardSprites.enumerated() {
      sprite.removeAllActions()
      sprite.isHidden = !seat.hasCards
      sprite.xScale = 1
      sprite.alpha = 1
      sprite.position = restPosition(index)
      let card = (faces?.count == 2) ? faces?[index] : nil
      sprite.texture = card.map { textures.cards.texture(for: $0) } ?? textures.cards.backTexture()
      var lift: CGFloat = 0
      sprite.colorBlendFactor = 0
      if let card {
        if lifted.contains(card) {
          lift = 8
          sprite.color = gold
          sprite.colorBlendFactor = 0.18
        } else if dimmed.contains(card) {
          sprite.color = .black
          sprite.colorBlendFactor = 0.45
        }
      }
      sprite.position.y += lift
    }
  }

  private static func boxTexture(resolver: ThemeResolver) -> SKTexture {
    let w = 276
    let h = 48
    let context = ThemeImageIO.makeContext(pixelWidth: w, pixelHeight: h)
    let rect = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 2, dy: 2)
    let path = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
    let palette = resolver.palette
    var night = palette[.night]
    night.alpha = 0.82
    context.addPath(path)
    context.setFillColor(night.cgColor)
    context.fillPath()
    context.addPath(path)
    context.setStrokeColor(palette[.gold].cgColor)
    context.setLineWidth(2)
    context.strokePath()
    return SKTexture(cgImage: context.makeImage()!)
  }
}

/// The texture caches seat nodes draw from.
@MainActor struct SeatTextures {
  let cards: CardTextureCache
  let chips: ChipTextureCache
}
