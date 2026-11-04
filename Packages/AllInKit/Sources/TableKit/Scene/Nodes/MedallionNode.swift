import AppKit
import CoreGraphics
import PokerCore
import SpriteKit
import ThemeKit

/// A round portrait: ring, dark disc and the character's SF Symbol (or an initial when there is none).
@MainActor final class MedallionNode: SKSpriteNode {
  static let diameter: CGFloat = 54
  private static let pixels = 128

  init(info: TableSeatInfo, resolver: ThemeResolver) {
    let image = Self.image(info: info, resolver: resolver)
    let side = Self.diameter
    super.init(texture: SKTexture(cgImage: image), color: .clear, size: CGSize(width: side, height: side))
    name = "medallion"
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// A slow scale pulse while a bot decides.
  func setBreathing(_ on: Bool) {
    let key = "breathe"
    if on {
      guard action(forKey: key) == nil else { return }
      let pulse = SKAction.sequence([
        SKAction.scale(to: 1.07, duration: 0.7), SKAction.scale(to: 1.0, duration: 0.7),
      ])
      run(SKAction.repeatForever(pulse), withKey: key)
    } else if action(forKey: key) != nil {
      removeAction(forKey: key)
      setScale(1)
    }
  }

  static func image(info: TableSeatInfo, resolver: ThemeResolver) -> CGImage {
    let palette = resolver.palette
    let side = pixels
    let context = ThemeImageIO.makeContext(pixelWidth: side, pixelHeight: side)
    let rect = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
    var ring = palette[.gold]
    var symbol: String?
    var initial = String(info.name.prefix(1)).uppercased()
    var portrait: CGImage?
    let key = info.characterID ?? ""
    if !key.isEmpty {
      switch resolver.resolve(.avatar(key)) {
      case .procedural(_, let params):
        ring = params.color("ring", default: ring)
        symbol = params.string("symbol", default: "")
        initial = params.string("initial", default: initial)
      case .file(let url): portrait = ThemeImageIO.loadImage(at: url)
      case .files(let urls): portrait = urls.first.flatMap { ThemeImageIO.loadImage(at: $0) }
      }
    }
    context.setFillColor(palette[.night].cgColor)
    context.fillEllipse(in: rect)
    if let portrait {
      context.saveGState()
      context.addEllipse(in: rect.insetBy(dx: 6, dy: 6))
      context.clip()
      context.draw(portrait, in: rect.insetBy(dx: 6, dy: 6))
      context.restoreGState()
    } else if let symbol, !symbol.isEmpty, let glyph = symbolImage(symbol, color: palette[.parchment]) {
      let target = rect.insetBy(dx: 28, dy: 28)
      let scale = min(target.width / CGFloat(glyph.width), target.height / CGFloat(glyph.height))
      let drawn = CGSize(width: CGFloat(glyph.width) * scale, height: CGFloat(glyph.height) * scale)
      context.draw(
        glyph,
        in: CGRect(origin: CGPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2), size: drawn))
    } else {
      TextDrawing.drawCentered(
        initial, in: context, center: CGPoint(x: rect.midX, y: rect.midY), fontSize: 58, color: palette[.parchment])
    }
    context.setStrokeColor(ring.cgColor)
    context.setLineWidth(8)
    context.strokeEllipse(in: rect.insetBy(dx: 3, dy: 3))
    context.setStrokeColor(palette[.ink].cgColor)
    context.setLineWidth(2)
    context.strokeEllipse(in: rect)
    return context.makeImage()!
  }

  private static func symbolImage(_ name: String, color: ThemeColor) -> CGImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let tint = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    let configuration = NSImage.SymbolConfiguration(pointSize: 96, weight: .semibold)
      .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
    guard let image = base.withSymbolConfiguration(configuration) else { return nil }
    var proposed = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
  }
}
