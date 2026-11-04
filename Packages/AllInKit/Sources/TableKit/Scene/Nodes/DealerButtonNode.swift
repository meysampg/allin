import SpriteKit
import ThemeKit

/// The dealer button; sits next to the button seat.
@MainActor final class DealerButtonNode: SKSpriteNode {
  static let diameter: CGFloat = 28

  init(renderer: TableRenderer) {
    let texture = SKTexture(cgImage: renderer.dealerButtonImage(pixelDiameter: 64))
    super.init(texture: texture, color: .clear, size: CGSize(width: Self.diameter, height: Self.diameter))
    name = "dealerButton"
    zPosition = 15
    isHidden = true
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
