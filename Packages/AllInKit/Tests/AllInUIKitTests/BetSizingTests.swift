import PokerCore
import Testing

@testable import AllInUI

@Suite struct BetSizingTests {
  /// Hero owes 30 on a flop bet of 30 with 75 in the middle (that 30 included), stack 186.
  private var facingBet: LegalActions {
    LegalActions.compute(seat: 0, stack: 186, committed: 0, currentBet: 30, lastRaiseSize: 30, canRaise: true)
  }

  /// Unopened flop, nothing owed, big blind 2.
  private var unopened: LegalActions {
    LegalActions.compute(seat: 0, stack: 186, committed: 0, currentBet: 0, lastRaiseSize: 2, canRaise: true)
  }

  @Test func presetsFacingABet() throws {
    let legal = facingBet
    #expect(BetSizing.raiseTo(.half, legal: legal, potTotal: 75) == 83)
    #expect(BetSizing.raiseTo(.pot, legal: legal, potTotal: 75) == 135)
    #expect(BetSizing.raiseTo(.allIn, legal: legal, potTotal: 75) == 186)
    let range = try #require(legal.raiseRange)
    for preset in BetPreset.allCases {
      let size = try #require(BetSizing.raiseTo(preset, legal: legal, potTotal: 75))
      #expect(range.contains(size))
    }
  }

  @Test func presetsOnUnopenedFlop() throws {
    let legal = unopened
    #expect(BetSizing.raiseTo(.third, legal: legal, potTotal: 40) == 13)
    #expect(BetSizing.raiseTo(.pot, legal: legal, potTotal: 40) == 40)
    let tiny = try #require(BetSizing.raiseTo(.third, legal: legal, potTotal: 3))
    #expect(tiny >= 2)
  }

  @Test func defaultSize() {
    #expect(BetSizing.defaultRaiseTo(legal: unopened, potTotal: 40, bigBlind: 2) == 20)
    #expect(BetSizing.defaultRaiseTo(legal: facingBet, potTotal: 75, bigBlind: 2) == 90)
  }

  @Test func stepStaysInRange() throws {
    let legal = facingBet
    let range = try #require(legal.raiseRange)
    #expect(BetSizing.step(80, by: 1, legal: legal, bigBlind: 2) == 82)
    #expect(BetSizing.step(80, by: -1, legal: legal, bigBlind: 2) == 78)
    #expect(BetSizing.step(range.lowerBound, by: -5, legal: legal, bigBlind: 2) == range.lowerBound)
    #expect(BetSizing.step(range.upperBound, by: 5, legal: legal, bigBlind: 2) == range.upperBound)
  }

  @Test func clampRoundsToChipUnit() throws {
    let legal = LegalActions.compute(
      seat: 0, stack: 1000, committed: 0, currentBet: 0, lastRaiseSize: 50, canRaise: true, chipUnit: 25)
    #expect(BetSizing.clamp(137, legal: legal) == 125)
    #expect(BetSizing.clamp(10, legal: legal) == 50)
    #expect(BetSizing.clamp(5000, legal: legal) == 1000)
  }

  @Test func actionMapping() {
    let legal = facingBet
    #expect(BetSizing.action(raiseTo: 186, legal: legal) == .allIn)
    #expect(BetSizing.action(raiseTo: 90, legal: legal) == .raise(to: 90))
    #expect(BetSizing.action(raiseTo: 40, legal: legal) == nil)
    #expect(BetSizing.action(raiseTo: 500, legal: legal) == nil)
    #expect(BetSizing.action(raiseTo: 20, legal: unopened) == .bet(to: 20))
  }

  @Test func shortStackOnlyAllIn() {
    let legal = LegalActions.compute(
      seat: 0, stack: 18, committed: 0, currentBet: 30, lastRaiseSize: 30, canRaise: true)
    #expect(legal.raiseRange == nil)
    #expect(BetSizing.checkCallAction(legal) == .allIn)
    #expect(BetSizing.checkCallLabel(legal) == "Call all-in 18")
    #expect(BetSizing.raiseTo(.half, legal: legal, potTotal: 75) == legal.allInTo)
    #expect(BetSizing.clamp(40, legal: legal) == legal.allInTo)
  }

  @Test func checkAndCall() {
    #expect(BetSizing.checkCallAction(unopened) == .check)
    #expect(BetSizing.checkCallLabel(unopened) == "Check")
    #expect(BetSizing.checkCallAction(facingBet) == .call)
    #expect(BetSizing.checkCallLabel(facingBet) == "Call 30")
  }

  @Test func presetLabels() {
    #expect(BetPreset.allCases.map(\.label) == ["⅓", "½", "⅔", "Pot", "All-in"])
    #expect(BetPreset.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
  }
}
