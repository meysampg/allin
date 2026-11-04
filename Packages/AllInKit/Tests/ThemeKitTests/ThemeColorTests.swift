import Foundation
import Testing

@testable import ThemeKit

@Suite struct ThemeColorTests {
  @Test func parsesThreeHexForms() throws {
    let a = try #require(ThemeColor(hex: "#FF8000"))
    #expect(a.red == 1)
    #expect(abs(a.green - 128.0 / 255) < 1e-9)
    #expect(a.alpha == 1)
    let short = try #require(ThemeColor(hex: "#F00"))
    #expect(short.hex == "#FF0000")
    let withAlpha = try #require(ThemeColor(hex: "#11223380"))
    #expect(abs(withAlpha.alpha - 128.0 / 255) < 1e-9)
    #expect(withAlpha.hex == "#11223380")
  }

  @Test func rejectsInvalidHex() {
    for text in ["", "#", "#12", "#12345", "#GGGGGG", "#1234567", "red"] {
      #expect(ThemeColor(hex: text) == nil, "\(text)")
    }
  }

  @Test func blackWhiteContrastIs21() {
    let black = ThemeColor(red: 0, green: 0, blue: 0)
    let white = ThemeColor(red: 1, green: 1, blue: 1)
    #expect(abs(ThemeColor.contrastRatio(black, white) - 21) < 0.01)
    #expect(abs(ThemeColor.contrastRatio(white, black) - 21) < 0.01)
  }

  @Test func hearthwoodSuitsReadOnCardFace() {
    let face = ThemePalette.hearthwood[.cardFace]
    for key in [PaletteKey.suitRed, .suitBlack, .suitBlue, .suitGreen] {
      #expect(ThemeColor.contrastRatio(ThemePalette.hearthwood[key], face) >= 4.5, "\(key)")
    }
  }

  @Test func codableRoundTripUsesHexString() throws {
    let color = try #require(ThemeColor(hex: "#D9A441"))
    let data = try JSONEncoder().encode([color])
    #expect(String(decoding: data, as: UTF8.self) == "[\"#D9A441\"]")
    #expect(try JSONDecoder().decode([ThemeColor].self, from: data) == [color])
  }

  @Test func paletteMergeKeepsExplicitKeys() throws {
    let red = try #require(ThemeColor(hex: "#FF0000"))
    let blue = try #require(ThemeColor(hex: "#0000FF"))
    let base = ThemePalette(colors: [.felt: red, .rail: red])
    let top = ThemePalette(colors: [.felt: blue])
    let merged = top.merged(over: base)
    #expect(merged[.felt] == blue)
    #expect(merged[.rail] == red)
    #expect(merged[.gold] == ThemePalette.hearthwood[.gold])
  }
}
