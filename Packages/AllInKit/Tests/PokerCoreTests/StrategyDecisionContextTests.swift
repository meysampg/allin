import Testing

@testable import PokerCore

@Suite struct StrategyDecisionContextTests {
  /// All cards reachable by reflection from a value.
  private func cards(in value: Any) -> [Card] {
    if let c = value as? Card { return [c] }
    return Mirror(reflecting: value).children.flatMap { cards(in: $0.value) }
  }

  private func start() throws -> Played {
    try HandScript.start(
      seatCount: 4, button: 3, stacks: [0: 2000, 1: 2000, 2: 2000, 3: 2000],
      holes: [0: "AhAd", 1: "KsKc", 2: "7h2d", 3: "QsQh"], board: "2c7d9s")
  }

  @Test func containsOnlyOwnHoleCardsAndBoard() throws {
    var hand = try start()
    try hand.act(.call, .call, .call, .check)  // through preflop, now on the flop
    #expect(hand.state.street == .flop)
    let seat = hand.state.seatToAct!
    let ctx = DecisionContext.make(
      from: hand.state, for: seat, history: ActionEntry.entries(from: hand.records))!
    let own = hand.state.seat(seat)!.holeCards
    #expect(ctx.holeCards == own)
    let seen = Set(cards(in: ctx))
    #expect(seen == Set(own + hand.state.board))
    let hidden = hand.state.seats.filter { $0.seat != seat }.flatMap(\.holeCards) + hand.state.burned
    #expect(seen.isDisjoint(with: hidden))
    // Nothing from the undealt deck either.
    #expect(seen.isDisjoint(with: Set(hand.state.deck[hand.state.deckPosition...])))
  }

  @Test func publicFieldsMatchState() throws {
    let hand = try start()
    let seat = hand.state.seatToAct!
    let ctx = DecisionContext.make(from: hand.state, for: seat)!
    #expect(ctx.seat == seat)
    #expect(ctx.street == .preflop)
    #expect(ctx.button == 3)
    #expect(ctx.smallBlindSeat == 0 && ctx.bigBlindSeat == 1)
    #expect(ctx.pot == 150)
    #expect(ctx.legal == hand.state.legalActions)
    #expect(ctx.seats.map(\.seat) == [0, 1, 2, 3])
    #expect(ctx.view(of: 1)?.committedThisStreet == 100)
    #expect(ctx.view(of: 1)?.stack == 1900)
    #expect(ctx.view(of: 1)?.totalContribution == 100)
    #expect(ctx.liveSeats == [0, 1, 2, 3])
  }

  @Test func onlySeatToActGetsAContext() throws {
    let hand = try start()
    let toAct = hand.state.seatToAct!
    for s in 0..<4 where s != toAct {
      #expect(DecisionContext.make(from: hand.state, for: s) == nil)
    }
  }

  @Test func historyIsPublicAndOrderedByStreet() throws {
    var hand = try start()
    try hand.act(.call, .call, .raise(to: 300), .fold, .call, .call)
    let history = ActionEntry.entries(from: hand.records)
    #expect(history.count == 6)
    #expect(history.map(\.street) == Array(repeating: .preflop, count: 6))
    #expect(history[2].action == .raise(to: 300) && history[2].committedAfter == 300)
    if let seat = hand.state.seatToAct, hand.state.street == .flop {
      let ctx = DecisionContext.make(from: hand.state, for: seat, history: history)!
      #expect(ctx.history == history)
      #expect(ctx.street == .flop)
    }
    try hand.act(.check)
    let more = ActionEntry.entries(from: hand.records)
    #expect(more.last?.street == .flop)
  }
}
