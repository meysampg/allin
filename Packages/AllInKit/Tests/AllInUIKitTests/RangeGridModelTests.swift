import PokerCore
import PokerEquity
import SwiftUI
import Testing

@testable import AllInUI

@Suite struct RangeGridModelTests {
  @Test func labels() {
    #expect(RangeGridModel.label(row: 0, column: 0) == "AA")
    #expect(RangeGridModel.label(row: 0, column: 1) == "AKs")
    #expect(RangeGridModel.label(row: 1, column: 0) == "AKo")
    #expect(RangeGridModel.label(row: 12, column: 12) == "22")
  }

  @Test func fullRangeSummary() {
    let model = RangeGridModel(range: .full)
    #expect(model.liveCombos == 1326)
    #expect(model.percentOfLive == 1)
    #expect(model.summary == "≈ 1326 combos · 100% of hands")
  }

  @Test func deadCardsReduceLive() throws {
    let dead = CardSet([try Card("As")])
    let model = RangeGridModel(range: HandRange.full.removing(dead), dead: dead)
    #expect(model.liveCombos == 1275)
    #expect(abs(model.percentOfLive - 1) < 1e-6)
  }

  @MainActor @Test func renderSmoke() {
    let view = RangeGridView(range: .full, cellSize: 17).allInTheme(.hearthwood)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = renderer.cgImage
    #expect((image?.width ?? 0) > 0)
  }
}
