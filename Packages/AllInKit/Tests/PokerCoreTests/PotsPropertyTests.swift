import Testing

@testable import PokerCore

@Suite struct PotsPropertyTests {
  /// Naive reference: peel chips off in layers, one seat-level at a time, awarding each layer directly.
  private static func reference(
    contributions: [PotContribution], strengths: [Int: Int], button: Int
  ) -> (payouts: [Int: Int], returned: [Int: Int]) {
    var remaining = Dictionary(uniqueKeysWithValues: contributions.map { ($0.seat, $0.amount) })
    let folded = Dictionary(uniqueKeysWithValues: contributions.map { ($0.seat, $0.folded) })
    var payouts: [Int: Int] = [:]
    var returned: [Int: Int] = [:]
    while true {
      let active = remaining.filter { $0.value > 0 }
      if active.isEmpty { break }
      let live = active.keys.filter { folded[$0] == false }
      if active.count == 1 || live.isEmpty {
        for (s, v) in active { returned[s, default: 0] += v; remaining[s] = 0 }
        break
      }
      // Layer height: smallest remaining among live seats.
      let height = live.map { remaining[$0]! }.min()!
      // Does any seat other than a single top contributor reach the layer? Check uncalled excess first.
      let sorted = active.values.sorted(by: >)
      if sorted[0] > sorted[1] {
        let seat = active.first { $0.value == sorted[0] }!.key
        let excess = sorted[0] - sorted[1]
        returned[seat, default: 0] += excess
        remaining[seat]! -= excess
        continue
      }
      var pot = 0
      for (s, v) in active {
        let take = min(v, height)
        pot += take
        remaining[s]! -= take
      }
      // Folded chips above the top live level also join this (final) layer.
      if live.allSatisfy({ remaining[$0]! == 0 }) {
        for (s, v) in remaining where v > 0 { pot += v; remaining[s] = 0 }
      }
      let eligible = live.filter { active[$0]! >= height }
      let best = eligible.map { strengths[$0]! }.max()!
      let winners = eligible.filter { strengths[$0] == best }.sorted {
        PotDistributor.order($0, button: button) < PotDistributor.order($1, button: button)
      }
      for (i, w) in winners.enumerated() {
        payouts[w, default: 0] += pot / winners.count + (i < pot % winners.count ? 1 : 0)
      }
    }
    return (payouts, returned)
  }

  @Test func randomConfigurationsAgreeWithReferenceAndConserveChips() throws {
    var rng = SeededRNG(seed: 0xA11_14)
    for _ in 0..<5000 {
      let n = Int.random(in: 2...9, using: &rng)
      var seats = Array(0..<10)
      seats.shuffle(using: &rng)
      let chosen = Array(seats.prefix(n))
      var contributions: [PotContribution] = []
      for seat in chosen {
        let amount = Int.random(in: 0...3, using: &rng) == 0 ? 0 : Int.random(in: 1...200, using: &rng)
        contributions.append(
          PotContribution(seat: seat, amount: amount, folded: Bool.random(using: &rng)))
      }
      // At least one live seat with chips, as in a real hand.
      if !contributions.contains(where: { !$0.folded && $0.amount > 0 }) {
        contributions[0] = PotContribution(seat: chosen[0], amount: max(1, contributions[0].amount), folded: false)
      }
      let total = contributions.reduce(0) { $0 + $1.amount }
      // Few distinct strengths so ties are common.
      var strengths: [Int: Int] = [:]
      for s in chosen { strengths[s] = Int.random(in: 0...3, using: &rng) }
      let button = Int.random(in: 0..<10, using: &rng)

      let breakdown = PotCalculator.calculate(contributions)
      let dist = try PotDistributor.distribute(pots: breakdown.pots, strengths: strengths, button: button)
      var actual = dist.payouts
      var actualReturn: [Int: Int] = [:]
      for r in breakdown.returns { actualReturn[r.seat, default: 0] += r.amount }

      #expect(dist.payouts.values.reduce(0, +) + breakdown.returnedTotal == total)
      #expect(breakdown.potTotal + breakdown.returnedTotal == total)
      for pot in breakdown.pots {
        for seat in pot.eligibleSeats {
          #expect(contributions.first { $0.seat == seat }?.folded == false)
        }
      }

      let ref = Self.reference(contributions: contributions, strengths: strengths, button: button)
      actual = actual.filter { $0.value > 0 }
      #expect(actual == ref.payouts.filter { $0.value > 0 })
      #expect(actualReturn == ref.returned.filter { $0.value > 0 })
    }
  }
}
