import CoreGraphics
import Foundation
import PokerCore
import SpriteKit
import ThemeKit

/// The animated main-menu backdrop: a dim candle-lit table with cards and coins drifting at several depths.
@MainActor public final class MenuBackgroundScene: SKScene {
  public static let cardCount = 10
  public static let chipCount = 14

  public private(set) var driftingNodes: [SKSpriteNode] = []

  private let resolver: ThemeResolver
  private let reduceMotion: Bool
  private let seed: UInt64

  public init(size: CGSize, resolver: ThemeResolver, reduceMotion: Bool, seed: UInt64 = 7) {
    self.resolver = resolver
    self.reduceMotion = reduceMotion
    self.seed = seed
    super.init(size: size)
    scaleMode = .aspectFill
    anchorPoint = .zero
    backgroundColor = SKColor(cgColor: resolver.palette[.night].cgColor) ?? .black
    buildBackdrop()
    buildDrifters()
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func buildBackdrop() {
    let pixels = CGSize(width: max(size.width, 64), height: max(size.height, 64))
    let tableImage = TableRenderer(resolver: resolver).tableImage(pixelSize: pixels)
    let table = SKSpriteNode(texture: SKTexture(cgImage: tableImage))
    table.size = size
    table.position = CGPoint(x: size.width / 2, y: size.height / 2)
    table.alpha = 0.35
    table.zPosition = -20
    table.name = "menu.table"
    addChild(table)

    let vignette = SKSpriteNode(texture: SKTexture(cgImage: Self.vignetteImage(resolver: resolver)))
    vignette.size = size
    vignette.position = table.position
    vignette.zPosition = 20
    vignette.name = "menu.vignette"
    addChild(vignette)
  }

  private func buildDrifters() {
    var rng = SeededRNG(seed: seed)
    let cardOptions = CardRenderOptions(pixelSize: CardRenderOptions.tablePixelSize)
    let cards = CardTextureCache(renderer: CardRenderer(resolver: resolver, options: cardOptions))
    let chips = ChipTextureCache(renderer: ChipRenderer(resolver: resolver), pixelDiameter: 64)
    let deck = Card.all.shuffled(using: &rng)
    let total = Self.cardCount + Self.chipCount
    for index in 0..<total {
      let isCard = index < Self.cardCount
      let node: SKSpriteNode
      if isCard {
        let card = deck[index]
        let texture = Bool.random(using: &rng) ? cards.texture(for: card) : cards.backTexture()
        node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: 70, height: 98)
        node.name = "menu.card"
      } else {
        let denomination = ChipDenomination.allCases.randomElement(using: &rng) ?? .one
        node = SKSpriteNode(texture: chips.texture(for: denomination))
        node.size = CGSize(width: 40, height: 40)
        node.name = "menu.chip"
      }
      let depth = Double.random(in: 0.3...1.0, using: &rng)  // 1 = near
      node.position = CGPoint(
        x: Double.random(in: 0...Double(size.width), using: &rng),
        y: Double.random(in: 0...Double(size.height), using: &rng))
      node.setScale(CGFloat(0.5 + depth * 0.9))
      node.zRotation = CGFloat(Double.random(in: -Double.pi...Double.pi, using: &rng))
      node.alpha = CGFloat(0.35 + depth * 0.5)
      node.zPosition = CGFloat(depth * 10) - 10
      let distance = Double.random(in: 20...60, using: &rng) * (0.5 + depth)
      let angle = Double.random(in: 0..<(2 * Double.pi), using: &rng)
      let duration = Double.random(in: 8...16, using: &rng) / (0.5 + depth * 0.5)
      let spin = Double.random(in: -0.25...0.25, using: &rng)
      addChild(node)
      driftingNodes.append(node)
      if !reduceMotion {
        node.run(Self.driftAction(dx: cos(angle) * distance, dy: sin(angle) * distance, spin: spin, duration: duration))
      }
    }
  }

  private static func driftAction(dx: Double, dy: Double, spin: Double, duration: Double) -> SKAction {
    let out = SKAction.group([
      SKAction.moveBy(x: CGFloat(dx), y: CGFloat(dy), duration: duration),
      SKAction.rotate(byAngle: CGFloat(spin), duration: duration),
    ])
    out.timingMode = .easeInEaseOut
    let back = out.reversed()
    back.timingMode = .easeInEaseOut
    return SKAction.repeatForever(SKAction.sequence([out, back]))
  }

  /// A warm radial glow in the middle fading to dark edges.
  private static func vignetteImage(resolver: ThemeResolver) -> CGImage {
    let width = 256
    let height = 160
    let space = CGColorSpaceCreateDeviceRGB()
    let night = resolver.palette[.night]
    let gold = resolver.palette[.gold]
    let colors = [
      CGColor(red: gold.red, green: gold.green * 0.8, blue: gold.blue * 0.5, alpha: 0.10),
      CGColor(red: night.red, green: night.green, blue: night.blue, alpha: 0.0),
      CGColor(red: night.red, green: night.green, blue: night.blue, alpha: 0.75),
    ]
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1])!
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.scaleBy(x: 1, y: CGFloat(height) / CGFloat(width))
    context.drawRadialGradient(
      gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: CGFloat(width) * 0.62,
      options: [.drawsAfterEndLocation])
    return context.makeImage()!
  }
}
