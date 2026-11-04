import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

private struct Calls: StrategyProvider {
  func distribution(for context: DecisionContext) -> ActionDistribution {
    try! ActionDistribution(certain: context.legal.canCheck ? .check : .call, legal: context.legal)
  }
}

private struct Stable {
  let name: String
  let spot: EVSpot
  let ranges: [Int: HandRange]
  let opponents: [Int: any StrategyProvider]
  let hero: any StrategyProvider
  let chosen: Action

  func grade(seed: UInt64, budget: EVBudget) async throws -> Grade {
    let request = EVRequest(
      spot: spot, opponentRanges: ranges, opponents: opponents, hero: hero, chosen: chosen, budget: budget,
      seed: seed)
    let evs = try await ActionEVEstimator.estimate(request)
    let context = spot.context
    let action = DecisionGrader.canonical(chosen, legal: context.legal)
    return DecisionGrader.grade(
      evs, chosen: action, potBefore: context.pot, bigBlind: context.config.bigBlind
    ).grade
  }
}

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

private func combos(_ texts: String...) -> HandRange {
  var weights = [Float](repeating: 0, count: 1326)
  for text in texts { weights[try! Combo(text).index] = 1 }
  return HandRange(weights: weights)
}

/// Deals the cards (blinds 1/2), plays `actions` and returns the spot of the seat to act.
private func handSpot(
  seatCount: Int, stacks: [Int], holes: [Int: String], board: String, actions: [Action]
) throws -> EVSpot {
  let boardCards = cards(board)
  let holeCards = holes.mapValues { cards($0) }
  let used = CardSet(boardCards + holeCards.values.flatMap { $0 })
  let seats = Array(0..<seatCount)
  let rest = Card.all.filter { !used.contains($0) }
  let deck = try #require(
    DeckLayout.deck(button: 0, seats: seats, burnsCards: true, holes: holeCards, board: boardCards, rest: rest))
  let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
  var steps = [
    try HandReducer.start(
      config: config, button: 0, stacks: seats.map { SeatStack(seat: $0, stack: stacks[$0]) }, deck: deck)
  ]
  for action in actions { steps.append(try HandReducer.apply(action, to: steps[steps.count - 1].state)) }
  return try spotOfLast(steps)
}

private func spotOfLast(_ steps: [HandStep]) throws -> EVSpot {
  let log = EventLog(handID: HandID(1), steps: steps)
  let start = try #require(DecisionPoints.start(of: log.events))
  let state = steps[steps.count - 1].state
  let seat = try #require(state.seatToAct)
  let history = ActionEntry.entries(from: steps.flatMap(\.records))
  let context = try #require(DecisionContext.make(from: state, for: seat, history: history))
  let prior = DecisionPoints.actions(of: log.events)
  return EVSpot(start: start, priorActions: prior, context: context)
}

private extension DecisionPoints {
  /// The actions applied in a log, in order.
  static func actions(of events: [LoggedEvent]) -> [Action] {
    events.compactMap { logged in
      if case .actionTaken(let taken) = logged.event { return taken.action }
      return nil
    }
  }
}

@Suite struct GradeStabilityTests {
  private let riverBoard = "2h 7h Kh 4c 9d"

  private func goldenSpots() throws -> [Stable] {
    let checked: [Action] = [.raise(to: 20), .call, .check, .check, .check, .check]
    let villainPolicy: any StrategyProvider = Calls()
    func make(_ name: String, _ spot: EVSpot, villain: Int, range: HandRange, chosen: Action) -> Stable {
      Stable(
        name: name, spot: spot, ranges: [villain: range], opponents: [villain: villainPolicy], hero: Calls(),
        chosen: chosen)
    }
    let g1 = try handSpot(
      seatCount: 2, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"], board: riverBoard, actions: checked)
    let g2 = try handSpot(
      seatCount: 2, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"], board: riverBoard,
      actions: checked + [.bet(to: 40)])
    let g3 = try handSpot(
      seatCount: 2, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"], board: riverBoard,
      actions: checked + [.bet(to: 20)])
    let g6 = try handSpot(
      seatCount: 2, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah As"], board: riverBoard, actions: [.allIn])
    return [
      make("G1", g1, villain: 0, range: combos("KdQc"), chosen: .check),
      make("G2", g2, villain: 1, range: combos("AhQh"), chosen: .call),
      make("G3", g3, villain: 1, range: combos("AhQh", "JdTd"), chosen: .fold),
      make("G6", g6, villain: 0, range: HandRange.top(0.3), chosen: .call),
    ]
  }

  /// A seeded heads-up hand played by two baseline bots; nil unless the hero (seat 0) decides on the turn or river.
  private func randomSpot(_ index: Int) throws -> Stable? {
    let config = try TableConfig(seatCount: 2, smallBlind: 1, bigBlind: 2)
    let baseline = BaselineStrategy()
    var steps = [
      try HandReducer.start(
        config: config, button: index % 2, stacks: [SeatStack(seat: 0, stack: 200), SeatStack(seat: 1, stack: 200)],
        seed: StableSeed.mix(0xB10C, UInt64(index)))
    ]
    var rng = SeededRNG(seed: StableSeed.mix(0x5EED, UInt64(index)))
    var candidates: [(EVSpot, Action)] = []
    while let seat = steps[steps.count - 1].state.seatToAct {
      let state = steps[steps.count - 1].state
      let history = ActionEntry.entries(from: steps.flatMap(\.records))
      guard let context = DecisionContext.make(from: state, for: seat, history: history) else { return nil }
      let action = baseline.distribution(for: context).sample(using: &rng)
      if seat == 0 { candidates.append((try spotOfLast(steps), action)) }
      steps.append(try HandReducer.apply(action, to: state))
    }
    // The last decision on the turn or the river: late spots have short rollouts and a clear answer.
    guard let (spot, action) = candidates.last(where: { $0.0.context.street >= .turn }) else { return nil }
    return Stable(
      name: "random \(index)", spot: spot, ranges: [1: .full], opponents: [1: baseline], hero: baseline,
      chosen: action)
  }

  @Test func gradesDoNotDependOnTheSeed() async throws {
    var spots = try goldenSpots()
    var index = 0
    while spots.count < 20 && index < 400 {
      if let spot = try randomSpot(index) { spots.append(spot) }
      index += 1
    }
    #expect(spots.count == 20)
    var identical = 0
    for spot in spots {
      let a = try await spot.grade(seed: 1, budget: .standard)
      let b = try await spot.grade(seed: 2, budget: .standard)
      print("grade stability \(spot.name) (\(spot.spot.context.street.rawValue)): \(a) / \(b)")
      if a == b { identical += 1 }
    }
    print("grade stability: \(identical) of \(spots.count) identical")
    #expect(identical >= 19)
  }
}
