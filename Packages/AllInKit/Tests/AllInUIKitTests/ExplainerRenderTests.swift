import PokerCore
import SwiftUI
import Testing

@testable import AllInUI

@MainActor
@Suite struct ExplainerRenderTests {
  private func renders<V: View>(_ view: V) -> Bool {
    let renderer = ImageRenderer(content: view.allInTheme(.hearthwood).environment(\.explainerAnimates, false))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return false }
    return image.width > 0 && image.height > 0
  }

  @Test func explainers() {
    #expect(renders(PotSlicesView(model: .sample)))
    #expect(renders(OutsGlowView(model: .sample)))
    #expect(renders(BettingRoundsTimelineView(model: .sample)))
    #expect(renders(HandRankLadderView(model: .sample)))
    #expect(renders(BestFiveHighlightView(model: .sample)))
    #expect(renders(PotCounterView(model: .sample)))
    #expect(renders(BoardNutsScanView(model: .sample)))
    #expect(renders(WhoCallsMeView(model: .sample)))
  }

  @Test func inputs() {
    var picked: [Card] = parseCards("AhKd")
    var weights = [[Float]](repeating: [Float](repeating: 0, count: 13), count: 13)
    let pickedBinding = Binding(get: { picked }, set: { picked = $0 })
    let weightsBinding = Binding(get: { weights }, set: { weights = $0 })
    #expect(renders(EquityBars(model: .sample)))
    #expect(renders(EquityBars(model: EquityBarsModel(priceNeeded: nil, chance: nil, isRefining: true))))
    #expect(renders(CardPickerView(selection: pickedBinding, limit: 2, dead: CardSet(parseCards("As")))))
    #expect(renders(RangePainterView(weights: weightsBinding)))
  }

  #if DEBUG
    @Test func catalog() {
      #expect(renders(ExplainerCatalog().frame(width: 700, height: 900)))
    }
  #endif
}
