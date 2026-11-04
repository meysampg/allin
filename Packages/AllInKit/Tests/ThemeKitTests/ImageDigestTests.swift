import CoreGraphics
import Foundation
import Testing

@testable import ThemeKit

@Suite struct ImageDigestTests {
  private func drawing(extraPixel: Bool = false) -> CGImage {
    let context = ThemeImageIO.makeContext(pixelWidth: 16, pixelHeight: 16)
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    if extraPixel {
      context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
      context.fill(CGRect(x: 15, y: 15, width: 1, height: 1))
    }
    return context.makeImage()!
  }

  @Test func digestIsStableAndSensitive() {
    #expect(ImageDigest.fnv1a(drawing()) == ImageDigest.fnv1a(drawing()))
    #expect(ImageDigest.fnv1a(drawing()) != ImageDigest.fnv1a(drawing(extraPixel: true)))
  }

  @Test func opaqueFractionBounds() {
    let empty = ThemeImageIO.makeContext(pixelWidth: 10, pixelHeight: 10).makeImage()!
    #expect(ImageDigest.opaqueFraction(empty) == 0)
    #expect(ImageDigest.opaqueFraction(PackFixture.image(width: 10, height: 10)) == 1)
    #expect(abs(ImageDigest.opaqueFraction(drawing()) - 0.25) < 1e-9)
  }

  @Test func pngRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let image = drawing(extraPixel: true)
    try ThemeImageIO.writePNG(image, to: url)
    let loaded = try #require(ThemeImageIO.loadImage(at: url))
    #expect(ImageDigest.fnv1a(loaded) == ImageDigest.fnv1a(image))
    #expect(ThemeImageIO.loadImage(at: url.appending(path: "nope")) == nil)
  }
}
