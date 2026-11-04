import PokerCore
import SpriteKit

/// Five community-card slots in a row, hidden until dealt.
@MainActor final class BoardNode: SKNode {
  static let cardSize = CGSize(width: 56, height: 78)
  static let spacing: CGFloat = 66

  let slots: [SKSpriteNode]

  override init() {
    slots = (0..<5).map { index in
      let sprite = SKSpriteNode(color: .clear, size: BoardNode.cardSize)
      sprite.position = BoardNode.restPosition(index)
      sprite.isHidden = true
      sprite.zPosition = CGFloat(index)
      return sprite
    }
    super.init()
    for slot in slots { addChild(slot) }
    zPosition = 10
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  static func restPosition(_ index: Int) -> CGPoint {
    CGPoint(x: (CGFloat(index) - 2) * spacing, y: 0)
  }
}
