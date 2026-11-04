import SpriteKit
import ThemeKit

/// The chips in the middle plus the "POT 75" caption.
@MainActor final class PotNode: SKNode {
  let chips = ChipStackNode(labelPrefix: nil)
  private let caption = SKLabelNode()

  override init() {
    super.init()
    chips.position = CGPoint(x: 0, y: 4)
    addChild(chips)
    caption.fontName = "Georgia-Bold"
    caption.fontSize = 15
    caption.fontColor = SKColor(white: 1, alpha: 0.95)
    caption.verticalAlignmentMode = .top
    caption.position = CGPoint(x: 0, y: -16)
    caption.isHidden = true
    addChild(caption)
    zPosition = 12
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  func set(settled: Int, total: Int, textures: ChipTextureCache) {
    chips.setAmount(settled, textures: textures)
    caption.text = "POT \(total)"
    caption.isHidden = total <= 0
  }
}
