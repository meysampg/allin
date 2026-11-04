import Testing

@testable import PokerCore

@Suite struct RulesLegalActionsTests {
  private func legal(
    stack: Int, committed: Int = 0, bet: Int, raise: Int = 100, canRaise: Bool = true, unit: Int = 1
  ) -> LegalActions {
    LegalActions.compute(
      seat: 0, stack: stack, committed: committed, currentBet: bet, lastRaiseSize: raise, canRaise: canRaise,
      chipUnit: unit)
  }

  @Test func openingBetRange() {
    let l = legal(stack: 1000, bet: 0)
    #expect(l.canCheck && !l.canCall && l.raiseKind == .bet)
    #expect(l.raiseRange == 100...1000 && l.allInTo == 1000)
  }

  @Test func facingBetMinRaiseIsLastFullIncrement() {
    // Bet 300 after a raise of 200 over 100: min raise-to is 300 + 200.
    let l = legal(stack: 2000, committed: 100, bet: 300, raise: 200)
    #expect(l.toCall == 200 && l.canCall && !l.canCheck && l.raiseKind == .raise)
    #expect(l.minRaiseTo == 500 && l.maxRaiseTo == 2100)
  }

  @Test func shortStackCanOnlyCallForLessViaAllIn() {
    let l = legal(stack: 60, bet: 100)
    #expect(!l.canCall && l.callIsAllIn && l.callAmount == 60)
    #expect(l.raiseRange == nil && l.allInTo == 60)
  }

  @Test func stackBetweenCallAndMinRaiseOffersOnlyAllInRaise() {
    let l = legal(stack: 150, bet: 100, raise: 100)  // min raise-to 200 > 150
    #expect(l.canCall && l.raiseRange == nil && l.allInTo == 150)
  }

  @Test func closedBettingForbidsRaiseAndAllInAboveCall() {
    let l = legal(stack: 1000, committed: 100, bet: 250, raise: 100, canRaise: false)
    #expect(l.canCall && l.raiseRange == nil && l.allInTo == nil)
    #expect(!l.isLegal(.allIn) && !l.isLegal(.raise(to: 600)))
  }

  @Test func validationRejectsIllegalAmountsAndKinds() {
    let l = legal(stack: 1000, committed: 100, bet: 300, raise: 200)
    #expect(throws: ActionError.amountOutOfRange(.raise(to: 400), min: 500, max: 1100)) {
      try l.validate(.raise(to: 400))
    }
    #expect(throws: ActionError.amountOutOfRange(.raise(to: 1200), min: 500, max: 1100)) {
      try l.validate(.raise(to: 1200))
    }
    #expect(throws: ActionError.notLegal(.bet(to: 600))) { try l.validate(.bet(to: 600)) }
    #expect(throws: ActionError.notLegal(.check)) { try l.validate(.check) }
    #expect(l.isLegal(.raise(to: 500)) && l.isLegal(.raise(to: 1100)) && l.isLegal(.fold) && l.isLegal(.call))
  }

  @Test func chipUnitAppliesExceptForAllIn() {
    let l = legal(stack: 990, bet: 0, raise: 100, unit: 25)
    #expect(!l.isLegal(.bet(to: 110)))
    #expect(l.isLegal(.bet(to: 125)) && l.isLegal(.bet(to: 990)))
  }

  @Test func betKindMismatchRejected() {
    #expect(!legal(stack: 500, bet: 0).isLegal(.raise(to: 200)))
  }
}
