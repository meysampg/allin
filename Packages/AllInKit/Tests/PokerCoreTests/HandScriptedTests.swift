import Testing

@testable import PokerCore

/// Scripted hands with exact expected stacks. Every action goes through `Played.act`, which checks chip
/// conservation (stacks plus pot) after each step.
@Suite struct HandScriptedTests {
  private func stacks(_ s: [Int]) -> [Int: Int] { Dictionary(uniqueKeysWithValues: s.enumerated().map { ($0, $1) }) }

  // MARK: Win by fold

  @Test func foldPreflopToBigBlind() throws {
    var h = try HandScript.start(button: 0, stacks: stacks(Array(repeating: 10_000, count: 6)))
    #expect(h.state.seatToAct == 3)
    try h.act(.fold, .fold, .fold, .fold)
    #expect(h.state.seatToAct == 1)  // the small blind, last to act
    try h.act(.fold)
    let result = try #require(h.state.result)
    #expect(result.reason == .uncontested)
    #expect(h.state.seats.map(\.stack) == [10_000, 9_950, 10_050, 10_000, 10_000, 10_000])
    #expect(h.returns == [SeatChips(seat: 2, amount: 50)])
    #expect(h.showdownSeats == nil)
    #expect(h.awards.map(\.shares) == [[SeatChips(seat: 2, amount: 100)]])
    #expect(result.board.isEmpty && h.streetsDealt.isEmpty)
    #expect(result.net.map(\.amount).reduce(0, +) == 0)
  }

  @Test func bigBlindOptionCheckedDown() throws {
    var h = try HandScript.start(
      button: 0, stacks: stacks([1000, 1000, 1000]),
      holes: [0: "AsAh", 1: "KsKh", 2: "7c2d"], board: "Qd9c5h3s8h")
    try h.act(.call, .call)
    #expect(h.state.seatToAct == 2)
    let legal = try #require(h.state.legalActions)
    #expect(legal.canCheck && legal.toCall == 0 && legal.minRaiseTo == 200)  // the big blind keeps its option
    try h.act(.check)
    #expect(h.state.street == .flop && h.state.seatToAct == 1)  // first live seat left of the button
    try h.act(.check, .check, .check)
    #expect(h.state.street == .turn)
    try h.act(.check, .check, .check)
    #expect(h.state.street == .river)
    try h.act(.check, .check, .check)
    #expect(h.state.seats.map(\.stack) == [1200, 900, 900])
    #expect(h.streetsDealt == [.flop, .turn, .river])
    #expect(h.showdownSeats == [1, 2, 0])  // nobody bet on the river: first seat left of the button
  }

  @Test func foldPostflopReturnsUncalledBet() throws {
    // Heads-up, button 0 is the small blind.
    var h = try HandScript.start(button: 0, stacks: stacks([1000, 1000]), board: "2c7d9hJsKd")
    #expect(h.state.seatToAct == 0)
    try h.act(.call, .check)
    #expect(h.state.street == .flop && h.state.seatToAct == 1)  // the big blind acts first postflop
    try h.act(.bet(to: 300), .fold)
    #expect(h.returns == [SeatChips(seat: 1, amount: 300)])
    #expect(h.state.seats.map(\.stack) == [900, 1100])
    #expect(h.state.result?.reason == .uncontested)
  }

  // MARK: Showdowns

  @Test func multiStreetShowdownLastAggressorShowsFirst() throws {
    var h = try HandScript.start(
      button: 0, stacks: stacks([3000, 3000, 3000]),
      holes: [0: "AhKd", 1: "JsTs", 2: "7h7c"], board: "Ks7d2h9c4s")
    try h.act(.raise(to: 300), .fold, .call)  // pot 650
    #expect(h.state.street == .flop && h.state.pot == 650 && h.state.seatToAct == 2)
    try h.act(.check, .bet(to: 400), .call)  // pot 1450
    #expect(h.state.street == .turn)
    try h.act(.check, .check)
    #expect(h.state.street == .river)
    try h.act(.bet(to: 200), .raise(to: 600), .call)  // seat 0 raised last
    #expect(h.state.seats.map(\.stack) == [1700, 2950, 4350])
    #expect(h.showdownSeats == [0, 2])
    #expect(h.state.result?.finalStack(of: 2) == 4350)
    #expect(h.state.board.count == 5 && h.state.burned.count == 3)
    let reveals = h.records.compactMap { r -> [ShowdownReveal]? in if case .showdown(let x) = r { x } else { nil } }
    #expect(reveals.first?.map(\.value.category) == [.pair, .threeOfAKind])
  }

  @Test func aggressionOnEarlierStreetDoesNotDecideShowdownOrder() throws {
    var h = try HandScript.start(
      button: 0, stacks: stacks([1000, 1000, 1000]),
      holes: [0: "AhKd", 1: "JsTs", 2: "7h7c"], board: "Qs8d2h9c4s")
    try h.act(.call, .call, .check)
    try h.act(.check, .check, .bet(to: 100), .fold, .call)  // seat 0 bets the flop
    try h.act(.check, .check, .check, .check)  // turn and river checked: aggressor resets
    #expect(h.showdownSeats == [2, 0])
    // Same hand but seat 0 bets the river.
    var g = try HandScript.start(
      button: 0, stacks: stacks([1000, 1000, 1000]),
      holes: [0: "AhKd", 1: "JsTs", 2: "7h7c"], board: "Qs8d2h9c4s")
    try g.act(.call, .call, .check)
    try g.act(Array(repeating: .check, count: 6))  // flop and turn
    try g.act(.check, .check, .bet(to: 100), .fold, .call)  // river: seats 1, 2 check, seat 0 bets
    #expect(g.showdownSeats == [0, 2])
  }

  @Test func splitPotOddChipGoesLeftOfButton() throws {
    var h = try HandScript.start(
      seatCount: 3, sb: 5, bb: 10, button: 0, stacks: stacks([1000, 1000, 1000]),
      holes: [0: "AsKd", 2: "AhKc"], board: "QsJd9c4h2d")
    try h.act(.call, .fold, .check)  // pot 25: 10 + 5 (dead) + 10
    try h.act(.check, .check, .check, .check, .check, .check)
    #expect(h.state.seats.map(\.stack) == [1002, 995, 1003])
    let award = try #require(h.awards.first)
    #expect(award.winners == [2, 0] && award.shares.map(\.amount) == [13, 12])
  }

  // MARK: All-in

  @Test(arguments: [0, 1, 2])
  func threeWayAllInPreflopWithSidePots(bestHand winner: Int) throws {
    // Seat 0 (button, first to act) shoves 1000, seat 1 calls 500 all-in, seat 2 calls 200 all-in.
    // Pots: main 600 (all), side 600 (seats 0 and 1), 500 of seat 0's shove is uncalled.
    var holes = [0: "QsQh", 1: "KsKh", 2: "AsAh"]
    if winner == 0 { holes = [0: "AsAh", 1: "KsKh", 2: "QsQh"] }
    if winner == 1 { holes = [0: "QsQh", 1: "AsAh", 2: "KsKh"] }
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 500, 2: 200], holes: holes, board: "2c5d9h7sJd")
    try h.act(.allIn, .allIn, .allIn)
    #expect(h.streetsDealt == [.flop, .turn, .river])
    #expect(h.requests == [0, 1, 2])  // nobody is asked to act during the runout
    #expect(h.returns == [SeatChips(seat: 0, amount: 500)])
    #expect(h.state.result?.reason == .showdown)
    #expect(h.showdownSeats == [0, 1, 2])  // seat 0 made the last raise, then clockwise
    // Best hand at seat 0 takes everything; at seat 1 the main and side pots; at seat 2 only the main pot.
    let finals: [Int: [Int]] = [0: [1700, 0, 0], 1: [500, 1200, 0], 2: [500, 600, 600]]
    #expect(h.state.seats.map(\.stack) == finals[winner]!)
  }

  @Test func shortStackBlindAllInSmallBlind() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 30, 2: 1000],
      holes: [0: "KsKh", 1: "AsAh", 2: "QsQh"], board: "2c5d9h7sJd")
    #expect(h.records.contains(.posted(Posting(seat: 1, kind: .smallBlind, amount: 30))))
    #expect(h.state.seat(1)?.status == .allIn && h.state.seatToAct == 0)
    try h.act(.call, .check)
    #expect(h.state.street == .flop && h.state.seatToAct == 2)
    try h.act(.check, .check)  // seat 1 is all-in and skipped
    try h.act(.check, .check, .check, .check)
    // Main pot 90 to seat 1; side pot 140 to seat 0.
    #expect(h.state.seats.map(\.stack) == [1040, 90, 900])
    #expect(h.awards.map(\.amount) == [90, 140])
  }

  @Test func shortStackBlindAllInBigBlind() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 1000, 2: 60],
      holes: [0: "KsKh", 1: "QsQh", 2: "AsAh"], board: "2c5d9h7sJd")
    try h.act(.call, .call)  // big blind is all-in for 60; the bet to match stays 100
    #expect(h.state.street == .flop && h.state.seatToAct == 1)
    try h.act(.check, .check)
    try h.act(.check, .check)
    try h.act(.check, .check)
    #expect(h.state.seats.map(\.stack) == [980, 900, 180])
    #expect(h.awards.map(\.amount) == [180, 80])
  }

  @Test func everyoneAllInFromTheBlinds() throws {
    // Both players are all-in after posting: the hand goes straight to the runout.
    let h = try HandScript.start(
      button: 0, stacks: [0: 50, 1: 100], holes: [0: "AsAh", 1: "KsKh"], board: "2c5d9h7sJd")
    #expect(h.state.isComplete)
    #expect(h.requests.isEmpty)
    #expect(h.streetsDealt == [.flop, .turn, .river])
    #expect(h.returns == [SeatChips(seat: 1, amount: 50)])
    #expect(h.state.seats.map(\.stack) == [100, 50])
  }

  @Test func allInCallForLessReturnsExcessHeadsUp() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 400], holes: [0: "KsKh", 1: "AsAh"], board: "2c5d9h7sJd")
    try h.act(.allIn, .allIn)
    #expect(h.returns == [SeatChips(seat: 0, amount: 600)])
    #expect(h.state.seats.map(\.stack) == [600, 800])
    #expect(h.state.result?.net.map(\.amount) == [-400, 400])
  }

  @Test func allInAfterFlopRunsOutTurnAndRiver() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 1000, 1: 1000], holes: [0: "AsAh", 1: "KsKh"], board: "2c5d9h7sJd")
    try h.act(.call, .check)
    try h.act(.bet(to: 100), .allIn, .call)
    #expect(h.streetsDealt == [.flop, .turn, .river])
    #expect(h.state.seats.map(\.stack) == [2000, 0])
    #expect(h.state.board.count == 5)
  }

  // MARK: Order and forced bets

  @Test func headsUpOrder() throws {
    var h = try HandScript.start(seatCount: 2, button: 1, stacks: [0: 1000, 1: 1000])
    guard case .handStarted(let info) = h.records[0] else { Issue.record("no start"); return }
    #expect(info.smallBlindSeat == 1 && info.bigBlindSeat == 0)
    #expect(h.state.seatToAct == 1)  // the button posts the small blind and acts first preflop
    try h.act(.call)
    #expect(h.state.seatToAct == 0)
    try h.act(.check)
    #expect(h.state.street == .flop && h.state.seatToAct == 0)  // and last postflop
    try h.act(.check)
    #expect(h.state.seatToAct == 1)
  }

  @Test func holeCardsDealtLeftOfButtonOneAtATime() throws {
    let deck = try HandScript.deck(
      seats: [0, 1, 2], button: 0, holes: [0: "AsAh", 1: "KsKh", 2: "QsQh"], board: "2c5d9h7sJd")
    let cfg = try TableConfig(seatCount: 3, smallBlind: 50, bigBlind: 100)
    let step = try HandReducer.start(
      config: cfg, button: 0, stacks: (0..<3).map { SeatStack(seat: $0, stack: 1000) }, deck: deck)
    let dealt = step.records.compactMap { r -> Int? in if case .holeCardsDealt(let s, _) = r { s } else { nil } }
    #expect(dealt == [1, 2, 0])
    #expect(step.state.seat(1)?.holeCards == [deck[0], deck[3]])
    #expect(step.state.seat(0)?.holeCards == [deck[2], deck[5]])
  }

  @Test func perPlayerAnteIsDeadMoney() throws {
    var h = try HandScript.start(
      sb: 50, bb: 100, ante: 10, button: 0, stacks: stacks([1000, 1000, 1000]))
    #expect(h.state.pot == 180)
    try h.act(.fold, .fold)
    // Pot 30 ante + 50 + 50 (big blind's other 50 came back) = 130.
    #expect(h.state.seats.map(\.stack) == [990, 940, 1070])
    #expect(h.returns == [SeatChips(seat: 2, amount: 50)])
  }

  @Test func anteGoesToShowdownPot() throws {
    var h = try HandScript.start(
      sb: 50, bb: 100, ante: 10, button: 0, stacks: stacks([1000, 1000, 1000]),
      holes: [0: "AsAh", 1: "KsKh", 2: "QsQh"], board: "2c5d9h7sJd")
    try h.act(.call, .call, .check)
    try h.act(Array(repeating: .check, count: 9))
    #expect(h.state.seats.map(\.stack) == [1220, 890, 890])  // pot 330 = 3 x (100 + 10)
  }

  @Test func bigBlindAnte() throws {
    var h = try HandScript.start(
      sb: 50, bb: 100, ante: 100, anteKind: .bigBlind, button: 0, stacks: stacks([1000, 1000, 1000]))
    #expect(h.records.contains(.posted(Posting(seat: 2, kind: .ante, amount: 100))))
    #expect(h.state.pot == 250 && h.state.seat(2)?.stack == 800)
    #expect(h.state.legalActions?.toCall == 100)  // the ante does not count toward the call amount
    try h.act(.fold, .fold)
    #expect(h.state.seats.map(\.stack) == [1000, 950, 1050])
  }

  @Test func shortStackCannotCoverAnteOrBlind() throws {
    // Seat 2 (big blind) has 60 and posts the 40 ante plus 20 of the blind.
    let h = try HandScript.start(
      sb: 50, bb: 100, ante: 40, anteKind: .bigBlind, button: 0, stacks: [0: 1000, 1: 1000, 2: 60])
    #expect(h.state.seat(2)?.status == .allIn && h.state.seat(2)?.stack == 0)
    #expect(h.state.contribution(of: 2) == 60)
  }
}
