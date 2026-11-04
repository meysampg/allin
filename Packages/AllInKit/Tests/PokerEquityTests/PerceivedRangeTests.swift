import PokerCore
import Testing

@testable import PokerEquity

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

private func entry(
  _ seat: Int, _ action: Action, to: Int, street: Street = .preflop, allIn: Bool = false
) -> ActionEntry {
  ActionEntry(street: street, seat: seat, action: action, chipsAdded: to, committedAfter: to, isAllIn: allIn)
}

/// Six handed, button 0 (seat 5 is the cutoff), hero in seat 0.
private func spot(
  hole: String = "AhAd", board: String = "Kd7s2c", street: Street = .flop, history: [ActionEntry]
) -> DecisionContext {
  let config = try! TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2)
  let seats = (0..<6).map { s in
    SeatView(
      seat: s, startingStack: 200, stack: 200, committedThisStreet: 0, totalContribution: 0, status: .active)
  }
  let legal = LegalActions.compute(
    seat: 0, stack: 200, committed: 0, currentBet: 0, lastRaiseSize: 2, canRaise: true)
  return DecisionContext(
    config: config, seat: 0, holeCards: cards(hole), board: cards(board), street: street, button: 0,
    smallBlindSeat: 1, bigBlindSeat: 2, seats: seats, pot: 20, history: history, legal: legal)
}

private let openFromCutoff = [entry(5, .raise(to: 6), to: 6)]

/// Share of the range weight on hands without a pair or better on `board`.
private func airShare(_ range: HandRange, board: String) -> Double {
  let table = BoardStrengthTable(board: cards(board))
  var air = 0.0
  var total = 0.0
  for combo in Combo.all {
    let w = Double(range[combo])
    guard w > 0, let v = table.value(of: combo) else { continue }
    total += w
    if v.category == .highCard { air += w }
  }
  return air / total
}

@Suite struct PerceivedRangeTests {
  @Test func flopBetRemovesAir() {
    var tables: [Int: BoardStrengthTable] = [:]
    let before = PerceivedRange.estimate(of: 5, in: spot(history: openFromCutoff), blur: 0, tables: &tables)
    let bet = openFromCutoff + [entry(5, .bet(to: 8), to: 8, street: .flop)]
    let after = PerceivedRange.estimate(of: 5, in: spot(history: bet), blur: 0, tables: &tables)
    #expect(airShare(after, board: "Kd7s2c") < airShare(before, board: "Kd7s2c"))
    #expect(after.totalWeight < before.totalWeight)
  }

  @Test func checkAndCallBehaveAsModelled() {
    var tables: [Int: BoardStrengthTable] = [:]
    let base = PerceivedRange.estimate(of: 5, in: spot(history: openFromCutoff), blur: 0, tables: &tables)
    let called = openFromCutoff + [entry(5, .call, to: 8, street: .flop)]
    let afterCall = PerceivedRange.estimate(of: 5, in: spot(history: called), blur: 0, tables: &tables)
    #expect(airShare(afterCall, board: "Kd7s2c") < airShare(base, board: "Kd7s2c"))
    let checked = openFromCutoff + [entry(5, .check, to: 0, street: .flop)]
    let afterCheck = PerceivedRange.estimate(of: 5, in: spot(history: checked), blur: 0, tables: &tables)
    #expect(airShare(afterCheck, board: "Kd7s2c") > airShare(base, board: "Kd7s2c"))
  }

  @Test func blurOneIsNearFull() {
    var tables: [Int: BoardStrengthTable] = [:]
    let bet = openFromCutoff + [entry(5, .bet(to: 8), to: 8, street: .flop)]
    let range = PerceivedRange.estimate(of: 5, in: spot(history: bet), blur: 1, tables: &tables)
    let live = range.nonZeroCombos
    // 5 dead cards (two hole, three board) leave C(47,2) combos.
    #expect(live.count == 47 * 46 / 2)
    let weights = live.map { range[$0] }
    #expect(weights.max()! - weights.min()! < 1e-6)
  }

  @Test func deadCardsHaveZeroWeight() {
    var tables: [Int: BoardStrengthTable] = [:]
    let bet = openFromCutoff + [entry(5, .bet(to: 8), to: 8, street: .flop)]
    let range = PerceivedRange.estimate(of: 5, in: spot(history: bet), blur: 0.3, tables: &tables)
    let dead = CardSet(cards("AhAdKd7s2c"))
    for combo in Combo.all where !combo.mask.isDisjoint(with: dead) { #expect(range[combo] == 0) }
    #expect(range.totalWeight > 0)
  }

  @Test func tablesAreCachedPerBoardPrefix() {
    var tables: [Int: BoardStrengthTable] = [:]
    let history =
      openFromCutoff + [
        entry(5, .bet(to: 8), to: 8, street: .flop), entry(5, .bet(to: 20), to: 20, street: .turn),
      ]
    let ctx = spot(board: "Kd7s2c9h", street: .turn, history: history)
    _ = PerceivedRange.estimate(of: 5, in: ctx, blur: 0.1, tables: &tables)
    #expect(Set(tables.keys) == [3, 4])
    #expect(tables[3]?.board == cards("Kd7s2c"))
    #expect(tables[4]?.board == cards("Kd7s2c9h"))
  }

  @Test func noPostflopActionsMatchesLineRange() {
    var tables: [Int: BoardStrengthTable] = [:]
    let ctx = spot(history: openFromCutoff)
    let range = PerceivedRange.estimate(of: 5, in: ctx, blur: 0, tables: &tables)
    #expect(range == PreflopLineRanges.range(of: 5, in: ctx))
    #expect(tables.isEmpty)
  }

  @Test func narrowingStaysDeterministicAndBounded() {
    var t1: [Int: BoardStrengthTable] = [:]
    var t2: [Int: BoardStrengthTable] = [:]
    let history =
      openFromCutoff + [
        entry(5, .bet(to: 8), to: 8, street: .flop), entry(3, .raise(to: 24), to: 24, street: .flop),
        entry(5, .call, to: 24, street: .flop),
      ]
    let ctx = spot(history: history)
    let a = PerceivedRange.estimate(of: 5, in: ctx, blur: 0.2, tables: &t1)
    let b = PerceivedRange.estimate(of: 5, in: ctx, blur: 0.2, tables: &t2)
    #expect(a == b)
    #expect(a.weights.allSatisfy { (0...1).contains($0) })
  }
}
