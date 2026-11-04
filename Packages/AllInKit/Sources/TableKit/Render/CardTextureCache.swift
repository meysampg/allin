import PokerCore
import SpriteKit
import ThemeKit

/// Main-actor cache of card textures. Faces are keyed by card index and the deck color mode; backs by reward id.
@MainActor public final class CardTextureCache {
  private var renderer: CardRenderer
  private var faces: [Int: SKTexture] = [:]
  private var backs: [String: SKTexture] = [:]

  public init(renderer: CardRenderer) {
    self.renderer = renderer
  }

  public var fourColor: Bool {
    get { renderer.options.fourColor }
    set {
      guard newValue != renderer.options.fourColor else { return }
      renderer.options.fourColor = newValue
      faces.removeAll()
    }
  }

  public var cachedCount: Int { faces.count + backs.count }

  public func texture(for card: Card) -> SKTexture {
    let key = Int(card.index) + (fourColor ? 64 : 0)
    if let cached = faces[key] { return cached }
    let texture = Self.makeTexture(renderer.face(card))
    faces[key] = texture
    return texture
  }

  public func backTexture(rewardID: String? = nil) -> SKTexture {
    let key = rewardID ?? ""
    if let cached = backs[key] { return cached }
    let texture = Self.makeTexture(renderer.back(rewardID: rewardID))
    backs[key] = texture
    return texture
  }

  /// Renders the 52 faces and the default back.
  public func preloadAll() {
    for card in Card.all { _ = texture(for: card) }
    _ = backTexture()
  }

  public func purge() {
    faces.removeAll()
    backs.removeAll()
  }

  private static func makeTexture(_ image: CGImage) -> SKTexture {
    let texture = SKTexture(cgImage: image)
    texture.filteringMode = .linear
    texture.usesMipmaps = true
    return texture
  }
}
