import Foundation
import PokerCore

/// One street of the betting-rounds timeline.
public struct TimelineStreet: Sendable, Hashable {
  public let name: String
  public let board: [Card]
  /// Labels such as "Bram: check" or "You: bet 12".
  public let actions: [String]

  public init(name: String, board: [Card], actions: [String]) {
    self.name = name
    self.board = board
    self.actions = actions
  }
}

public struct TimelineData: Sendable, Hashable {
  public let streets: [TimelineStreet]
  public let current: Int

  public init(streets: [TimelineStreet], current: Int) {
    self.streets = streets
    self.current = current
  }
}

public struct LadderData: Sendable, Hashable {
  /// Category → tag ("You", "Bram").
  public let highlights: [HandCategory: String]

  public init(highlights: [HandCategory: String]) { self.highlights = highlights }
}

public struct BestFiveData: Sendable, Hashable {
  public let cards: [Card]
  public let best: [Card]
  public let description: String

  public init(cards: [Card], best: [Card], description: String) {
    self.cards = cards
    self.best = best
    self.description = description
  }
}

public struct PotCounterEntry: Sendable, Hashable {
  public let label: String
  public let amount: Int

  public init(label: String, amount: Int) {
    self.label = label
    self.amount = amount
  }
}

public struct PotCounterData: Sendable, Hashable {
  public let entries: [PotCounterEntry]
  public let total: Int
  public let toCall: Int?

  public init(entries: [PotCounterEntry], total: Int, toCall: Int?) {
    self.entries = entries
    self.total = total
    self.toCall = toCall
  }
}

public struct NutsScanData: Sendable, Hashable {
  public let board: [Card]
  public let nuts: String
  public let nutCards: [Card]
  public let flushPossible: Bool
  public let straightPossible: Bool
  public let fullHousePossible: Bool

  public init(
    board: [Card], nuts: String, nutCards: [Card], flushPossible: Bool, straightPossible: Bool,
    fullHousePossible: Bool
  ) {
    self.board = board
    self.nuts = nuts
    self.nutCards = nutCards
    self.flushPossible = flushPossible
    self.straightPossible = straightPossible
    self.fullHousePossible = fullHousePossible
  }
}

public struct WhoCallsMeData: Sendable, Hashable {
  public enum Mode: String, Sendable, Hashable { case callers, bettors }
  public enum Cell: String, Sendable, Hashable { case none, worseCalls, betterCalls, folds }

  public let mode: Mode
  public let villainName: String
  public let heroCards: [Card]
  public let board: [Card]
  /// 13×13 in `HandRange.grid` order.
  public let cells: [[Cell]]
  /// Shares of the villain's live range weight, 0...1 (they sum to 1). In bettors mode `worseCalls` is the
  /// share of bets the hero beats and `betterCalls` the share that beat the hero.
  public let worseCalls: Double
  public let betterCalls: Double
  public let folds: Double
  public let betLabel: String?

  public init(
    mode: Mode, villainName: String, heroCards: [Card], board: [Card], cells: [[Cell]], worseCalls: Double,
    betterCalls: Double, folds: Double, betLabel: String?
  ) {
    self.mode = mode
    self.villainName = villainName
    self.heroCards = heroCards
    self.board = board
    self.cells = cells
    self.worseCalls = worseCalls
    self.betterCalls = betterCalls
    self.folds = folds
    self.betLabel = betLabel
  }
}

public struct PotSlicesData: Sendable, Hashable {
  public let pot: Int
  public let call: Int

  public init(pot: Int, call: Int) {
    self.pot = pot
    self.call = call
  }
}

public struct OutsData: Sendable, Hashable {
  public let hole: [Card]
  public let board: [Card]
  public let outs: [Card]
  public let unseen: Int
  public let exactEquity: Double?

  public init(hole: [Card], board: [Card], outs: [Card], unseen: Int, exactEquity: Double?) {
    self.hole = hole
    self.board = board
    self.outs = outs
    self.unseen = unseen
    self.exactEquity = exactEquity
  }
}

/// The payload of one explainer, field names mirroring the AllInUI models.
public enum ExplainerData: Sendable, Hashable {
  case bettingRoundsTimeline(TimelineData)
  case handRankLadder(LadderData)
  case bestFiveHighlight(BestFiveData)
  case potCounter(PotCounterData)
  case boardNutsScan(NutsScanData)
  case whoCallsMe(WhoCallsMeData)
  case potSlices(PotSlicesData)
  case outsGlow(OutsData)

  public var kind: ExplainerKind {
    switch self {
    case .bettingRoundsTimeline: .bettingRoundsTimeline
    case .handRankLadder: .handRankLadder
    case .bestFiveHighlight: .bestFiveHighlight
    case .potCounter: .potCounter
    case .boardNutsScan: .boardNutsScan
    case .whoCallsMe: .whoCallsMe
    case .potSlices: .potSlices
    case .outsGlow: .outsGlow
    }
  }
}

/// Why an explainer could not be built for an instance.
public enum ExplainerBuildError: Error, Sendable, Equatable, CustomStringConvertible {
  case notApplicable(ExplainerKind, String)

  public var description: String {
    switch self {
    case .notApplicable(let kind, let reason): "\(kind.rawValue) does not apply here: \(reason)"
    }
  }
}
