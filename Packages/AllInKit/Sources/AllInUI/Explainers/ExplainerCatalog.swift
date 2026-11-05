#if DEBUG
  import PokerCore
  import SwiftUI

  /// Debug-only gallery of every explainer with sample models (not linked from the app).
  public struct ExplainerCatalog: View {
    @Environment(\.theme) private var theme
    @State private var picked: [Card] = []
    @State private var weights: [[Float]] = (0..<13).map { r in (0..<13).map { c in r + c < 5 ? 1 : 0 } }

    public init() {}

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          section("Pot slices") { PotSlicesView(model: .sample) }
          section("Outs glow") { OutsGlowView(model: .sample) }
          section("Betting rounds") { BettingRoundsTimelineView(model: .sample) }
          section("Hand rank ladder") { HandRankLadderView(model: .sample) }
          section("Best five") { BestFiveHighlightView(model: .sample) }
          section("Pot counter") { PotCounterView(model: .sample) }
          section("Board nuts scan") { BoardNutsScanView(model: .sample) }
          section("Who calls me") { WhoCallsMeView(model: .sample) }
          section("Equity bars") {
            EquityBars(model: EquityBarsModel(priceNeeded: 0.2, chance: 0.35, isRefining: true))
          }
          section("Card picker (limit 2)") {
            CardPickerView(selection: $picked, limit: 2, dead: CardSet(parseCards("As")))
          }
          section("Range painter") { RangePainterView(weights: $weights) }
        }
        .padding(20)
      }
      .background(theme.parchment)
      .allInTheme(theme)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(theme.displayFont(size: 15)).foregroundStyle(theme.ink)
        content()
      }
    }
  }
#endif
