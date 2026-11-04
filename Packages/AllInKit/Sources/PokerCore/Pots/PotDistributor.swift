public enum PotDistributionError: Error, Sendable, Equatable {
  /// No eligible seat of the pot has a showdown strength.
  case noContender(potIndex: Int)
}

/// What one pot paid out.
public struct PotAward: Sendable, Hashable {
  public let potIndex: Int
  public let winners: [Int]
  /// Chips per winning seat, odd chips included.
  public let shares: [Int: Int]
}

public struct PotDistribution: Sendable, Hashable {
  public let awards: [PotAward]
  /// Total won per seat across all pots (excludes uncalled returns).
  public let payouts: [Int: Int]
}

/// Awards each pot to its best eligible hand(s). Ties split evenly with integer chips; odd chips go one
/// each to the tied winners in order of seat left of the button (the first seat clockwise after it).
public enum PotDistributor {
  /// - Parameter strengths: showdown strength per seat; higher wins. A seat missing here (mucked or
  ///   not at showdown) cannot win.
  public static func distribute<Strength: Comparable>(
    pots: [Pot], strengths: [Int: Strength], button: Int
  ) throws -> PotDistribution {
    var awards: [PotAward] = []
    var payouts: [Int: Int] = [:]
    for (index, pot) in pots.enumerated() {
      let contenders = pot.eligibleSeats.filter { strengths[$0] != nil }
      guard let best = contenders.compactMap({ strengths[$0] }).max() else {
        throw PotDistributionError.noContender(potIndex: index)
      }
      let winners = contenders.filter { strengths[$0] == best }
        .sorted { order($0, button: button) < order($1, button: button) }
      let base = pot.amount / winners.count
      let odd = pot.amount % winners.count
      var shares: [Int: Int] = [:]
      for (i, seat) in winners.enumerated() {
        shares[seat] = base + (i < odd ? 1 : 0)
        payouts[seat, default: 0] += shares[seat]!
      }
      awards.append(PotAward(potIndex: index, winners: winners, shares: shares))
    }
    return PotDistribution(awards: awards, payouts: payouts)
  }

  /// Clockwise distance from the button: seats after the button first, the button itself last.
  static func order(_ seat: Int, button: Int) -> Int {
    seat > button ? seat - button : seat + 1_000_000 - button
  }
}
