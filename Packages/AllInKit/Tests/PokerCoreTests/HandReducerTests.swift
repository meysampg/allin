import Foundation
import Testing

@testable import PokerCore

@Suite struct HandReducerTests {
  private func config(_ seats: Int) throws -> TableConfig {
    try TableConfig(seatCount: seats, smallBlind: 50, bigBlind: 100, ante: 10)
  }
  private func stacks(_ n: Int) -> [SeatStack] { (0..<n).map { SeatStack(seat: $0, stack: 5_000) } }

  @Test func sameSeedSameHand() throws {
    let a = try HandReducer.start(config: config(6), button: 2, stacks: stacks(6), seed: 42)
    let b = try HandReducer.start(config: config(6), button: 2, stacks: stacks(6), seed: 42)
    let c = try HandReducer.start(config: config(6), button: 2, stacks: stacks(6), seed: 43)
    #expect(a == b)
    #expect(a.state != c.state)
    let next = try HandReducer.apply(.call, to: a.state)
    #expect(next == (try HandReducer.apply(.call, to: b.state)))
  }

  @Test func stateRoundTripsThroughJSON() throws {
    var step = try HandReducer.start(config: config(4), button: 1, stacks: stacks(4), seed: 7)
    step = try HandReducer.apply(.raise(to: 300), to: step.state)
    let data = try JSONEncoder().encode(step.state)
    let decoded = try JSONDecoder().decode(HandState.self, from: data)
    #expect(decoded == step.state)
    // The decoded state continues identically.
    #expect(try HandReducer.apply(.call, to: decoded) == (try HandReducer.apply(.call, to: step.state)))
  }

  @Test func illegalActionLeavesStateUnchanged() throws {
    let step = try HandReducer.start(config: config(3), button: 0, stacks: stacks(3), seed: 1)
    #expect(throws: ActionError.self) { try HandReducer.apply(.check, to: step.state) }
    #expect(throws: ActionError.self) { try HandReducer.apply(.raise(to: 150), to: step.state) }
  }

  @Test func noActionsAfterTheHandEnds() throws {
    var state = try HandReducer.start(config: config(2), button: 0, stacks: stacks(2), seed: 1).state
    state = try HandReducer.apply(.fold, to: state).state
    #expect(state.isComplete)
    #expect(throws: HandError.handComplete) { try HandReducer.apply(.check, to: state) }
  }

  @Test func rejectsBadDeckAndBadSeats() throws {
    let cfg = try config(3)
    #expect(throws: HandError.invalidDeck) {
      try HandReducer.start(config: cfg, button: 0, stacks: stacks(3), deck: Array(Card.all.dropLast()))
    }
    #expect(throws: BettingRoundError.self) {
      try HandReducer.start(config: cfg, button: 5, stacks: stacks(3), seed: 1)
    }
  }

  @Test func burnCardsCanBeDisabled() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 1000], holes: [0: "AsAh", 1: "KsKh"], board: "2c5d9h7sJd", burn: false)
    try h.act(.allIn, .allIn)
    // With no burns the board is simply the next five cards after the hole cards.
    #expect(h.state.burned.isEmpty)
    #expect(h.state.board.count == 5)
    #expect(h.state.undealtCount == 52 - 4 - 5)
  }

  /// Random legal play on every table size: the hand always terminates and chips are conserved.
  @Test(arguments: [2, 3, 6, 9])
  func randomPlayoutsConserveChips(seats: Int) throws {
    var rng = SeededRNG(seed: UInt64(seats) &* 977)
    for hand in 0..<150 {
      let cfg = try TableConfig(
        seatCount: seats, smallBlind: 50, bigBlind: 100, ante: hand % 3 == 0 ? 10 : 0,
        anteKind: hand % 2 == 0 ? .perPlayer : .bigBlind)
      let sk = (0..<seats).map { SeatStack(seat: $0, stack: 20 + Int(rng.next(upperBound: UInt64(3_000)))) }
      var step = try HandReducer.start(
        config: cfg, button: Int(rng.next(upperBound: UInt64(seats))), stacks: sk, seed: rng.next())
      let total = sk.reduce(0) { $0 + $1.stack }
      var guardCount = 0
      while !step.state.isComplete {
        guardCount += 1
        #expect(guardCount < 500)
        let legal = step.state.legalActions!
        var options: [Action] = [.fold]
        if legal.canCheck { options.append(.check) }
        if legal.canCall { options.append(.call) }
        if legal.canAllIn { options.append(.allIn) }
        if let r = legal.raiseRange, let k = legal.raiseKind {
          let to = r.lowerBound + Int(rng.next(upperBound: UInt64(r.count)))
          if legal.isLegal(k == .bet ? .bet(to: to) : .raise(to: to)) {
            options.append(k == .bet ? .bet(to: to) : .raise(to: to))
          }
        }
        // Prefer staying in so hands reach showdown.
        let pick =
          rng.next(upperBound: UInt64(10)) == 0 ? options[0] : options[Int(rng.next(upperBound: UInt64(options.count)))]
        step = try HandReducer.apply(pick, to: step.state)
        #expect(step.state.totalChips == total)
      }
      let result = try #require(step.state.result)
      #expect(result.net.reduce(0) { $0 + $1.amount } == 0)
      #expect(result.finalStacks.reduce(0) { $0 + $1.amount } == total)
      #expect(step.state.pot == 0)
    }
  }
}
