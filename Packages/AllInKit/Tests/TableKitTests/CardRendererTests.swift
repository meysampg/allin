import CoreGraphics
import Foundation
import PokerCore
import Testing
import ThemeKit

@testable import TableKit

@Suite("CardRenderer")
struct CardRendererTests {
  static let small = CardRenderOptions(pixelSize: CGSize(width: 100, height: 140))

  @Test func facesAndBackHaveRequestedSizeAndAreOpaque() {
    let renderer = CardRenderer(resolver: .codeDrawn, options: Self.small)
    var images = Card.all.map { renderer.face($0) }
    images.append(renderer.back())
    for image in images {
      #expect(image.width == 100 && image.height == 140)
      #expect(ImageDigest.opaqueFraction(image) > 0.5)
    }
  }

  @Test func fullSizeFace() {
    let renderer = CardRenderer(resolver: .codeDrawn)
    let image = renderer.face(try! Card("Qh"))
    #expect(image.width == 250 && image.height == 350)
    #expect(ImageDigest.opaqueFraction(image) > 0.5)
  }

  @Test func renderingIsDeterministicAndFacesAreDistinct() {
    let a = CardRenderer(resolver: .codeDrawn, options: Self.small)
    let b = CardRenderer(resolver: .codeDrawn, options: Self.small)
    var digests = Set<UInt64>()
    for card in Card.all {
      let d = ImageDigest.fnv1a(a.face(card))
      #expect(d == ImageDigest.fnv1a(b.face(card)))
      digests.insert(d)
    }
    #expect(digests.count == 52)
    #expect(ImageDigest.fnv1a(a.back()) == ImageDigest.fnv1a(b.back()))
  }

  @Test func fourColorChangesOnlyClubsAndDiamonds() {
    let two = CardRenderer(resolver: .codeDrawn, options: Self.small)
    var opts = Self.small
    opts.fourColor = true
    let four = CardRenderer(resolver: .codeDrawn, options: opts)
    for card in Card.all {
      let same = ImageDigest.fnv1a(two.face(card)) == ImageDigest.fnv1a(four.face(card))
      switch card.suit {
      case .clubs, .diamonds: #expect(!same)
      case .hearts, .spades: #expect(same)
      }
    }
  }

  @Test func overrideFileIsUsedForTheAceOfSpades() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cardtest-\(UUID().uuidString)")
    let pack = dir.appendingPathComponent("test.allintheme")
    try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let ctx = ThemeImageIO.makeContext(pixelWidth: 500, pixelHeight: 700)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 500, height: 700))
    try ThemeImageIO.writePNG(ctx.makeImage()!, to: pack.appendingPathComponent("as.png"))
    let manifest = """
      {"schemaVersion":1,"id":"test","name":"Test","version":"1","author":"t","palette":{},
       "slots":{"card.face.As":{"file":"as.png"}}}
      """
    try manifest.write(to: pack.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)
    let loaded = try ThemePack.load(from: pack)
    let resolver = ThemeResolver(chain: [loaded])
    let renderer = CardRenderer(resolver: resolver, options: Self.small)
    let image = renderer.face(try! Card("As"))
    #expect(image.width == 100 && image.height == 140)
    let plain = CardRenderer(resolver: .codeDrawn, options: Self.small).face(try! Card("As"))
    #expect(ImageDigest.fnv1a(image) != ImageDigest.fnv1a(plain))
    // Centre pixel is blue.
    let ctx2 = ThemeImageIO.makeContext(pixelWidth: 100, pixelHeight: 140)
    ctx2.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 140))
    let data = ctx2.data!.assumingMemoryBound(to: UInt8.self)
    let offset = (70 * 100 + 50) * 4
    #expect(data[offset] < 10 && data[offset + 2] > 245)
  }

  @Test func themeKeyMatchesRawValues() {
    let key = try! Card("Td").themeKey
    #expect(key.rank == 8 && key.suit == 1)
  }
}
