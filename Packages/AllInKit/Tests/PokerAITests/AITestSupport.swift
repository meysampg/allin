import Foundation
import PokerCore
import PokerEquity
import Testing

@testable import PokerAI

/// Shared helpers of the personality tests (test targets cannot share files, so the names are unique).
enum AITestSupport {
  static let characterIDs = ["grumli", "zib", "vexa", "mott", "bram", "patron"]

  /// The six personality strategies from the shipped character files (the patron is varied with a fixed seed).
  static func personalities() throws -> [(id: String, strategy: PersonalityStrategy)] {
    let characters = try BotCharacter.loadAll(directory: BotCharacter.sourceTreeDirectory)
    return try characterIDs.map { id in
      let character = try #require(characters.first { $0.id == id })
      var params = try #require(character.params)
      if let variation = character.variation { params = params.varied(by: variation, seed: 1) }
      return (id, PersonalityStrategy(params: params, seed: 7))
    }
  }

  static func bot(_ id: String) throws -> PersonalityStrategy {
    try #require(personalities().first { $0.id == id }).strategy
  }

  static func card(_ text: String) -> Card { try! Card(text) }
  static func cards(_ text: String) -> [Card] { text.split(separator: " ").map { card(String($0)) } }
}

/// Builds decision contexts by applying scripted actions to a fresh 6-max or heads-up hand (button seat 0).
enum AIScript {
  static func table(seats: Int) -> TableConfig {
    try! TableConfig(seatCount: seats, smallBlind: 50, bigBlind: 100, chipUnit: 10)
  }

  /// The context of the seat to act after `actions`, with its hole cards (and optionally the board) replaced.
  static func context(
    seats: Int = 6, actions: [Action], hole: String? = nil, board: String? = nil, stack: Int = 10_000
  ) -> DecisionContext {
    optionalContext(seats: seats, actions: actions, hole: hole, board: board, stack: stack)!
  }

  /// Like ``context(seats:actions:hole:board:stack:)``; nil when the script ended the hand.
  static func optionalContext(
    seats: Int = 6, actions: [Action], hole: String? = nil, board: String? = nil, stack: Int = 10_000
  ) -> DecisionContext? {
    let stacks = (0..<seats).map { SeatStack(seat: $0, stack: stack) }
    var step = try! HandReducer.start(config: table(seats: seats), button: 0, stacks: stacks, seed: 11)
    var records = step.records
    for action in actions {
      guard step.state.seatToAct != nil, let next = try? HandReducer.apply(action, to: step.state) else { break }
      step = next
      records += step.records
    }
    guard let seat = step.state.seatToAct,
      let base = DecisionContext.make(from: step.state, for: seat, history: ActionEntry.entries(from: records))
    else { return nil }
    return DecisionContext(
      config: base.config, seat: base.seat, holeCards: hole.map(AITestSupport.cards) ?? base.holeCards,
      board: board.map(AITestSupport.cards) ?? base.board, street: base.street, button: base.button,
      smallBlindSeat: base.smallBlindSeat, bigBlindSeat: base.bigBlindSeat, seats: base.seats, pot: base.pot,
      history: base.history, legal: base.legal)
  }

  static func withHole(_ context: DecisionContext, _ cards: [Card]) -> DecisionContext {
    DecisionContext(
      config: context.config, seat: context.seat, holeCards: cards, board: context.board, street: context.street,
      button: context.button, smallBlindSeat: context.smallBlindSeat, bigBlindSeat: context.bigBlindSeat,
      seats: context.seats, pot: context.pot, history: context.history, legal: context.legal)
  }

  /// P(raise, bet or all-in) of a distribution.
  static func aggression(_ distribution: ActionDistribution) -> Double {
    distribution.entries.reduce(0) { sum, entry in
      switch entry.action {
      case .bet, .raise, .allIn: sum + entry.probability
      default: sum
      }
    }
  }

  /// P(any chips voluntarily: not fold, not check).
  static func playing(_ distribution: ActionDistribution) -> Double {
    distribution.entries.reduce(0) { sum, entry in
      switch entry.action {
      case .fold, .check: sum
      default: sum + entry.probability
      }
    }
  }
}

/// Random hands driven by ``UniformRandomStrategy``: 2 to 9 seats, random stacks, antes and chip units.
enum AIRandomPlayout {
  /// Calls `visit` with the context of every decision of hand `index`.
  static func decisions(index: Int, baseSeed: UInt64, visit: (DecisionContext) throws -> Void) throws {
    var rng = SeededRNG(seed: baseSeed &+ UInt64(index) &* 0x9E37_79B9)
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
      case 0: amount = Int.random(in: 1...max(1, bb), using: &rng)
      case 1: amount = Int.random(in: 1...(bb * 10), using: &rng)
      default: amount = Int.random(in: (bb * 10)...(bb * 300), using: &rng)
      }
      return SeatStack(seat: seat, stack: amount)
    }
    let button = Int.random(in: 0..<seatCount, using: &rng)
    var step = try HandReducer.start(config: config, button: button, stacks: stacks, seed: rng.next())
    var records = step.records
    let random = UniformRandomStrategy()
    while let seat = step.state.seatToAct {
      let context = try #require(
        DecisionContext.make(from: step.state, for: seat, history: ActionEntry.entries(from: records)))
      try visit(context)
      let action = random.distribution(for: context).sample(using: &rng)
      step = try HandReducer.apply(action, to: step.state)
      records += step.records
    }
  }
}
