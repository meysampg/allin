import CoreGraphics
import Foundation
import SpriteKit
import ThemeKit

/// A ring sprite that draws glyph marks with the runes shader.
@MainActor public final class TableRuneRing: SKSpriteNode {
  private let reduceMotion: Bool
  private let runeShader: SKShader
  private static let restingPulse: Float = 0.6

  public init(size: CGSize, resolver: ThemeResolver, reduceMotion: Bool) {
    self.reduceMotion = reduceMotion
    var color = resolver.palette[.rune]
    if case .procedural(_, let params) = resolver.resolve(.tableRunes) {
      color = params.color("color", default: color)
    }
    let shader = TableShaders.runes(color: color, pulse: reduceMotion ? Self.restingPulse : 0)
    runeShader = shader
    let pixels = CGSize(width: max(size.width, 8), height: max(size.height, 8))
    let texture = SKTexture(cgImage: Self.ringImage(pixelSize: pixels))
    super.init(texture: texture, color: .clear, size: size)
    self.shader = shader
    name = "runeRing"
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// A brief flare for street changes; a static glow under reduce motion.
  public func pulse() {
    if reduceMotion {
      setPulse(Self.restingPulse)
      return
    }
    let duration: CGFloat = 0.6
    let action = SKAction.customAction(withDuration: duration) { node, elapsed in
      let t = Float(elapsed / duration)
      let value: Float = t < 0.5 ? t * 2 : 1 - (t - 0.5) * 2 * (1 - Self.restingPulse)
      MainActor.assumeIsolated { (node as? TableRuneRing)?.setPulse(value) }
    }
    removeAction(forKey: "pulse")
    run(action, withKey: "pulse")
  }

  private func setPulse(_ value: Float) {
    runeShader.uniformNamed(TableShaders.pulseUniform)?.floatValue = value
  }

  /// A faint white ellipse ring; the shader supplies the marks and color.
  static func ringImage(pixelSize: CGSize) -> CGImage {
    let w = Int(min(pixelSize.width, 2048))
    let h = Int(min(pixelSize.height, 2048))
    let context = ThemeImageIO.makeContext(pixelWidth: w, pixelHeight: h)
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let lineWidth = CGFloat(min(w, h)) * 0.012 + 1
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
    context.setLineWidth(lineWidth)
    context.strokeEllipse(in: rect.insetBy(dx: CGFloat(w) * 0.07, dy: CGFloat(h) * 0.07))
    context.strokeEllipse(in: rect.insetBy(dx: CGFloat(w) * 0.03, dy: CGFloat(h) * 0.03))
    return context.makeImage()!
  }
}
