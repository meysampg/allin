/// One player's total chips put into the pot during a hand.
public struct PotContribution: Sendable, Hashable {
  public let seat: Int
  public let amount: Int
  public let folded: Bool

  public init(seat: Int, amount: Int, folded: Bool) {
    self.seat = seat
    self.amount = amount
    self.folded = folded
  }
}

/// A main or side pot: its chips and the seats that may win it (never a folded seat).
public struct Pot: Sendable, Hashable {
  public let amount: Int
  /// Ascending seat indices.
  public let eligibleSeats: [Int]

  public init(amount: Int, eligibleSeats: [Int]) {
    self.amount = amount
    self.eligibleSeats = eligibleSeats
  }
}

/// Chips handed back to a seat because nobody matched them (uncalled bet).
public struct PotReturn: Sendable, Hashable {
  public let seat: Int
  public let amount: Int

  public init(seat: Int, amount: Int) {
    self.seat = seat
    self.amount = amount
  }
}

public struct PotBreakdown: Sendable, Hashable {
  /// Main pot first, then side pots in increasing contribution level.
  public let pots: [Pot]
  public let returns: [PotReturn]

  public init(pots: [Pot], returns: [PotReturn]) {
    self.pots = pots
    self.returns = returns
  }

  public var potTotal: Int { pots.reduce(0) { $0 + $1.amount } }
  public var returnedTotal: Int { returns.reduce(0) { $0 + $1.amount } }
}

/// Builds the main pot and side pots from per-seat total contributions. Folded chips stay in as dead
/// money but those seats are never eligible. The part of the biggest contribution that no other seat
/// matched is returned to its owner.
public enum PotCalculator {
  public static func calculate(_ contributions: [PotContribution]) -> PotBreakdown {
    var amounts: [Int: Int] = [:]  // seat -> chips still in play
    var folded: [Int: Bool] = [:]
    for c in contributions where c.amount > 0 {
      amounts[c.seat, default: 0] += c.amount
      folded[c.seat] = (folded[c.seat] ?? true) && c.folded
    }
    var returns: [PotReturn] = []

    // Uncalled bet: the top contribution minus the second highest (folded chips count as matching).
    let sortedAmounts = amounts.values.sorted(by: >)
    if let top = sortedAmounts.first {
      let second = sortedAmounts.count > 1 ? sortedAmounts[1] : 0
      if top > second, let seat = amounts.first(where: { $0.value == top })?.key {
        returns.append(PotReturn(seat: seat, amount: top - second))
        amounts[seat] = second
        if second == 0 { amounts[seat] = nil }
      }
    }

    let liveLevels = Set(amounts.filter { folded[$0.key] == false }.map(\.value)).sorted()
    guard let topLive = liveLevels.last else {
      // Nobody can win: give everything back.
      for (seat, amount) in amounts { returns.append(PotReturn(seat: seat, amount: amount)) }
      return PotBreakdown(pots: [], returns: returns.sorted { $0.seat < $1.seat })
    }

    var pots: [Pot] = []
    var previous = 0
    for level in liveLevels {
      let isLast = level == topLive
      var amount = 0
      for value in amounts.values {
        // The last pot also absorbs any folded chips above the top live level.
        let upper = isLast ? value : min(value, level)
        amount += max(0, upper - min(value, previous))
      }
      let eligible = amounts.filter { folded[$0.key] == false && $0.value >= level }.keys.sorted()
      pots.append(Pot(amount: amount, eligibleSeats: eligible))
      previous = level
    }
    return PotBreakdown(pots: pots, returns: returns.sorted { $0.seat < $1.seat })
  }
}
