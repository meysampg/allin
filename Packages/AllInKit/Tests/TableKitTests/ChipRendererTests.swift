import Testing
import ThemeKit

@testable import TableKit

@Suite struct ChipRendererTests {
  @Test func chipsAreDistinctAndFilled() {
    let renderer = ChipRenderer(resolver: .codeDrawn)
    var digests = Set<UInt64>()
    for denomination in ChipDenomination.allCases {
      let image = renderer.chipImage(denomination, pixelDiameter: 96)
      #expect(image.width == 96 && image.height == 96)
      #expect(ImageDigest.opaqueFraction(image) > 0.4)
      digests.insert(ImageDigest.fnv1a(image))
    }
    #expect(digests.count == 8)
  }

  @Test func chipsAreDeterministic() {
    let renderer = ChipRenderer(resolver: .codeDrawn)
    let a = renderer.chipImage(.hundred, pixelDiameter: 64)
    let b = renderer.chipImage(.hundred, pixelDiameter: 64)
    #expect(ImageDigest.fnv1a(a) == ImageDigest.fnv1a(b))
  }

  @MainActor @Test func textureCacheReusesTextures() {
    let cache = ChipTextureCache(renderer: ChipRenderer(resolver: .codeDrawn), pixelDiameter: 32)
    #expect(cache.texture(for: .five) === cache.texture(for: .five))
  }
}
