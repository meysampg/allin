import PokerCore
import SpriteKit
import ThemeKit

/// A few columns of chips with an optional amount label. Rebuilt only when the amount changes.
@MainActor final class ChipStackNode: SKNode {
  static let chipSize: CGFloat = 24
  static let maxPerColumn = 6
  static let maxColumns = 3

  private(set) var amount = 0
  private let labelPrefix: String?
  private let label = SKLabelNode()

  init(labelPrefix: String?) {
    self.labelPrefix = labelPrefix
    super.init()
    label.fontName = "Menlo-Bold"
    label.fontSize = 13
    label.fontColor = .white
    label.verticalAlignmentMode = .top
    label.position = CGPoint(x: 0, y: -ChipStackNode.chipSize * 0.6)
    label.isHidden = true
    addChild(label)
    zPosition = 20
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setAmount(_ newAmount: Int, textures: ChipTextureCache, force: Bool = false) {
    guard newAmount != amount || force else { return }
    amount = newAmount
    for child in children where child !== label { child.removeFromParent() }
    guard newAmount > 0 else {
      label.isHidden = true
      return
    }
    let columns = ChipStackBuilder.columns(
      for: newAmount, maxPerColumn: Self.maxPerColumn, maxColumns: Self.maxColumns)
    let spacing = Self.chipSize * 0.95
    let origin = -CGFloat(columns.count - 1) * spacing / 2
    for (column, chips) in columns.enumerated() {
      for (level, denomination) in chips.enumerated() {
        let chip = SKSpriteNode(texture: textures.texture(for: denomination))
        chip.size = CGSize(width: Self.chipSize, height: Self.chipSize)
        chip.position = CGPoint(x: origin + CGFloat(column) * spacing, y: CGFloat(level) * 3.5)
        chip.zPosition = CGFloat(level)
        addChild(chip)
      }
    }
    if let labelPrefix {
      label.text = "\(labelPrefix) \(newAmount)"
      label.isHidden = false
    }
  }
}
