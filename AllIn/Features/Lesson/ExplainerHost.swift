import AllInUI
import Curriculum
import PokerCore
import SwiftUI

/// Draws one `ExplainerData` with its AllInUI view and the optional authored caption.
struct ExplainerHost: View {
  @Environment(\.theme) private var theme
  let data: ExplainerData
  let caption: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      explainer
      if let caption, !caption.isEmpty {
        Text(caption)
          .font(theme.bodyFont(size: 13, weight: .medium))
          .italic()
          .foregroundStyle(theme.mute)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("explain.explainer.\(data.kind.rawValue).caption")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("explain.explainer.\(data.kind.rawValue)")
  }

  @ViewBuilder
  private var explainer: some View {
    switch data {
    case .bettingRoundsTimeline(let d): BettingRoundsTimelineView(model: Self.model(for: d))
    case .handRankLadder(let d): HandRankLadderView(model: Self.model(for: d))
    case .bestFiveHighlight(let d): BestFiveHighlightView(model: Self.model(for: d))
    case .potCounter(let d): PotCounterView(model: Self.model(for: d))
    case .boardNutsScan(let d): BoardNutsScanView(model: Self.model(for: d))
    case .whoCallsMe(let d): WhoCallsMeView(model: Self.model(for: d))
    case .potSlices(let d): PotSlicesView(model: Self.model(for: d))
    case .outsGlow(let d): OutsGlowView(model: Self.model(for: d))
    }
  }
}

// MARK: - Data to view-model mapping

extension ExplainerHost {
  static func model(for d: TimelineData) -> TimelineModel {
    TimelineModel(
      streets: d.streets.map { .init(name: $0.name, board: $0.board, actions: $0.actions) }, current: d.current)
  }

  static func model(for d: LadderData) -> HandLadderModel { HandLadderModel(highlights: d.highlights) }

  static func model(for d: BestFiveData) -> BestFiveModel {
    BestFiveModel(cards: d.cards, best: d.best, description: d.description)
  }

  static func model(for d: PotCounterData) -> PotCounterModel {
    PotCounterModel(
      entries: d.entries.map { .init(label: $0.label, amount: $0.amount) }, total: d.total, toCall: d.toCall)
  }

  static func model(for d: NutsScanData) -> NutsScanModel {
    NutsScanModel(
      board: d.board, nuts: d.nuts, nutCards: d.nutCards, flushPossible: d.flushPossible,
      straightPossible: d.straightPossible, fullHousePossible: d.fullHousePossible)
  }

  static func model(for d: WhoCallsMeData) -> WhoCallsMeModel {
    WhoCallsMeModel(
      mode: WhoCallsMode(rawValue: d.mode.rawValue) ?? .callers, villainName: d.villainName, heroCards: d.heroCards,
      board: d.board,
      cells: d.cells.map { row in row.map { WhoCallsMeModel.Cell(rawValue: $0.rawValue) ?? .none } },
      worseCalls: d.worseCalls, betterCalls: d.betterCalls, folds: d.folds, betLabel: d.betLabel)
  }

  static func model(for d: PotSlicesData) -> PotSlicesModel { PotSlicesModel(pot: d.pot, call: d.call) }

  static func model(for d: OutsData) -> OutsGlowModel {
    OutsGlowModel(hole: d.hole, board: d.board, outs: d.outs, unseen: d.unseen, exactEquity: d.exactEquity)
  }
}
