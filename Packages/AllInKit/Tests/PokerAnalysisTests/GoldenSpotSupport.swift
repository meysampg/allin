import PokerCore
import PokerEquity

@testable import PokerAnalysis

/// A hand-built decision with a known answer, graded at the cheap `.test` budget.
struct GoldenSpot {
  let name: String
  let request: EVRequest

  var context: DecisionContext { request.spot.context }

  /// Estimates once (serially) and grades `chosen`.
  func grade(_ chosen: Action) throws -> (graded: GradedDecision, evs: ActionEVResult) {
    let evs = try ActionEVEstimator.estimateSerial(request)
    let canonical = DecisionGrader.canonical(chosen, legal: context.legal)
    let graded = DecisionGrader.grade(
      evs, chosen: canonical, potBefore: context.pot, bigBlind: context.config.bigBlind)
    return (graded, evs)
  }
}

enum GoldenSpots {
  static let nuts = "Ah Qh"
  static let pair = "Kd Qc"

  private static func make(
    _ name: String, built: BuiltSpot, villainSeat: Int, range: HandRange, strategy: any StrategyProvider,
    budget: EVBudget = .test
  ) -> GoldenSpot {
    GoldenSpot(
      name: name,
      request: EVRequest(
        spot: built.spot, opponentRanges: [villainSeat: range], opponents: [villainSeat: strategy],
        hero: AlwaysCall(), chosen: nil, budget: budget, seed: 11))
  }

  /// G1: river, hero has the nut flush and checks to a calling station.
  static func riverValueBetVsStation() throws -> GoldenSpot {
    let built = try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: pair, 1: nuts],
      board: riverBoard, actions: checkedToRiver)
    return make("G1", built: built, villainSeat: 0, range: range("KdQc"), strategy: AlwaysCall())
  }

  /// G2: river, hero has top pair and faces a pot bet from a range that is only the nut flush.
  static func riverFoldVsNuts() throws -> GoldenSpot {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: pair, 1: nuts],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 40)])
    return make("G2", built: built, villainSeat: 1, range: range("AhQh"), strategy: AlwaysCall())
  }

  /// G3: river, hero has top pair and faces a half-pot bet from half flushes, half air: calling is +10 bb.
  /// The villain folds the air to a raise, so raising is worse than calling.
  static func bluffCatcherCall() throws -> GoldenSpot {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: pair, 1: nuts],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 20)])
    let villain = ClosureStrategy { context in
      if context.holeCards.contains(try! Card("Ah")) { return [(.call, 1)] }
      return [(context.legal.canCheck ? .check : .fold, 1)]
    }
    return make("G3", built: built, villainSeat: 1, range: range("AhQh", "JdTd"), strategy: villain)
  }

  /// G6: heads-up preflop, the small blind shoves 200 with the top 30%, hero has aces in the big blind.
  static func preflopAAvsShove() throws -> GoldenSpot {
    let built = try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah As"],
      board: riverBoard, actions: [.allIn])
    return make(
      "G6", built: built, villainSeat: 0, range: HandRange.top(0.3), strategy: AlwaysCall(),
      budget: EVBudget(rolloutsPerCandidate: 125, policyStreets: 1, chunks: 2))
  }
}

// MARK: Scripted hands and synthetic analyses

/// Plays `actions` from a dealt deck (small blind 1, big blind 2) and returns the host log.
func scriptedLog(
  seatCount: Int, button: Int, stacks: [Int], holes: [Int: String], board: String, actions: [Action],
  handID: UInt64 = 1
) throws -> EventLog {
  let boardCards = cards(board)
  let holeCards = holes.mapValues { cards($0) }
  let used = CardSet(boardCards + holeCards.values.flatMap { $0 })
  let rest = Card.all.filter { !used.contains($0) }
  let seats = Array(0..<seatCount)
  guard
    let deck = DeckLayout.deck(
      button: button, seats: seats, burnsCards: true, holes: holeCards, board: boardCards, rest: rest)
  else { throw EVError.invalidSpot("bad scripted deck") }
  let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
  var steps = [
    try HandReducer.start(
      config: config, button: button, stacks: seats.map { SeatStack(seat: $0, stack: stacks[$0]) }, deck: deck)
  ]
  for action in actions { steps.append(try HandReducer.apply(action, to: steps[steps.count - 1].state)) }
  return EventLog(handID: HandID(handID), steps: steps)
}

/// A graded decision with a chosen loss of `lossBB` (pot 100 chips, bb 2: 0 is good, 3 a small miss, 6 a leak).
func fakeGraded(lossBB: Double) -> GradedDecision {
  func ev(_ action: Action, _ value: Double) -> CandidateEV {
    CandidateEV(
      action: action, label: "\(action)", shortLabel: "\(action)", evBB: value, standardError: 0, samples: 0,
      method: .rollout)
  }
  let result = ActionEVResult(candidates: [ev(.check, 10), ev(.allIn, 10 - lossBB)])
  return DecisionGrader.grade(result, chosen: lossBB == 0 ? .check : .allIn, potBefore: 100, bigBlind: 2)
}

func fakeDecision(
  index: Int, street: Street = .turn, facing: Facing = .none, chosen: ActionClass = .passive,
  best: ActionClass = .aggressive, lossBB: Double
) -> ReviewedDecision {
  let graded = fakeGraded(lossBB: lossBB)
  let kind = DecisionKind(street: street, facing: facing, chosen: chosen, best: best)
  return ReviewedDecision(
    index: index, requestSeq: index * 2, actionSeq: index * 2 + 1, street: street, board: [], heroCards: [],
    potBefore: 100, toCall: 0, graded: graded, kind: kind, focusSeat: nil, focusName: nil, focusStyle: nil,
    focusRangeGrid: nil, equityVsFocus: nil, potOddsNeeded: nil, tag: "check",
    timelineText: ReviewNarrator.timelineText(tag: "check", graded: graded), title: "", body: "")
}

func fakeAnalysis(
  net: Int = 0, decisions: [ReviewedDecision] = [], weightedQuality: Double = 0, weight: Double = 0,
  luck: LuckResult? = nil
) -> HandAnalysis {
  var counts = GradeCounts()
  for d in decisions { counts.add(d.graded.grade) }
  let noLuck = LuckResult(
    netChips: net, expectedNetChips: Double(net), luckChips: 0, wasAllIn: false, allInStreet: nil, heroEquity: nil)
  return HandAnalysis(
    handID: HandID(1), heroSeat: 0, bigBlind: 2, netChips: net, potTotal: 100, decisions: decisions, counts: counts,
    luck: luck ?? noLuck,
    weightedQuality: weightedQuality, weight: weight,
    decisionScore: weight > 0 ? 100 * weightedQuality / weight : nil,
    evLossBB: decisions.reduce(0) { $0 + $1.graded.evLossBB }, budget: .test)
}
