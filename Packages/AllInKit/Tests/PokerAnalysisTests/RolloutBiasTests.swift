import Foundation
import PokerAI
import PokerCore
import PokerEquity
import Testing

@testable import PokerAnalysis

/// Records every board it is shown (thread-safe: the estimator may run the strategy from several tasks).
private final class BoardLog: @unchecked Sendable {
  private let lock = NSLock()
  private var seen = Set<Int>()

  func record(_ board: [Card]) {
    lock.lock()
    defer { lock.unlock() }
    for card in board { seen.insert(Int(card.index)) }
  }

  var cards: Set<Int> {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }
}

@Suite struct RolloutBiasTests {
  /// 6-max, the button raised, four seats folded, the hero (big blind) is to act preflop.
  private func preflopSpotWithFoldedSeats() throws -> BuiltSpot {
    try spot(
      heroSeat: 2, seatCount: 6, button: 0, stacks: [200, 200, 200, 200, 200, 200],
      holes: [0: "As Ad", 1: "6c 6d", 2: "Kh Qd", 3: "4c 4d", 4: "3c 3d", 5: "5c 5d"],
      board: "7c 8d 9h Ts 2c",
      actions: [.fold, .fold, .fold, .raise(to: 6), .fold])
  }

  @Test func foldedSeatCardsDoNotBiasTheRunout() throws {
    let built = try preflopSpotWithFoldedSeats()
    let log = BoardLog()
    let watcher = ClosureStrategy { context in
      log.record(context.board)
      return context.legal.canCheck ? [(.check, 1)] : [(.call, 1)]
    }
    // Rollout decks start from the lowest card indexes; the folded seats used to take them all.
    let request = EVRequest(
      spot: built.spot, opponentRanges: [0: .full], opponents: [0: watcher], hero: watcher, chosen: nil,
      budget: EVBudget(rolloutsPerCandidate: 300, policyStreets: 4, chunks: 1), seed: 5)
    _ = try ActionEVEstimator.estimateSerial(request)
    let lowest = log.cards.filter { $0 < 8 }
    #expect(!lowest.isEmpty, "the four lowest ranks never reached a board")
    #expect(log.cards.count > 40)
  }

  @Test func preflopShoveEVMatchesDirectPlayout() throws {
    // 4 seats, button 0 (hero) shoves; the small blind folds and the big blind always calls; seat 3 folded.
    let heroCards = "Qs Th"
    let built = try spot(
      heroSeat: 0, seatCount: 4, button: 0, stacks: [200, 200, 200, 200],
      holes: [0: heroCards, 1: "6c 6d", 2: "Ah Ad", 3: "4c 4d"],
      board: "2c 3d 7h 5s 9c", actions: [.fold])
    let villain = ClosureStrategy { context in
      if context.seat == 1 { return [(.fold, 1)] }
      return context.legal.canCheck ? [(.check, 1)] : [(.call, 1)]
    }
    let request = EVRequest(
      spot: built.spot, opponentRanges: [1: .full, 2: .full], opponents: [1: villain, 2: villain], hero: villain,
      chosen: .allIn, budget: EVBudget(rolloutsPerCandidate: 3_000, policyStreets: 4, chunks: 1), seed: 9)
    let estimate = try #require(ActionEVEstimator.estimateSerial(request).candidate(for: .allIn))

    // Independent playout with uniformly random hidden cards.
    var rng = SeededRNG(seed: 77)
    let hero = cards(heroCards)
    var values: [Double] = []
    let config = try TableConfig(seatCount: 4, smallBlind: 1, bigBlind: 2)
    for _ in 0..<3_000 {
      var deck = Deck(removing: CardSet(hero))
      deck.shuffle(using: &rng)
      let holes: [Int: [Card]] = [0: hero, 1: deck.deal(2)!, 2: deck.deal(2)!, 3: deck.deal(2)!]
      let board = deck.deal(5)!
      let order = try #require(
        DeckLayout.deck(
          button: 0, seats: [0, 1, 2, 3], burnsCards: true, holes: holes, board: board, rest: Array(deck.undealt)))
      var state = try HandReducer.start(
        config: config, button: 0, stacks: (0..<4).map { SeatStack(seat: $0, stack: 200) }, deck: order
      ).state
      for action in [Action.fold, .allIn, .fold, .call] { state = try HandReducer.apply(action, to: state).state }
      let final = try #require(state.result?.finalStack(of: 0))
      values.append(Double(final - 200) / 2)
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    let directSE = (variance / Double(values.count)).squareRoot()
    let bound = 3 * (directSE * directSE + estimate.standardError * estimate.standardError).squareRoot()
    #expect(abs(estimate.evBB - mean) <= bound, "estimate \(estimate.evBB) vs direct \(mean), bound \(bound)")
  }
}
