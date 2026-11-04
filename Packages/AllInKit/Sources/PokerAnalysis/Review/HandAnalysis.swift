import PokerCore

public struct ReviewedDecision: Codable, Sendable, Hashable, Identifiable {
  public var id: Int { index }
  /// Among the hero's decisions.
  public let index: Int
  public let requestSeq: Int
  public let actionSeq: Int
  public let street: Street
  public let board: [Card]
  public let heroCards: [Card]
  public let potBefore: Int
  public let toCall: Int
  public let graded: GradedDecision
  public let kind: DecisionKind
  public let focusSeat: Int?
  public let focusName: String?
  public let focusStyle: String?
  /// `HandRange.grid` (13x13) of the focus villain's tracked range.
  public let focusRangeGrid: [[Float]]?
  /// Hero vs the focus range (Monte Carlo, seeded; exact on the river).
  public let equityVsFocus: Double?
  /// `toCall / (pot + toCall)` when `toCall > 0`.
  public let potOddsNeeded: Double?
  public let tag: String
  public let timelineText: String
  public let title: String
  public let body: String

  public init(
    index: Int, requestSeq: Int, actionSeq: Int, street: Street, board: [Card], heroCards: [Card], potBefore: Int,
    toCall: Int, graded: GradedDecision, kind: DecisionKind, focusSeat: Int?, focusName: String?,
    focusStyle: String?, focusRangeGrid: [[Float]]?, equityVsFocus: Double?, potOddsNeeded: Double?, tag: String,
    timelineText: String, title: String, body: String
  ) {
    self.index = index
    self.requestSeq = requestSeq
    self.actionSeq = actionSeq
    self.street = street
    self.board = board
    self.heroCards = heroCards
    self.potBefore = potBefore
    self.toCall = toCall
    self.graded = graded
    self.kind = kind
    self.focusSeat = focusSeat
    self.focusName = focusName
    self.focusStyle = focusStyle
    self.focusRangeGrid = focusRangeGrid
    self.equityVsFocus = equityVsFocus
    self.potOddsNeeded = potOddsNeeded
    self.tag = tag
    self.timelineText = timelineText
    self.title = title
    self.body = body
  }
}

public struct HandAnalysis: Codable, Sendable, Hashable {
  public let handID: HandID
  public let heroSeat: Int
  public let bigBlind: Int
  public let netChips: Int
  /// Σ contributions.
  public let potTotal: Int
  public let decisions: [ReviewedDecision]
  public let counts: GradeCounts
  public let luck: LuckResult
  /// Σ w·q.
  public let weightedQuality: Double
  /// Σ w.
  public let weight: Double
  /// `100 · Σwq / Σw`; nil without decisions.
  public let decisionScore: Double?
  public let evLossBB: Double
  public let budget: EVBudget

  public init(
    handID: HandID, heroSeat: Int, bigBlind: Int, netChips: Int, potTotal: Int, decisions: [ReviewedDecision],
    counts: GradeCounts, luck: LuckResult, weightedQuality: Double, weight: Double, decisionScore: Double?,
    evLossBB: Double, budget: EVBudget
  ) {
    self.handID = handID
    self.heroSeat = heroSeat
    self.bigBlind = bigBlind
    self.netChips = netChips
    self.potTotal = potTotal
    self.decisions = decisions
    self.counts = counts
    self.luck = luck
    self.weightedQuality = weightedQuality
    self.weight = weight
    self.decisionScore = decisionScore
    self.evLossBB = evLossBB
    self.budget = budget
  }

  /// "You won 29 · decisions: 3 good, 1 leak".
  public var headline: String { ReviewNarrator.headline(self) }

  /// Only for an all-in hand: "Chips +420 (luck −60)".
  public var luckText: String? { ReviewNarrator.luckText(self) }

  /// The first leak, else the first small miss, else 0; nil without decisions.
  public var initialSelection: Int? {
    if let leak = decisions.first(where: { $0.graded.grade == .leak }) { return leak.index }
    if let miss = decisions.first(where: { $0.graded.grade == .smallMiss }) { return miss.index }
    return decisions.isEmpty ? nil : 0
  }
}
