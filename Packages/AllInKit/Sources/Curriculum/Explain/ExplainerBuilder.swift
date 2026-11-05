import Foundation
import PokerAI
import PokerCore
import PokerEquity

/// Builds the data behind each explainer from a generated spot.
///
/// Binds: `handRankLadder.highlight` hero|both (both); `bestFiveHighlight.hand` hero|villain|winner (hero);
/// `whoCallsMe.mode` callers|bettors (callers when the hero is not facing a bet), `size` "bet:F" (0.5),
/// `range` "villainRange", `hand` "hero".
public enum ExplainerBuilder {
  public static func build(
    _ ref: ExplainerRef, instance: SpotInstance, template: SpotTemplate, characters: CharacterCatalog,
    villainRanges: [Int: HandRange]
  ) async throws -> ExplainerData {
    switch ref.explainer {
    case .bettingRoundsTimeline: return .bettingRoundsTimeline(timeline(instance))
    case .handRankLadder: return .handRankLadder(try ladder(ref, instance))
    case .bestFiveHighlight: return .bestFiveHighlight(try bestFive(ref, instance))
    case .potCounter: return .potCounter(potCounter(instance))
    case .boardNutsScan: return .boardNutsScan(try nutsScan(instance))
    case .whoCallsMe:
      return .whoCallsMe(try whoCallsMe(ref, instance, characters: characters, villainRanges: villainRanges))
    case .potSlices: return .potSlices(try potSlices(ref, instance))
    case .outsGlow: return .outsGlow(try outsGlow(instance, villainRanges: villainRanges))
    }
  }

  // MARK: - Shared helpers

  static func name(_ seat: Int, _ instance: SpotInstance) -> String { instance.seatNames[seat] ?? "Seat \(seat + 1)" }

  static func heroCards(_ instance: SpotInstance) -> [Card] { instance.holeCards[instance.heroSeat] ?? [] }

  static func streetName(_ street: Street) -> String {
    switch street {
    case .preflop: "Preflop"
    case .flop: "Flop"
    case .turn: "Turn"
    case .river: "River"
    }
  }

  static func actionText(_ entry: ActionEntry) -> String {
    switch entry.action {
    case .fold: "fold"
    case .check: "check"
    case .call: "call"
    case .bet(let to): "bet \(to)"
    case .raise(let to): "raise to \(to)"
    case .allIn: "all-in \(entry.committedAfter)"
    }
  }

  /// The hand's category with 2 to 7 cards (a pair or high card before the flop).
  static func category(hole: [Card], board: [Card]) -> HandCategory {
    if hole.count + board.count >= 5 { return HandEvaluator.evaluate(hole: hole, board: board).category }
    if hole.count == 2, hole[0].rank == hole[1].rank { return .pair }
    return .highCard
  }

  /// The villain whose hand the explainers talk about: the first involved villain.
  static func mainVillain(_ instance: SpotInstance) -> Int? { instance.villainSeats.first }

  static func requireBoard(_ kind: ExplainerKind, _ instance: SpotInstance) throws {
    guard instance.board.count >= 3 else { throw ExplainerBuildError.notApplicable(kind, "needs a flop") }
  }

  /// "bet:F" → F.
  static func betFraction(_ text: String?) -> Double {
    guard let text, text.hasPrefix("bet:"), let f = Double(text.dropFirst(4)), f > 0 else { return 0.5 }
    return f
  }

  // MARK: - Timeline, ladder, best five, pot counter, nuts

  static func timeline(_ instance: SpotInstance) -> TimelineData {
    let upTo = Street.allCases.filter { $0 <= instance.street }
    let board = instance.board
    let streets = upTo.map { street -> TimelineStreet in
      let shown = street == .preflop ? 0 : (street == .flop ? 3 : (street == .turn ? 4 : 5))
      let actions = instance.history.filter { $0.street == street }.map {
        "\(name($0.seat, instance)): \(actionText($0))"
      }
      return TimelineStreet(name: streetName(street), board: Array(board.prefix(shown)), actions: actions)
    }
    return TimelineData(streets: streets, current: max(streets.count - 1, 0))
  }

  static func ladder(_ ref: ExplainerRef, _ instance: SpotInstance) throws -> LadderData {
    let hero = heroCards(instance)
    var highlights: [HandCategory: String] = [:]
    highlights[category(hole: hero, board: instance.board)] = name(instance.heroSeat, instance)
    if (ref.bind["highlight"] ?? "both") != "hero", let villain = revealedVillain(instance) {
      let cat = category(hole: instance.holeCards[villain] ?? [], board: instance.board)
      let tag = name(villain, instance)
      highlights[cat] = highlights[cat].map { "\($0) & \(tag)" } ?? tag
    }
    return LadderData(highlights: highlights)
  }

  static func revealedVillain(_ instance: SpotInstance) -> Int? {
    instance.villainSeats.first { instance.reveal.contains($0) && instance.holeCards[$0] != nil }
  }

  static func bestFive(_ ref: ExplainerRef, _ instance: SpotInstance) throws -> BestFiveData {
    try requireBoard(.bestFiveHighlight, instance)
    let hero = heroCards(instance)
    // The page is shown after the verdict, so a bound villain hand is shown even when the spot hid it.
    let villain = instance.villainSeats.first { instance.holeCards[$0] != nil }
    var hole = hero
    switch ref.bind["hand"] ?? "hero" {
    case "villain":
      guard let villain, let theirs = instance.holeCards[villain] else {
        throw ExplainerBuildError.notApplicable(.bestFiveHighlight, "no villain hand")
      }
      hole = theirs
    case "winner":
      if let villain, let theirs = instance.holeCards[villain] {
        let mine = HandEvaluator.evaluate(hole: hero, board: instance.board)
        if HandEvaluator.evaluate(hole: theirs, board: instance.board) > mine { hole = theirs }
      }
    default: break
    }
    let cards = hole + instance.board
    return BestFiveData(
      cards: cards, best: HandEvaluator.bestFive(cards), description: HandDescription.describe(cards: cards))
  }

  static func potCounter(_ instance: SpotInstance) -> PotCounterData {
    var entries: [PotCounterEntry] = []
    var blinds = 0
    for logged in instance.log.events {
      if case .blindPosted(let posting) = logged.event { blinds += posting.amount }
    }
    entries.append(PotCounterEntry(label: "Blinds", amount: blinds))
    for street in Street.allCases where street <= instance.street {
      let chips = instance.history.filter { $0.street == street }.reduce(0) { $0 + $1.chipsAdded }
      if chips > 0 { entries.append(PotCounterEntry(label: streetName(street), amount: chips)) }
    }
    let toCall = instance.state.legalActions?.toCall ?? 0
    return PotCounterData(entries: entries, total: instance.state.pot, toCall: toCall > 0 ? toCall : nil)
  }

  static func nutsScan(_ instance: SpotInstance) throws -> NutsScanData {
    try requireBoard(.boardNutsScan, instance)
    let board = instance.board
    let nuts = BoardAnalyzer.nuts(board: board)
    let texture = BoardAnalyzer.texture(board)
    return NutsScanData(
      board: board, nuts: nuts.description, nutCards: nuts.combos.first?.cards ?? [],
      flushPossible: texture.flushPossible, straightPossible: texture.straightPossible,
      fullHousePossible: texture.isPaired || texture.hasTrips)
  }

  // MARK: - Pot slices and outs

  static func potSlices(_ ref: ExplainerRef, _ instance: SpotInstance) throws -> PotSlicesData {
    let context = instance.actor == instance.heroSeat ? instance.heroContext : nil
    let pot = (context ?? instance.actorContext).pot
    var call = (context ?? instance.actorContext).legal.toCall
    if call == 0 {
      call = max(1, Int((betFraction(ref.bind["size"]) * Double(pot)).rounded()))
    }
    return PotSlicesData(pot: pot, call: call)
  }

  static func outsGlow(_ instance: SpotInstance, villainRanges: [Int: HandRange]) throws -> OutsData {
    try requireBoard(.outsGlow, instance)
    let hole = heroCards(instance)
    let board = instance.board
    let dead = CardSet(hole + board)
    let ranges = instance.villainSeats.map { (villainRanges[$0] ?? .full).removing(dead) }
    var equity: Double?
    if ranges.count == 1, board.count >= 4 {
      equity = EquityCalculator.exact(hero: hole, vs: ranges[0], board: board).equity
    } else if !ranges.isEmpty {
      var rng = SeededRNG(seed: StableSeed.mix(instance.seed, 0x0A))
      let result = EquityCalculator.monteCarlo(hero: hole, vs: ranges, board: board, samples: 4000, using: &rng)
      equity = result.samples > 0 ? result.equity : nil
    }
    return OutsData(
      hole: hole, board: board, outs: BoardAnalyzer.outs(hole: hole, board: board),
      unseen: 52 - hole.count - board.count,
      exactEquity: equity)
  }

  // MARK: - Who calls me

  static func whoCallsMe(
    _ ref: ExplainerRef, _ instance: SpotInstance, characters: CharacterCatalog, villainRanges: [Int: HandRange]
  ) throws -> WhoCallsMeData {
    try requireBoard(.whoCallsMe, instance)
    let hero = heroCards(instance)
    let board = instance.board
    let dead = CardSet(hero + board)
    let facing = instance.actor == instance.heroSeat && (instance.heroContext?.legal.toCall ?? 0) > 0
    let mode: WhoCallsMeData.Mode =
      ref.bind["mode"].flatMap { WhoCallsMeData.Mode(rawValue: $0) } ?? (facing ? .bettors : .callers)
    guard let villainSeat = mainVillain(instance) else {
      throw ExplainerBuildError.notApplicable(.whoCallsMe, "no villain")
    }
    let heroValue = HandEvaluator.evaluate(hole: hero, board: board)
    var range = (villainRanges[villainSeat] ?? .full).removing(dead)
    var pCall: (Combo) -> Double = { _ in 1 }
    var villainName = name(villainSeat, instance)
    var betLabel: String?

    switch mode {
    case .bettors:
      if let last = instance.history.last(where: { $0.seat == villainSeat && $0.street == instance.street }),
        last.chipsAdded > 0
      {
        betLabel = "\(villainName) \(actionText(last))"
      }
    case .callers:
      guard let context = instance.heroContext else {
        throw ExplainerBuildError.notApplicable(.whoCallsMe, "hero is not to act")
      }
      let reply = try replyContext(
        context, fraction: betFraction(ref.bind["size"]), instance: instance, preferred: villainSeat)
      betLabel = reply.label
      villainName = name(reply.seat, instance)
      if reply.seat != villainSeat { range = (villainRanges[reply.seat] ?? .full).removing(dead) }
      let strategy =
        SpotRanges.strategies(instance, characters: characters)[reply.seat] ?? BaselineStrategy()
      let base = reply.context
      pCall = { combo in
        let asked = DecisionContext(
          config: base.config, seat: base.seat, holeCards: combo.cards, board: base.board, street: base.street,
          button: base.button, smallBlindSeat: base.smallBlindSeat, bigBlindSeat: base.bigBlindSeat,
          seats: base.seats, pot: base.pot, history: base.history, legal: base.legal)
        return 1 - strategy.distribution(for: asked).probability(of: .fold)
      }
    }

    var sums = [[(worse: Double, better: Double, folds: Double)]](
      repeating: [(worse: Double, better: Double, folds: Double)](repeating: (0, 0, 0), count: 13), count: 13)
    var worse = 0.0
    var better = 0.0
    var folds = 0.0
    let blocked = dead.bits
    for combo in range.nonZeroCombos where combo.mask.bits & blocked == 0 {
      let w = Double(range[combo])
      let call = mode == .callers ? pCall(combo) : 1
      let beatsHero = HandEvaluator.evaluate(hole: combo.cards, board: board) > heroValue
      let cls = combo.handClass
      var cell = sums[cls.gridRow][cls.gridColumn]
      if beatsHero {
        better += w * call
        cell.better += w * call
      } else {
        worse += w * call
        cell.worse += w * call
      }
      folds += w * (1 - call)
      cell.folds += w * (1 - call)
      sums[cls.gridRow][cls.gridColumn] = cell
    }
    let cells = sums.map { row in
      row.map { sum -> WhoCallsMeData.Cell in
        if sum.worse + sum.better + sum.folds <= 0 { return .none }
        if sum.worse >= sum.better && sum.worse >= sum.folds { return .worseCalls }
        return sum.better >= sum.folds ? .betterCalls : .folds
      }
    }
    let total = worse + better + folds
    return WhoCallsMeData(
      mode: mode, villainName: villainName, heroCards: hero, board: board, cells: cells,
      worseCalls: total > 0 ? worse / total : 0, betterCalls: total > 0 ? better / total : 0,
      folds: total > 0 ? folds / total : 0, betLabel: betLabel)
  }

  /// The context of the villain to act after the hero's bet of `fraction` of the pot, plus the bet's label.
  private static func replyContext(
    _ context: DecisionContext, fraction: Double, instance: SpotInstance, preferred: Int
  ) throws -> (context: DecisionContext, seat: Int, label: String) {
    let legal = context.legal
    guard let kind = legal.raiseKind, let range = legal.raiseRange else {
      throw ExplainerBuildError.notApplicable(.whoCallsMe, "hero cannot bet")
    }
    let action =
      ActionDistribution.potSizedRaises(fractions: [fraction], pot: context.pot, legal: legal).first
      ?? (kind == .bet ? .bet(to: range.lowerBound) : .raise(to: range.lowerBound))
    let step = try HandReducer.apply(action, to: instance.state)
    let target: Int
    switch action {
    case .bet(let to), .raise(let to): target = to
    default: target = legal.allInTo ?? range.upperBound
    }
    let entry = ActionEntry(
      street: context.street, seat: context.seat, action: action, chipsAdded: target - legal.committed,
      committedAfter: target, isAllIn: target == legal.allInTo)
    guard let next = step.state.seatToAct else {
      throw ExplainerBuildError.notApplicable(.whoCallsMe, "nobody left to reply")
    }
    guard let made = DecisionContext.make(from: step.state, for: next, history: context.history + [entry]) else {
      throw ExplainerBuildError.notApplicable(.whoCallsMe, "no reply context")
    }
    let seat = instance.villainSeats.contains(next) ? next : preferred
    return (made, seat, "You \(actionText(entry))")
  }
}
