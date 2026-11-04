import CoreGraphics
import PokerCore
import SpriteKit
import Testing
import ThemeKit

@testable import TableKit

@Suite("CardTextureCache")
@MainActor
struct CardTextureCacheTests {
  func makeCache() -> CardTextureCache {
    CardTextureCache(
      renderer: CardRenderer(
        resolver: .codeDrawn, options: CardRenderOptions(pixelSize: CGSize(width: 100, height: 140))))
  }

  @Test func repeatCallsReturnTheSameTexture() {
    let cache = makeCache()
    let a = cache.texture(for: try! Card("As"))
    #expect(cache.cachedCount == 1)
    #expect(cache.texture(for: try! Card("As")) === a)
    _ = cache.texture(for: try! Card("Kd"))
    #expect(cache.cachedCount == 2)
    let back = cache.backTexture()
    #expect(cache.backTexture() === back)
    #expect(cache.cachedCount == 3)
  }

  @Test func settingFourColorPurgesFaces() {
    let cache = makeCache()
    _ = cache.texture(for: try! Card("2c"))
    _ = cache.backTexture()
    cache.fourColor = true
    #expect(cache.fourColor)
    #expect(cache.cachedCount == 1)
  }

  @Test func preloadAllGivesFiftyThree() {
    let cache = makeCache()
    cache.preloadAll()
    #expect(cache.cachedCount == 53)
    cache.purge()
    #expect(cache.cachedCount == 0)
  }
}
