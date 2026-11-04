import CoreGraphics
import SpriteKit
import Testing
import ThemeKit

@testable import TableKit

@Suite struct TableRendererTests {
  private let renderer = TableRenderer(resolver: .codeDrawn)
  private let size = CGSize(width: 400, height: 250)

  private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    let context = ThemeImageIO.makeContext(pixelWidth: image.width, pixelHeight: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    return bytes[y * context.bytesPerRow + x * 4 + 3]
  }

  @Test func imagesHaveRequestedSize() {
    let images = [
      renderer.tableImage(pixelSize: size), renderer.feltImage(pixelSize: size), renderer.railImage(pixelSize: size),
    ]
    for image in images {
      #expect(image.width == 400 && image.height == 250)
    }
    #expect(renderer.dealerButtonImage(pixelDiameter: 64).width == 64)
  }

  @Test func feltIsOvalShaped() {
    let felt = renderer.feltImage(pixelSize: size)
    #expect(alpha(felt, x: 2, y: 2) == 0)
    #expect(alpha(felt, x: 200, y: 125) == 255)
    let rail = renderer.railImage(pixelSize: size)
    #expect(alpha(rail, x: 200, y: 125) == 0)
    #expect(alpha(rail, x: 2, y: 2) == 0)
  }

  @Test func feltDigestIsDeterministic() {
    let a = ImageDigest.fnv1a(renderer.feltImage(pixelSize: size))
    let b = ImageDigest.fnv1a(TableRenderer(resolver: .codeDrawn).feltImage(pixelSize: size))
    #expect(a == b)
  }

  @Test func runesSourceMentionsUniforms() throws {
    let source = try TableShaders.runesSource()
    #expect(!source.isEmpty)
    #expect(source.contains("u_pulse"))
    #expect(source.contains("u_rune_color"))
  }

  @MainActor @Test func shaderHasNamedUniforms() {
    let shader = TableShaders.runes(color: ThemeColor(hex: "#7FE3FF")!, pulse: 0.3)
    let names = Set(shader.uniforms.map(\.name))
    #expect(names.contains(TableShaders.pulseUniform))
    #expect(names.contains(TableShaders.colorUniform))
  }

  @MainActor @Test func reducedMotionRingRunsNoAction() {
    let ring = TableRuneRing(size: CGSize(width: 100, height: 60), resolver: .codeDrawn, reduceMotion: true)
    ring.pulse()
    #expect(!ring.hasActions())
    let moving = TableRuneRing(size: CGSize(width: 100, height: 60), resolver: .codeDrawn, reduceMotion: false)
    moving.pulse()
    #expect(moving.hasActions())
  }
}
