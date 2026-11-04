import PokerAI
import PokerCore
import PokerEquity

public struct HandAnalysisInput: Sendable {
  /// A complete HOST log (it needs `.deckSetup` and every hole card).
  public var log: EventLog
  public var heroSeat: Int
  /// The strategy of every opponent seat.
  public var opponents: [Int: any StrategyProvider]
  /// The hero's continuation policy in rollouts (`BaselineStrategy()`).
  public var heroContinuation: any StrategyProvider
  /// `BotCharacter.name` and `.style` by seat.
  public var seatNames: [Int: String]
  public var seatStyles: [Int: String]
  public var budget: EVBudget
  public var trackerOptions: RangeTrackerOptions

  public init(
    log: EventLog, heroSeat: Int, opponents: [Int: any StrategyProvider],
    heroContinuation: any StrategyProvider, seatNames: [Int: String], seatStyles: [Int: String],
    budget: EVBudget = .standard, trackerOptions: RangeTrackerOptions = .standard
  ) {
    self.log = log
    self.heroSeat = heroSeat
    self.opponents = opponents
    self.heroContinuation = heroContinuation
    self.seatNames = seatNames
    self.seatStyles = seatStyles
    self.budget = budget
    self.trackerOptions = trackerOptions
  }
}

public enum HandAnalysisError: Error, Sendable, Equatable {
  case incompleteHand
  case heroNotInHand
}

public enum HandAnalyzer {
  /// DecisionPoints → RangeTracker (observer = hero; villains' points observed in order, each after the hero
  /// decisions that precede it) → at each hero point an `EVSpot` + `EVRequest` (seed = `StableSeed.mix(handSeed,
  /// actionSeq)`) → `DecisionGrader` → narration. Luck comes from `LuckCalculator`. Never call on the main actor.
  public static func analyze(_ input: HandAnalysisInput) async throws -> HandAnalysis {
    let log = input.log
    let hero = input.heroSeat
    var start: HandStart?
    var deckSeed: UInt64?
    var heroCards: [Card] = []
    var result: HandResult?
    for logged in log.events {
      switch logged.event {
      case .handStarted(let s): start = start ?? s
      case .deckSetup(let seed, _): deckSeed = deckSeed ?? seed
      case .holeCardsDealt(let seat, let cards) where seat == hero: heroCards = cards
      case .handEnded(let r): result = r
      default: break
      }
    }
    guard let start else { throw DecisionPointError.notHostLog }
    guard let result else { throw HandAnalysisError.incompleteHand }
    guard start.seats.contains(where: { $0.seat == hero }), heroCards.count == 2 else {
      throw HandAnalysisError.heroNotInHand
    }
    let handSeed = deckSeed ?? fnv(start.deckCommitment)
    let points = try DecisionPoints.extract(from: log)
    var tracker = RangeTracker(
      seats: start.seats.map(\.seat).filter { $0 != hero }, observer: hero, observerCards: heroCards,
      strategies: input.opponents, options: input.trackerOptions)

    var decisions: [ReviewedDecision] = []
    var counts = GradeCounts()
    var weightedQuality = 0.0
    var weight = 0.0
    var evLoss = 0.0
    for (i, point) in points.enumerated() {
      if point.context.seat == hero {
        let reviewed = try await review(
          point, index: decisions.count, priorActions: points[..<i].map(\.action), start: start,
          tracker: tracker, handSeed: handSeed, input: input)
        decisions.append(reviewed)
        counts.add(reviewed.graded.grade)
        weightedQuality += reviewed.graded.weight * reviewed.graded.quality
        weight += reviewed.graded.weight
        evLoss += reviewed.graded.evLossBB
      } else {
        await tracker.observe(point.context, action: point.action)
      }
    }
    let luck = try LuckCalculator.luck(in: log, seat: hero)
    return HandAnalysis(
      handID: log.handID, heroSeat: hero, bigBlind: start.config.bigBlind, netChips: result.netChips(of: hero) ?? 0,
      potTotal: result.contributions.reduce(0) { $0 + $1.amount }, decisions: decisions, counts: counts, luck: luck,
      weightedQuality: weightedQuality, weight: weight,
      decisionScore: weight > 0 ? 100 * weightedQuality / weight : nil, evLossBB: evLoss, budget: input.budget)
  }

  // MARK: One hero decision

  private static func review(
    _ point: DecisionPoint, index: Int, priorActions: [Action], start: HandStart, tracker: RangeTracker,
    handSeed: UInt64, input: HandAnalysisInput
  ) async throws -> ReviewedDecision {
    let context = point.context
    let hero = input.heroSeat
    let liveOpponents = context.seats.filter { $0.status != .folded && $0.seat != hero }.map(\.seat)
    var ranges: [Int: HandRange] = [:]
    var strategies: [Int: any StrategyProvider] = [:]
    for seat in liveOpponents {
      ranges[seat] = tracker.range(of: seat) ?? .full
      if let strategy = input.opponents[seat] { strategies[seat] = strategy }
    }
    let seed = StableSeed.mix(handSeed, UInt64(point.actionSeq))
    let request = EVRequest(
      spot: EVSpot(start: start, priorActions: priorActions, context: context), opponentRanges: ranges,
      opponents: strategies, hero: input.heroContinuation, chosen: point.action, budget: input.budget, seed: seed)
    let evs = try await ActionEVEstimator.estimate(request)
    let chosen = DecisionGrader.canonical(point.action, legal: context.legal)
    let graded = DecisionGrader.grade(evs, chosen: chosen, potBefore: context.pot, bigBlind: start.config.bigBlind)
    let kind = DecisionClassifier.kind(context: context, chosen: graded.chosen.action, best: graded.best.action)

    let focus = focusSeat(context: context, liveOpponents: liveOpponents)
    var equity: Double?
    if let focus {
      let range = ranges[focus] ?? .full
      if context.board.count == 5 {
        equity = EquityCalculator.exact(hero: context.holeCards, vs: range, board: context.board).equity
      } else {
        var rng = SeededRNG(seed: StableSeed.mix(seed, 0xE0))
        let estimate = EquityCalculator.monteCarlo(
          hero: context.holeCards, vs: [range], board: context.board, samples: 2_000, using: &rng)
        equity = estimate.samples > 0 ? estimate.equity : nil
      }
    }
    let toCall = context.legal.toCall
    let potOdds = toCall > 0 ? Double(toCall) / Double(context.pot + toCall) : nil
    let name = focus.flatMap { input.seatNames[$0] }
    let style = focus.flatMap { input.seatStyles[$0] }
    let tag = ReviewNarrator.tag(for: graded.chosen.action, context: context, heroCards: context.holeCards)
    let draft = ReviewedDecisionDraft(
      graded: graded, kind: kind, focusName: name, focusStyle: style, equityVsFocus: equity, potOddsNeeded: potOdds)
    return ReviewedDecision(
      index: index, requestSeq: point.requestSeq, actionSeq: point.actionSeq, street: context.street,
      board: context.board, heroCards: context.holeCards, potBefore: context.pot, toCall: toCall, graded: graded,
      kind: kind, focusSeat: focus, focusName: name, focusStyle: style,
      focusRangeGrid: focus.flatMap { tracker.range(of: $0)?.grid }, equityVsFocus: equity,
      potOddsNeeded: potOdds, tag: tag,
      timelineText: ReviewNarrator.timelineText(tag: tag, graded: graded),
      title: ReviewNarrator.title(street: context.street, graded: graded, context: context),
      body: ReviewNarrator.body(decision: draft))
  }

  /// The last live opponent who bet or raised in the hand before the decision, else the live opponent with the
  /// most chips in the pot, else the first live opponent.
  static func focusSeat(context: DecisionContext, liveOpponents: [Int]) -> Int? {
    guard !liveOpponents.isEmpty else { return nil }
    let flags = DecisionClassifier.aggressiveFlags(context.history, bigBlind: context.config.bigBlind)
    for (entry, flag) in zip(context.history, flags).reversed() where flag && liveOpponents.contains(entry.seat) {
      return entry.seat
    }
    var best: (seat: Int, chips: Int)?
    for seat in liveOpponents {
      let chips = context.view(of: seat)?.totalContribution ?? 0
      if best == nil || chips > best!.chips { best = (seat, chips) }
    }
    return best?.seat ?? liveOpponents.first
  }

  /// FNV-1a over the UTF-8 bytes.
  private static func fnv(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
  }
}
