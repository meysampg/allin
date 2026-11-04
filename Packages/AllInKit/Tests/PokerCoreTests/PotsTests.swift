import Testing

@testable import PokerCore

private func c(_ seat: Int, _ amount: Int, folded: Bool = false) -> PotContribution {
  PotContribution(seat: seat, amount: amount, folded: folded)
}

@Suite struct PotsTests {
  @Test func classicThreeWayAllInSidePots() {
    let r = PotCalculator.calculate([c(0, 50), c(1, 150), c(2, 300)])
    #expect(
      r.pots == [
        Pot(amount: 150, eligibleSeats: [0, 1, 2]),
        Pot(amount: 200, eligibleSeats: [1, 2]),
      ])
    #expect(r.returns == [PotReturn(seat: 2, amount: 150)])
  }

  @Test func threeWayWithCalledTop() {
    let r = PotCalculator.calculate([c(0, 50), c(1, 150), c(2, 150)])
    #expect(
      r.pots == [
        Pot(amount: 150, eligibleSeats: [0, 1, 2]),
        Pot(amount: 200, eligibleSeats: [1, 2]),
      ])
    #expect(r.returns.isEmpty)
  }

  @Test func foldedContributorIsDeadMoney() {
    let r = PotCalculator.calculate([c(0, 100), c(1, 40, folded: true), c(2, 100), c(3, 60, folded: true)])
    #expect(r.pots == [Pot(amount: 300, eligibleSeats: [0, 2])])
    #expect(r.returns.isEmpty)
  }

  @Test func foldedChipsSplitAcrossLevels() {
    let r = PotCalculator.calculate([c(0, 30), c(1, 100), c(2, 100), c(3, 50, folded: true)])
    #expect(
      r.pots == [
        Pot(amount: 120, eligibleSeats: [0, 1, 2]),
        Pot(amount: 160, eligibleSeats: [1, 2]),
      ])
  }

  @Test func uncalledBetReturned() {
    let r = PotCalculator.calculate([c(0, 100), c(1, 30, folded: true), c(2, 20, folded: true)])
    #expect(r.returns == [PotReturn(seat: 0, amount: 70)])
    #expect(r.pots == [Pot(amount: 80, eligibleSeats: [0])])
  }

  @Test func emptyAndZeroContributions() {
    #expect(PotCalculator.calculate([]).pots.isEmpty)
    #expect(PotCalculator.calculate([c(0, 0), c(1, 0)]).pots.isEmpty)
  }

  @Test func bestHandWinsEachPot() throws {
    let r = PotCalculator.calculate([c(0, 50), c(1, 150), c(2, 150)])
    // Seat 0 has the best hand: wins main only; seat 2 beats seat 1 for the side pot.
    let d = try PotDistributor.distribute(pots: r.pots, strengths: [0: 9, 1: 3, 2: 5], button: 0)
    #expect(d.payouts == [0: 150, 2: 200])
  }

  @Test func tieSplitsEvenly() throws {
    let pots = [Pot(amount: 100, eligibleSeats: [0, 1])]
    let d = try PotDistributor.distribute(pots: pots, strengths: [0: 5, 1: 5], button: 0)
    #expect(d.payouts == [0: 50, 1: 50])
  }

  @Test func oddChipGoesLeftOfButton() throws {
    let pots = [Pot(amount: 101, eligibleSeats: [1, 3, 5])]
    let s = [1: 7, 3: 7, 5: 7]
    // 101 / 3 = 33 rem 2: first two winners left of the button get 34.
    var d = try PotDistributor.distribute(pots: pots, strengths: s, button: 2)
    #expect(d.payouts == [3: 34, 5: 34, 1: 33])
    d = try PotDistributor.distribute(pots: pots, strengths: s, button: 5)
    #expect(d.payouts == [1: 34, 3: 34, 5: 33])
    d = try PotDistributor.distribute(pots: pots, strengths: s, button: 0)
    #expect(d.payouts == [1: 34, 3: 34, 5: 33])
  }

  @Test func multiWayTieAcrossPotsWithOddChips() throws {
    let r = PotCalculator.calculate([c(0, 33), c(1, 34), c(2, 34), c(3, 34), c(4, 1, folded: true)])
    let d = try PotDistributor.distribute(
      pots: r.pots, strengths: [0: 1, 1: 1, 2: 1, 3: 1], button: 0)
    // Main pot 133 over 4 seats: 33 each, odd chip to seat 1. Side pot 3 over seats 1-3: 1 each.
    #expect(d.payouts == [0: 33, 1: 35, 2: 34, 3: 34])
  }

  @Test func noContenderThrows() {
    #expect(throws: PotDistributionError.noContender(potIndex: 0)) {
      try PotDistributor.distribute(
        pots: [Pot(amount: 10, eligibleSeats: [1])], strengths: [Int: Int](), button: 0)
    }
  }
}
