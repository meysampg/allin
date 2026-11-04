import PokerCore
import Testing

@testable import PokerEquity

private func config(seats: Int = 6) -> TableConfig {
  try! TableConfig(seatCount: seats, smallBlind: 1, bigBlind: 2)
}

private func entry(
  _ seat: Int, _ action: Action, to: Int, added: Int? = nil, street: Street = .preflop, allIn: Bool = false
) -> ActionEntry {
  ActionEntry(
    street: street, seat: seat, action: action, chipsAdded: added ?? to, committedAfter: to, isAllIn: allIn)
}

/// Six handed, button 0, SB 1, BB 2, seats 3,4,5 = early, middle, cutoff... (button 0: CO is 5).
private func context(
  hero: Int, cards: String = "AhKh", board: String = "", street: Street = .preflop, history: [ActionEntry],
  toCall: Int = 0, pot: Int = 3, seatCount: Int = 6, button: Int = 0, stacks: [Int: Int] = [:],
  folded: Set<Int> = []
) -> DecisionContext {
  let seats = (0..<seatCount).map { s in
    SeatView(
      seat: s, startingStack: 200, stack: stacks[s] ?? 200, committedThisStreet: 0, totalContribution: 0,
      status: folded.contains(s) ? .folded : .active)
  }
  let legal = LegalActions.compute(
    seat: hero, stack: stacks[hero] ?? 200, committed: 0, currentBet: toCall, lastRaiseSize: 2, canRaise: true)
  let sb = seatCount == 2 ? button : (button + 1) % seatCount
  let bb = seatCount == 2 ? (button + 1) % seatCount : (button + 2) % seatCount
  return DecisionContext(
    config: config(seats: seatCount), seat: hero, holeCards: try! Card.parseList(cards),
    board: try! Card.parseList(board), street: street, button: button, smallBlindSeat: sb, bigBlindSeat: bb,
    seats: seats, pot: pot, history: history, legal: legal)
}

@Suite struct TablePositionTests {
  @Test func twoSeats() {
    #expect(TablePosition.of(seat: 3, button: 3, seats: [3, 7]) == .button)
    #expect(TablePosition.of(seat: 7, button: 3, seats: [3, 7]) == .bigBlind)
  }

  @Test func threeSeats() {
    let seats = [0, 1, 2]
    #expect(TablePosition.of(seat: 0, button: 0, seats: seats) == .button)
    #expect(TablePosition.of(seat: 1, button: 0, seats: seats) == .smallBlind)
    #expect(TablePosition.of(seat: 2, button: 0, seats: seats) == .bigBlind)
  }

  @Test func sixSeats() {
    let seats = Array(0..<6)
    let expected: [TablePosition] = [.button, .smallBlind, .bigBlind, .early, .middle, .cutoff]
    for s in seats { #expect(TablePosition.of(seat: s, button: 0, seats: seats) == expected[s]) }
    // Wrap-around with the button at seat 4.
    #expect(TablePosition.of(seat: 3, button: 4, seats: seats) == .cutoff)
    #expect(TablePosition.of(seat: 5, button: 4, seats: seats) == .smallBlind)
  }

  @Test func nineSeats() {
    let seats = Array(0..<9)
    let expected: [TablePosition] = [
      .button, .smallBlind, .bigBlind, .early, .early, .early, .middle, .middle, .cutoff,
    ]
    for s in seats { #expect(TablePosition.of(seat: s, button: 0, seats: seats) == expected[s]) }
  }

  @Test func sparseSeats() {
    let seats = [1, 4, 6, 8]
    #expect(TablePosition.of(seat: 8, button: 1, seats: seats) == .cutoff)
    #expect(TablePosition.of(seat: 6, button: 1, seats: seats) == .bigBlind)
  }
}

@Suite struct SpotFeaturesTests {
  @Test func unopened() {
    let ctx = context(hero: 3, history: [], toCall: 2)
    let f = SpotFeatures(ctx)
    #expect(f.preflop.situation == .unopened)
    #expect(f.preflop.raises == 0 && f.preflop.limpers == 0)
    #expect(f.position == .early)
    #expect(!f.isHeadsUp)
    #expect(f.liveOpponents == [0, 1, 2, 4, 5])
    #expect(f.facingBet)
    #expect(f.preflopAggressor == nil)
    #expect(f.effectiveStack == 200)
    #expect(f.spr == Double(200) / 3)
    #expect(f.lastAggressorPreviousStreet == nil && !f.heroBetPreviousStreet)
  }

  @Test func limped() {
    let h = [entry(3, .call, to: 2), entry(4, .call, to: 2)]
    let f = SpotFeatures(context(hero: 5, history: h, toCall: 2, pot: 7))
    #expect(f.preflop.situation == .limped)
    #expect(f.preflop.limpers == 2)
    #expect(f.preflop.raises == 0)
  }

  @Test func openWithCallers() {
    let h = [entry(3, .fold, to: 0), entry(4, .raise(to: 6), to: 6), entry(5, .call, to: 6)]
    let f = SpotFeatures(context(hero: 0, history: h, toCall: 6, pot: 15))
    #expect(f.preflop.situation == .facingOpen)
    #expect(f.preflop.raises == 1)
    #expect(f.preflop.opener == 4 && f.preflop.lastRaiser == 4)
    #expect(f.preflop.lastRaiseTo == 6)
    #expect(f.preflop.callersOfLastRaise == 1)
    #expect(f.preflopAggressor == 4)
    #expect(f.position == .button)
  }

  @Test func threeBetAndFourBet() {
    let open = entry(3, .raise(to: 6), to: 6)
    let three = entry(0, .raise(to: 20), to: 20)
    let heroOpened = SpotFeatures(context(hero: 3, history: [open, three], toCall: 14, pot: 29))
    #expect(heroOpened.preflop.situation == .facingThreeBet)
    #expect(heroOpened.preflop.heroRaises == 1)
    #expect(heroOpened.preflop.lastRaiseTo == 20)

    let four = entry(3, .raise(to: 50), to: 50)
    let facingFour = SpotFeatures(context(hero: 0, history: [open, three, four], toCall: 30, pot: 79))
    #expect(facingFour.preflop.situation == .facingFourBetPlus)
    #expect(facingFour.preflop.raises == 3)
    #expect(facingFour.preflop.callersOfLastRaise == 0)
    #expect(facingFour.preflop.heroRaises == 1)
  }

  @Test func shortAllInIsNotARaiseButBigOneIs() {
    // All-in for 1 (less than the big blind) is a call-like action; all-in to 30 is a raise.
    let short = entry(3, .allIn, to: 2, added: 2, allIn: true)
    let f = SpotFeatures(context(hero: 4, history: [short], toCall: 2))
    #expect(f.preflop.raises == 0)
    #expect(f.preflop.limpers == 1)

    let big = entry(3, .allIn, to: 30, allIn: true)
    let g = SpotFeatures(context(hero: 4, history: [big], toCall: 30))
    #expect(g.preflop.raises == 1)
    #expect(g.preflop.situation == .facingOpen)
    #expect(g.preflop.lastRaiseTo == 30)

    // An all-in below the current raise level is a call, not a re-raise.
    let open = entry(3, .raise(to: 10), to: 10)
    let under = entry(4, .allIn, to: 8, allIn: true)
    let h = SpotFeatures(context(hero: 5, history: [open, under], toCall: 10))
    #expect(h.preflop.raises == 1)
    #expect(h.preflop.callersOfLastRaise == 1)
  }

  @Test func headsUpAndInPosition() {
    let ctx = context(hero: 0, street: .flop, history: [], seatCount: 2, button: 0)
    let f = SpotFeatures(ctx)
    #expect(f.isHeadsUp)
    #expect(f.position == .button)
    #expect(f.isInPosition)
    let bb = SpotFeatures(context(hero: 1, street: .flop, history: [], seatCount: 2, button: 0))
    #expect(!bb.isInPosition)
    #expect(bb.position == .bigBlind)
  }

  @Test func multiwayPositionIgnoresFoldedSeats() {
    let early = context(hero: 3, street: .flop, history: [], folded: [0, 5])
    #expect(!SpotFeatures(early).isInPosition)
    let late = context(hero: 5, street: .flop, history: [], folded: [0])
    #expect(SpotFeatures(late).isInPosition)
    let afterButtonFolds = context(hero: 4, street: .flop, history: [], folded: [0, 5])
    #expect(SpotFeatures(afterButtonFolds).isInPosition)
  }

  @Test func postflopStreetHistory() {
    let pre = [entry(3, .raise(to: 6), to: 6), entry(0, .call, to: 6)]
    let flop = [
      entry(3, .bet(to: 8), to: 8, street: .flop), entry(0, .raise(to: 24), to: 24, street: .flop),
      entry(3, .call, to: 24, added: 16, street: .flop),
    ]
    let turn = [entry(3, .check, to: 0, added: 0, street: .turn)]
    let ctx = context(
      hero: 0, board: "2c7d9hTs", street: .turn, history: pre + flop + turn, toCall: 0, pot: 57,
      stacks: [0: 150, 3: 90], folded: [1, 2, 4, 5])
    let f = SpotFeatures(ctx)
    #expect(f.preflop.raises == 1)
    #expect(f.preflopAggressor == 3)
    #expect(f.lastAggressorPreviousStreet == 0)
    #expect(f.heroBetPreviousStreet)
    #expect(f.betsThisStreet == 0)
    #expect(!f.facingBet)
    #expect(f.liveOpponents == [3])
    #expect(f.effectiveStack == 90)
    #expect(f.isInPosition)
    #expect(abs(f.spr - 90.0 / 57.0) < 1e-9)
    let flopCtx = context(
      hero: 0, board: "2c7d9h", street: .flop, history: pre + flop, toCall: 0, pot: 57, folded: [1, 2, 4, 5])
    #expect(SpotFeatures(flopCtx).betsThisStreet == 2)
    #expect(SpotFeatures(flopCtx).lastAggressorPreviousStreet == 3)
    #expect(!SpotFeatures(flopCtx).heroBetPreviousStreet)
  }
}

@Suite struct PreflopLineRangesTests {
  private func total(_ r: HandRange) -> Double { r.totalWeight }

  @Test func openerRangeUsesPosition() {
    let h = [entry(3, .raise(to: 6), to: 6)]
    let ctx = context(hero: 0, cards: "2c3d", history: h, toCall: 6, pot: 9)
    let r = PreflopLineRanges.range(of: 3, in: ctx)
    // Early position opens the top 15%, minus combos blocked by the hero's 2c3d.
    let expected = HandRange.top(0.15).removing(CardSet(ctx.holeCards))
    #expect(r == expected)
    #expect(abs(total(HandRange.top(0.15)) - 0.15 * 1326) < 0.01)
  }

  @Test func buttonOpenIsWiderThanEarly() {
    let early = context(hero: 1, cards: "2c3d", history: [entry(3, .raise(to: 6), to: 6)], toCall: 6)
    let button = context(hero: 4, cards: "2c3d", history: [entry(0, .raise(to: 6), to: 6)], toCall: 6)
    #expect(total(PreflopLineRanges.range(of: 0, in: button)) > total(PreflopLineRanges.range(of: 3, in: early)))
  }

  @Test func headsUpButtonOpen() {
    let ctx = context(hero: 1, cards: "2c3d", history: [entry(0, .raise(to: 5), to: 5)], toCall: 3, seatCount: 2)
    let r = PreflopLineRanges.range(of: 0, in: ctx)
    #expect(r == HandRange.top(0.80).removing(CardSet(ctx.holeCards)))
  }

  @Test func limpAndCall() {
    let h = [
      entry(3, .call, to: 2), entry(4, .raise(to: 8), to: 8), entry(5, .call, to: 8),
    ]
    let ctx = context(hero: 0, cards: "2c3d", history: h, toCall: 8, pot: 20)
    let dead = CardSet(ctx.holeCards)
    #expect(PreflopLineRanges.range(of: 3, in: ctx) == HandRange.band(from: 0.08, to: 0.55).removing(dead))
    #expect(PreflopLineRanges.range(of: 4, in: ctx) == HandRange.top(0.19).removing(dead))
    #expect(PreflopLineRanges.range(of: 5, in: ctx) == HandRange.band(from: 0.04, to: 0.30).removing(dead))
  }

  @Test func threeBetFourBetAndCallOfThreeBet() {
    let h = [
      entry(3, .raise(to: 6), to: 6), entry(4, .raise(to: 20), to: 20), entry(3, .call, to: 20, added: 14),
      entry(5, .raise(to: 60), to: 60),
    ]
    let ctx = context(hero: 0, cards: "2c3d", history: h, toCall: 60, pot: 100)
    let dead = CardSet(ctx.holeCards)
    #expect(PreflopLineRanges.range(of: 4, in: ctx) == HandRange.top(0.07).removing(dead))
    #expect(PreflopLineRanges.range(of: 3, in: ctx) == HandRange.band(from: 0.03, to: 0.14).removing(dead))
    #expect(PreflopLineRanges.range(of: 5, in: ctx) == HandRange.top(0.035).removing(dead))
  }

  @Test func bigAllInUsesAllInRange() {
    let h = [entry(3, .allIn, to: 150, added: 150, allIn: true)]
    let ctx = context(hero: 0, cards: "2c3d", history: h, toCall: 150, pot: 153)
    #expect(PreflopLineRanges.range(of: 3, in: ctx) == HandRange.top(0.06).removing(CardSet(ctx.holeCards)))
  }

  @Test func blindsAndSilentSeatsAreFullMinusDead() {
    let ctx = context(hero: 3, cards: "AhKh", board: "2c7d9s", street: .flop, history: [entry(0, .call, to: 2)])
    let dead = CardSet(ctx.holeCards + ctx.board)
    #expect(PreflopLineRanges.range(of: 2, in: ctx) == HandRange.full.removing(dead))
    let r = PreflopLineRanges.range(of: 2, in: ctx)
    #expect(r[try! Combo("AhKd")] == 0)
    #expect(r[try! Combo("2c2d")] == 0)
    #expect(r[try! Combo("QsQd")] == 1)
  }
}
