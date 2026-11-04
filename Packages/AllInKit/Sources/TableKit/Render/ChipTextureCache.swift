import Foundation
import SpriteKit
import ThemeKit

@MainActor public final class ChipTextureCache {
  private let renderer: ChipRenderer
  private let pixelDiameter: Int
  private var textures: [ChipDenomination: SKTexture] = [:]

  public init(renderer: ChipRenderer, pixelDiameter: Int = 64) {
    self.renderer = renderer
    self.pixelDiameter = pixelDiameter
  }

  public func texture(for denomination: ChipDenomination) -> SKTexture {
    if let cached = textures[denomination] { return cached }
    let texture = SKTexture(cgImage: renderer.chipImage(denomination, pixelDiameter: pixelDiameter))
    textures[denomination] = texture
    return texture
  }
}
