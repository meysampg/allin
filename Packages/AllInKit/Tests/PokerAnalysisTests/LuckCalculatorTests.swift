import PokerCore
import PokerEquity
import Testing

@testable import PokerAnalysis

@Suite struct LuckCalculatorTests {
  @Test func noAllInNoLuck() throws {
    let log = try scriptedLog(
      seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"], board: riverBoard,
      actions: checkedToRiver + [.bet(to: 20), .call])
    let luck = try LuckCalculator.luck(in: log, seat: 1)
    #expect(!luck.wasAllIn)
    #expect(luck.allInStreet == nil)
    #expect(luck.luckChips == 0)
    #expect(luck.expectedNetChips == Double(luck.netChips))
    #expect(luck.netChips == 40)
  }

  @Test func foldedHandHasNoLuck() throws {
    let log = try scriptedLog(
      seatCount: 3, button: 0, stacks: [200, 200, 200], holes: [0: "Kd Qc", 1: "Ah Qh", 2: "2c 3d"],
      board: riverBoard, actions: [.raise(to: 6), .call, .call, .allIn, .fold, .call])
    // Seat 2 folded on the flop; the others ran it out, but the folded seat has no luck.
    let luck = try LuckCalculator.luck(in: log, seat: 2)
    #expect(!luck.wasAllIn)
    #expect(luck.luckChips == 0)
  }

  @Test func preflopAllInUsesEquity() throws {
    // AA vs KK; the board gives KK a set.
    let log = try scriptedLog(
      seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Ah As", 1: "Kh Kd"], board: "2c 7d Ks 4h 9c",
      actions: [.allIn, .call])
    let luck = try LuckCalculator.luck(in: log, seat: 0)
    #expect(luck.wasAllIn)
    #expect(luck.allInStreet == .preflop)
    #expect(luck.netChips == -200)
    let expected = 0.82 * 400 - 200
    #expect(abs(luck.expectedNetChips - expected) < 0.005 * 400, "expected \(luck.expectedNetChips)")
    #expect(abs(luck.luckChips - (Double(luck.netChips) - luck.expectedNetChips)) < 1e-9)
    #expect(luck.luckChips < -300)
    let equity = try #require(luck.heroEquity)
    #expect(abs(equity - 0.82) < 0.01)
    // The villain's side of the same hand sees the mirror image.
    let villain = try LuckCalculator.luck(in: log, seat: 1)
    #expect(abs(villain.luckChips + luck.luckChips) < 1e-9)
  }

  @Test func flopAllInExact() throws {
    let log = try scriptedLog(
      seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"], board: riverBoard,
      actions: [.raise(to: 6), .call, .allIn, .call])
    let luck = try LuckCalculator.luck(in: log, seat: 1)
    #expect(luck.allInStreet == .flop)
    let exact = EquityCalculator.exact([cards("Ah Qh"), cards("Kd Qc")], board: cards("2h 7h Kh"))[0].equity
    #expect(abs(luck.expectedNetChips - (exact * 400 - 200)) < 1e-9)
    #expect(luck.heroEquity == exact)
    #expect(luck.netChips == 200)
  }

  @Test func sidePotEligibility() throws {
    // Seat 2 has only 50: a three-way main pot of 150 and a side pot of 300 between seats 0 and 1.
    let log = try scriptedLog(
      seatCount: 3, button: 0, stacks: [200, 200, 50], holes: [0: "Ah Kh", 1: "Qd Qc", 2: "9s 8s"],
      board: "2h 7h Kd 3c 4d", actions: [.raise(to: 10), .call, .call, .allIn, .allIn, .call])
    let luck = try LuckCalculator.luck(in: log, seat: 0)
    #expect(luck.allInStreet == .flop)
    let flop = cards("2h 7h Kd")
    let three = EquityCalculator.exact([cards("Ah Kh"), cards("Qd Qc"), cards("9s 8s")], board: flop)[0].equity
    let two = EquityCalculator.exact([cards("Ah Kh"), cards("Qd Qc")], board: flop)[0].equity
    let expected = three * 150 + two * 300 - 200
    #expect(abs(luck.expectedNetChips - expected) < 1e-9)
    #expect(luck.heroEquity == three)
    // The short stack can only win the main pot.
    let short = try LuckCalculator.luck(in: log, seat: 2)
    let shortEquity = EquityCalculator.exact([cards("Ah Kh"), cards("Qd Qc"), cards("9s 8s")], board: flop)[2].equity
    #expect(abs(short.expectedNetChips - (shortEquity * 150 - 50)) < 1e-9)
  }

  @Test func seatLogThrows() throws {
    let log = try scriptedLog(
      seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Ah As", 1: "Kh Kd"], board: "2c 7d Ks 4h 9c",
      actions: [.allIn, .call])
    #expect(throws: LuckError.notHostLog) { try LuckCalculator.luck(in: log.view(for: .seat(0)), seat: 0) }
    #expect(throws: LuckError.missingHoleCards(seat: 7)) { try LuckCalculator.luck(in: log, seat: 7) }
  }
}
