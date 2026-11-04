import AppKit
import PokerCore
import SwiftUI
import Testing
import ThemeKit

@testable import AllInUI

@Suite struct ThemeTests {
  @Test func goldMatchesPaletteHex() throws {
    let color = try #require(NSColor(Theme.hearthwood.color(.gold)).usingColorSpace(.sRGB))
    #expect(abs(color.redComponent - 0xD9 / 255.0) <= 1 / 255.0)
    #expect(abs(color.greenComponent - 0xA4 / 255.0) <= 1 / 255.0)
    #expect(abs(color.blueComponent - 0x41 / 255.0) <= 1 / 255.0)
  }

  @Test func fourColorChangesClubs() {
    let theme = Theme.hearthwood
    #expect(theme.suitColor(.clubs, fourColor: true) != theme.suitColor(.clubs, fourColor: false))
    #expect(theme.suitColor(.hearts, fourColor: true) == theme.suitColor(.hearts, fourColor: false))
  }

  @Test func fontsResolve() {
    let theme = Theme.hearthwood
    #expect(theme.displayFont(size: 20) == .system(size: 20, weight: .heavy, design: .serif))
    #expect(theme.bodyFont(size: 12, weight: .semibold) == .system(size: 12, weight: .semibold, design: .rounded))
  }
}
