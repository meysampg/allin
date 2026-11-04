import Testing

@testable import PokerCore

@Suite struct RulesBettingRoundTests {
  private let cfg6 = try! TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100)

  private func stacks(_ s: [Int]) -> [SeatStack] {
    s.enumerated().map { SeatStack(seat: $0.offset, stack: $0.element) }
  }

  /// Preflop 6-max, button seat 0, SB 1, BB 2, UTG 3.
  private func preflop6(_ s: [Int] = [10_000, 10_000, 10_000, 10_000, 10_000, 10_000]) throws -> BettingRound {
    try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks(s)).round
  }

  // MARK: Positions and blinds

  @Test func sixMaxPositionsAndPostings() throws {
    let (r, posts) = try BettingRound.preflop(
      config: cfg6, button: 0, stacks: stacks(Array(repeating: 10_000, count: 6)))
    #expect(posts == [Posting(seat: 1, kind: .smallBlind, amount: 50), Posting(seat: 2, kind: .bigBlind, amount: 100)])
    #expect(r.toAct == 3 && r.currentBet == 100 && r.lastRaiseSize == 100)
    #expect(r.player(at: 1)?.committed == 50 && r.player(at: 2)?.stack == 9_900)
  }

  @Test func headsUpButtonPostsSmallBlindAndActsFirstPreflopLastPostflop() throws {
    let cfg = try TableConfig(seatCount: 2, smallBlind: 50, bigBlind: 100)
    let pos = HandPositions(button: 1, seats: [0, 1])!
    #expect(pos.smallBlind == 1 && pos.bigBlind == 0 && pos.firstToActPreflop == 1)
    var (r, posts) = try BettingRound.preflop(config: cfg, button: 1, stacks: stacks([5000, 5000]))
    #expect(posts.first { $0.kind == .smallBlind }?.seat == 1)
    #expect(r.toAct == 1)
    try r.apply(.call)
    #expect(r.toAct == 0)  // BB option
    try r.apply(.check)
    #expect(r.isClosed)
    // Postflop the big blind (non-button) acts first.
    let post = try BettingRound.postflop(config: cfg, button: 1, players: stacks([4900, 4900]))
    #expect(post.toAct == 0)
  }

  @Test func threeHandedPositionsWrapAround() {
    let pos = HandPositions(button: 4, seats: [4, 0, 2])!
    #expect(pos.smallBlind == 0 && pos.bigBlind == 2 && pos.firstToActPreflop == 4)
    #expect(HandPositions(button: 3, seats: [4, 0, 2]) == nil)
  }

  @Test func anteAndBigBlindAnte() throws {
    let perPlayer = try TableConfig(seatCount: 3, smallBlind: 50, bigBlind: 100, ante: 10)
    let a = try BettingRound.preflop(config: perPlayer, button: 0, stacks: stacks([1000, 1000, 1000]))
    #expect(a.postings.filter { $0.kind == .ante }.map(\.amount) == [10, 10, 10])
    #expect(a.round.totalCommitted == 150 && a.round.player(at: 0)?.stack == 990)

    let bbAnte = try TableConfig(seatCount: 3, smallBlind: 50, bigBlind: 100, ante: 100, anteKind: .bigBlind)
    let b = try BettingRound.preflop(config: bbAnte, button: 0, stacks: stacks([1000, 1000, 1000]))
    #expect(b.postings.first == Posting(seat: 2, kind: .ante, amount: 100))
    #expect(b.round.player(at: 2)?.stack == 800 && b.round.player(at: 2)?.committed == 100)
    #expect(b.round.totalCommitted == 150)  // ante is dead money, not a street bet
  }

  @Test func shortStackPostsWhatItHasAndIsAllIn() throws {
    let (r, posts) = try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks([1000, 30, 1000]))
    #expect(posts.contains(Posting(seat: 1, kind: .smallBlind, amount: 30)))
    #expect(r.player(at: 1)?.status == .allIn && r.toAct == 0)
  }

  // MARK: Min-raise

  @Test func minRaiseEqualsLastFullRaiseIncrement() throws {
    var r = try preflop6()
    #expect(r.legalActions()?.minRaiseTo == 200)
    try r.apply(.raise(to: 300))  // +200 increment
    #expect(r.lastRaiseSize == 200 && r.legalActions()?.minRaiseTo == 500)
    try r.apply(.raise(to: 500))
    #expect(r.lastRaiseSize == 200 && r.legalActions()?.minRaiseTo == 700)
  }

  @Test func postflopMinBetIsBigBlindAndMinRaiseFollowsBet() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 1000, 1000]))
    #expect(r.toAct == 1 && r.legalActions()?.raiseRange == 100...1000)
    try r.apply(.bet(to: 300))
    #expect(r.legalActions()?.minRaiseTo == 600)
  }

  // MARK: Illegal actions

  @Test func illegalAmountsAndActionsRejectedWithoutChangingState() throws {
    var r = try preflop6()
    let snapshot = r
    #expect(throws: ActionError.amountOutOfRange(.raise(to: 150), min: 200, max: 10_000)) {
      try r.apply(.raise(to: 150))
    }
    #expect(throws: ActionError.amountOutOfRange(.raise(to: 20_000), min: 200, max: 10_000)) {
      try r.apply(.raise(to: 20_000))
    }
    #expect(throws: ActionError.notLegal(.check)) { try r.apply(.check) }
    #expect(throws: ActionError.notLegal(.bet(to: 400))) { try r.apply(.bet(to: 400)) }
    #expect(r == snapshot)
  }

  @Test func actingOnClosedRoundThrows() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 1000]))
    try r.apply(.check)
    try r.apply(.check)
    #expect(r.isClosed)
    #expect(throws: ActionError.roundClosed) { try r.apply(.check) }
  }

  // MARK: Incomplete all-in

  @Test func shortAllInDoesNotReopenBettingForPlayerWhoAlreadyActed() throws {
    // Seats 0..2 postflop. Seat 1 bets 100, seat 2 calls, seat 0 (stack 150) all-in: +50 < 100.
    var r = try BettingRound.postflop(config: cfg6, button: 2, players: stacks([150, 1000, 1000]))
    #expect(r.toAct == 0)
    try r.apply(.check)
    try r.apply(.bet(to: 100))
    #expect(r.toAct == 2)
    try r.apply(.call)
    // Seat 0 already checked and faces 100: all-in for 150 is a raise of 50 (incomplete).
    #expect(r.toAct == 0)
    let a = try r.apply(.allIn)
    #expect(a.isIncompleteRaise && !a.isFullRaise && r.currentBet == 150 && r.lastRaiseSize == 100)
    // Seat 1 acted at 100: facing 50 more, cannot raise.
    let l1 = r.legalActions()!
    #expect(l1.seat == 1 && l1.toCall == 50 && l1.canCall)
    #expect(l1.raiseRange == nil && l1.allInTo == nil)
    try r.apply(.call)
    let l2 = r.legalActions()!
    #expect(l2.seat == 2 && l2.raiseRange == nil)
    try r.apply(.call)
    #expect(r.isClosed)
  }

  @Test func shortAllInStillAllowsPlayersWhoHaveNotActedToRaise() throws {
    // Preflop: UTG shoves 150 (incomplete over... raise of 50 on BB 100 is below min raise 100).
    var r = try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks([1000, 1000, 1000, 150, 1000, 1000])).round
    let a = try r.apply(.allIn)
    #expect(a.isIncompleteRaise && r.currentBet == 150 && r.lastRaiseSize == 100)
    // Seat 4 never acted: may raise to 250 (current bet + last full increment).
    #expect(r.toAct == 4 && r.legalActions()?.minRaiseTo == 250)
  }

  @Test func cumulativeShortAllInsAddUpToFullRaiseAndReopen() throws {
    // Seat 0 bets 100. Seat 1 all-in 150 (+50), seat 2 all-in 200 (+50 more): each is incomplete, but the bet
    // grew by 100 since seat 0 acted, a full raise, so seat 0 may raise again.
    var r = try BettingRound.postflop(config: cfg6, button: 2, players: stacks([1000, 150, 200]))
    try r.apply(.bet(to: 100))
    let b = try r.apply(.allIn)
    #expect(b.isIncompleteRaise)
    let c = try r.apply(.allIn)
    #expect(c.isIncompleteRaise && r.currentBet == 200 && r.lastRaiseSize == 100)
    let l = r.legalActions()!
    #expect(l.seat == 0 && l.toCall == 100 && l.raiseKind == .raise && l.minRaiseTo == 300)
  }

  // MARK: All-in for less

  @Test func allInForLessThanCallDoesNotChangeBetOrRaiseSize() throws {
    var r = try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks([1000, 1000, 1000, 1000, 40, 1000])).round
    try r.apply(.raise(to: 300))  // seat 3
    #expect(r.toAct == 4)
    let l = r.legalActions()!
    #expect(!l.canCall && l.callIsAllIn && l.callAmount == 40 && l.raiseRange == nil)
    let a = try r.apply(.allIn)
    #expect(a.chipsAdded == 40 && a.isAllIn && !a.isFullRaise && !a.isIncompleteRaise)
    #expect(r.currentBet == 300 && r.lastRaiseSize == 200)
    #expect(r.player(at: 4)?.status == .allIn)
  }

  // MARK: BB option and round closing

  @Test func bigBlindGetsOptionWhenEveryoneLimps() throws {
    var r = try preflop6()
    for _ in 0..<3 { try r.apply(.call) }  // seats 3, 4, 5
    try r.apply(.call)  // button (seat 0) limps
    try r.apply(.call)  // SB completes
    #expect(r.toAct == 2 && !r.isClosed)
    let l = r.legalActions()!
    #expect(l.canCheck && l.raiseKind == .raise && l.minRaiseTo == 200)
    try r.apply(.check)
    #expect(r.isClosed)
  }

  @Test func bigBlindMayRaiseHisOption() throws {
    var r = try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks([1000, 1000, 1000, 1000])).round
    try r.apply(.call)  // seat 3
    try r.apply(.call)  // button
    try r.apply(.call)  // SB
    try r.apply(.raise(to: 300))  // BB
    #expect(r.toAct == 3 && r.legalActions()?.toCall == 200)
  }

  @Test func roundClosesWhenAllCheck() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 1000, 1000]))
    try r.apply(.check)
    try r.apply(.check)
    #expect(!r.isClosed)
    try r.apply(.check)
    #expect(r.isClosed && r.toAct == nil)
  }

  @Test func raiseReopensActionForEveryoneAndClosesAfterCalls() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 1000, 1000]))
    try r.apply(.bet(to: 100))
    try r.apply(.raise(to: 300))
    try r.apply(.call)  // seat 0 calls 300? seat order 1,2,0
    #expect(r.toAct == 1)
    try r.apply(.call)
    #expect(r.isClosed && r.totalCommitted == 900)
  }

  @Test func foldToLastPlayerClosesRoundAndReportsWinner() throws {
    var r = try preflop6()
    for _ in 0..<5 { try r.apply(.fold) }
    #expect(r.isClosed && r.winnerByFold == 2)
    #expect(r.uncalledBet()?.seat == 2 && r.uncalledBet()?.amount == 50)
  }

  @Test func closesWhenOnlyOneActivePlayerRemainsAndHasMatched() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 300, 1000]))
    try r.apply(.bet(to: 100))  // seat 1
    try r.apply(.fold)  // seat 2
    try r.apply(.allIn)  // seat 0: all-in 1000, raise
    try r.apply(.allIn)  // seat 1 calls for less
    #expect(r.isClosed)
  }

  @Test func allInRaiseRunsOutWhenRemainingPlayerCannotAct() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([500, 500]))
    try r.apply(.bet(to: 100))
    try r.apply(.allIn)
    try r.apply(.call)
    #expect(r.isClosed)
    #expect(r.livePlayers.count == 2 && r.player(at: 0)?.status == .allIn)
  }

  @Test func uncalledBetIsTheExcessOverTheSecondHighestCommitment() throws {
    var r = try BettingRound.postflop(config: cfg6, button: 0, players: stacks([1000, 400]))
    try r.apply(.check)  // seat 1 acts first heads-up postflop
    try r.apply(.bet(to: 700))  // seat 0
    try r.apply(.allIn)  // seat 1 calls for less (400)
    #expect(r.isClosed)
    let u = r.uncalledBet()
    #expect(u?.seat == 0 && u?.amount == 300)
  }

  @Test func creationValidation() throws {
    #expect(throws: BettingRoundError.tooFewPlayers) {
      try BettingRound.postflop(config: cfg6, button: 0, players: stacks([100]))
    }
    #expect(throws: BettingRoundError.buttonNotSeated(5)) {
      try BettingRound.preflop(config: cfg6, button: 5, stacks: stacks([100, 100, 100]))
    }
    #expect(throws: BettingRoundError.duplicateSeat(0)) {
      try BettingRound.preflop(
        config: cfg6, button: 0, stacks: [SeatStack(seat: 0, stack: 5), SeatStack(seat: 0, stack: 5)])
    }
    #expect(throws: BettingRoundError.nonPositiveStack(seat: 1)) {
      try BettingRound.preflop(config: cfg6, button: 0, stacks: stacks([100, 0]))
    }
  }
}
