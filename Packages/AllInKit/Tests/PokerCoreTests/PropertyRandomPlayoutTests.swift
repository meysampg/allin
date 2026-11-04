import Testing

@testable import PokerCore

/// Plays random hands through ``HandReducer`` with ``UniformRandomStrategy`` and checks invariants after every
/// step. (The same harness runs 100k hands in `HeavyTests/PropertyHeavyPlayoutTests.swift`.)
enum RandomPlayout {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  /// Plays hand number `index` of the run; returns the number of actions taken.
  @discardableResult
  static func play(index: UInt64, baseSeed: UInt64) throws -> Int {
    var rng = SeededRNG(seed: baseSeed &+ index &* 0x9E37_79B9)
    let seatCount = Int.random(in: 2...9, using: &rng)
    let unit = [1, 1, 1, 5, 25].randomElement(using: &rng)!
    let sb = unit * Int.random(in: 1...4, using: &rng)
    let bb = sb * Int.random(in: 1...2, using: &rng)
    let anteKind: AnteKind = Bool.random(using: &rng) ? .perPlayer : .bigBlind
    let ante = Int.random(in: 0..<4, using: &rng) == 0 ? unit * Int.random(in: 1...3, using: &rng) : 0
    let config = try TableConfig(
      seatCount: seatCount, smallBlind: sb, bigBlind: bb, ante: ante, anteKind: anteKind, chipUnit: unit)
    let stacks: [SeatStack] = (0..<seatCount).map { seat in
      let amount: Int
      switch Int.random(in: 0..<4, using: &rng) {
      case 0: amount = Int.random(in: 1...max(1, bb), using: &rng)  // shorter than the big blind
      case 1: amount = Int.random(in: 1...(bb * 10), using: &rng)  // short
      default: amount = Int.random(in: (bb * 10)...(bb * 300), using: &rng)  // deep
      }
      return SeatStack(seat: seat, stack: amount)
    }
    let button = Int.random(in: 0..<seatCount, using: &rng)
    let total = stacks.reduce(0) { $0 + $1.stack }
    let label = "hand \(index) cfg=\(config) button=\(button) stacks=\(stacks.map(\.stack))"

    var step = try HandReducer.start(
      config: config, button: button, stacks: stacks, seed: rng.next(), burnsCards: Bool.random(using: &rng))
    var records = step.records
    try check(step.state, total: total, label: label)

    let strategy = UniformRandomStrategy()
    var actions = 0
    let bound = 2000
    while let seat = step.state.seatToAct {
      guard actions < bound else { throw Failure(description: "no termination in \(bound) actions: \(label)") }
      guard
        let context = DecisionContext.make(
          from: step.state, for: seat, history: ActionEntry.entries(from: records))
      else { throw Failure(description: "no context for seat \(seat): \(label)") }
      let distribution = strategy.distribution(for: context)
      do { try distribution.validate(against: context.legal) } catch {
        throw Failure(description: "illegal distribution \(error): \(label)")
      }
      let action = distribution.sample(using: &rng)
      step = try HandReducer.apply(action, to: step.state)
      records += step.records
      actions += 1
      try check(step.state, total: total, label: label + " after \(action)")
    }
    try checkEnd(step.state, total: total, label: label)
    return actions
  }

  private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Failure(description: message()) }
  }

  private static func check(_ state: HandState, total: Int, label: String) throws {
    try require(state.totalChips == total, "chips not conserved (\(state.totalChips) vs \(total)): \(label)")
    try require(state.seats.allSatisfy { $0.stack >= 0 }, "negative stack: \(label)")
    try require(state.pot >= 0, "negative pot: \(label)")
    try require(
      state.board.count == (Street.allCases.filter { $0 <= state.street }.reduce(0) { $0 + $1.cardsDealt }),
      "board size \(state.board.count) does not match street \(state.street): \(label)")

    // No duplicate cards among hole cards, board and burned; they are exactly the dealt prefix of the deck.
    let dealt = state.seats.flatMap(\.holeCards) + state.board + state.burned
    try require(CardSet(dealt).count == dealt.count, "duplicate card: \(label)")
    try require(CardSet(dealt) == CardSet(state.deck[..<state.deckPosition]), "dealt cards differ from deck: \(label)")
    try require(state.seats.allSatisfy { $0.holeCards.count == 2 }, "hole cards missing: \(label)")

    if let seat = state.seatToAct {
      guard let legal = state.legalActions, legal.seat == seat else {
        throw Failure(description: "no legal actions for seat \(seat): \(label)")
      }
      let mine = state.seat(seat)!
      try require(mine.status == .active && mine.stack > 0, "seat to act cannot act: \(label)")
      let options: [Bool] = [
        legal.canCheck, legal.canCall, legal.raiseRange != nil, legal.canAllIn,
      ]
      try require(options.contains(true), "legal action set empty (only fold): \(label)")
      try require(legal.canCheck != (legal.toCall > 0), "check/toCall inconsistent: \(label)")
    }
  }

  private static func checkEnd(_ state: HandState, total: Int, label: String) throws {
    guard let result = state.result else { throw Failure(description: "not complete: \(label)") }
    try require(state.pot == 0, "pot not zero at end: \(label)")
    try require(state.round == nil, "round open at end: \(label)")
    try require(result.net.reduce(0) { $0 + $1.amount } == 0, "net does not sum to zero: \(label)")
    try require(result.finalStacks.reduce(0) { $0 + $1.amount } == total, "final stacks differ: \(label)")
    try require(result.board == state.board, "result board differs: \(label)")
    try require(
      result.contributions.reduce(0) { $0 + $1.amount } <= total, "contributions exceed chips: \(label)")
    for s in state.seats {
      try require(result.finalStack(of: s.seat) == s.stack, "final stack mismatch: \(label)")
      try require(result.netChips(of: s.seat) == s.stack - s.startingStack, "net mismatch: \(label)")
    }
    if result.reason == .showdown {
      try require(state.board.count == 5, "showdown without full board: \(label)")
    }
  }
}

@Suite struct PropertyRandomPlayoutTests {
  @Test func tenThousandRandomHands() throws {
    var actions = 0
    for i in 0..<10_000 {
      actions += try RandomPlayout.play(index: UInt64(i), baseSeed: 0xA11_1A)
    }
    #expect(actions > 10_000)
  }

  @Test func sameSeedReplaysTheSameHand() throws {
    #expect(try RandomPlayout.play(index: 17, baseSeed: 5) == RandomPlayout.play(index: 17, baseSeed: 5))
  }
}
