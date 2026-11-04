import PokerCore
import PokerEquity

public struct LuckResult: Codable, Sendable, Hashable {
  public let netChips: Int
  public let expectedNetChips: Double
  /// `net - expected`.
  public let luckChips: Double
  public let wasAllIn: Bool
  public let allInStreet: Street?
  /// Equity in the main pot at the all-in.
  public let heroEquity: Double?

  public init(
    netChips: Int, expectedNetChips: Double, luckChips: Double, wasAllIn: Bool, allInStreet: Street?,
    heroEquity: Double?
  ) {
    self.netChips = netChips
    self.expectedNetChips = expectedNetChips
    self.luckChips = luckChips
    self.wasAllIn = wasAllIn
    self.allInStreet = allInStreet
    self.heroEquity = heroEquity
  }
}

public enum LuckError: Error, Sendable, Equatable {
  case notHostLog
  case missingHoleCards(seat: Int)
}

public enum LuckCalculator {
  /// All-in adjusted result. The all-in point is the last `.actionTaken` when `.streetDealt` events follow it and
  /// the hand ends at showdown. `expected = Σ over the final pots of equity(hero among the pot's eligible hands,
  /// board at the all-in) · amount − heroContribution`. Two hands preflop use the equity table, a flop or later
  /// is exact, a multiway preflop is Monte Carlo with `samples`. Without an all-in, luck is 0 and expected = net.
  public static func luck(in log: EventLog, seat: Int, samples: Int = 20_000) throws -> LuckResult {
    var start: HandStart?
    var hasDeck = false
    var holes: [Int: [Card]] = [:]
    var result: HandResult?
    var pots: [PotInfo] = []
    var folded = Set<Int>()
    var board: [Card] = []
    var boardAtLastAction: [Card] = []
    var lastActionIndex: Int?
    var lastActionStreetBoard = 0
    for (i, logged) in log.events.enumerated() {
      switch logged.event {
      case .handStarted(let s): start = start ?? s
      case .deckSetup: hasDeck = true
      case .holeCardsDealt(let s, let cards): holes[s] = cards
      case .actionTaken(let taken):
        lastActionIndex = i
        boardAtLastAction = board
        lastActionStreetBoard = board.count
        if taken.action == .fold { folded.insert(taken.seat) }
      case .streetDealt(_, let cards): board += cards
      case .potsUpdated(let p): pots = p
      case .handEnded(let r): result = r
      default: break
      }
    }
    guard let start, hasDeck else { throw LuckError.notHostLog }
    guard start.seats.contains(where: { $0.seat == seat }), let heroCards = holes[seat], heroCards.count == 2
    else { throw LuckError.missingHoleCards(seat: seat) }
    guard let result else {
      return LuckResult(
        netChips: 0, expectedNetChips: 0, luckChips: 0, wasAllIn: false, allInStreet: nil, heroEquity: nil)
    }
    let net = result.netChips(of: seat) ?? 0
    let runout = lastActionIndex.map { index in
      log.events[(index + 1)...].contains { event in
        if case .streetDealt = event.event { return true }
        return false
      }
    }
    guard runout == true, result.reason == .showdown, !folded.contains(seat) else {
      return LuckResult(
        netChips: net, expectedNetChips: Double(net), luckChips: 0, wasAllIn: false, allInStreet: nil,
        heroEquity: nil)
    }

    let contribution = result.contributions.first { $0.seat == seat }?.amount ?? 0
    var seed: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in start.deckCommitment.utf8 {
      seed ^= UInt64(byte)
      seed = seed &* 0x0000_0100_0000_01b3
    }
    var cache: [[Int]: Double] = [:]
    var expected = -Double(contribution)
    var mainEquity: Double?
    for pot in pots {
      let eligible = pot.eligibleSeats.filter { !folded.contains($0) && holes[$0] != nil }.sorted()
      var equity = 0.0
      if eligible.contains(seat) {
        if let cached = cache[eligible] {
          equity = cached
        } else {
          equity = heroEquity(
            seat: seat, eligible: eligible, holes: holes, board: boardAtLastAction, samples: samples, seed: seed)
          cache[eligible] = equity
        }
      }
      if mainEquity == nil, eligible.contains(seat) { mainEquity = equity }
      expected += equity * Double(pot.amount)
    }
    let street: Street =
      switch lastActionStreetBoard {
      case 0: .preflop
      case 3: .flop
      default: .turn
      }
    return LuckResult(
      netChips: net, expectedNetChips: expected, luckChips: Double(net) - expected, wasAllIn: true,
      allInStreet: street, heroEquity: mainEquity)
  }

  private static func heroEquity(
    seat: Int, eligible: [Int], holes: [Int: [Card]], board: [Card], samples: Int, seed: UInt64
  ) -> Double {
    guard eligible.count > 1, let index = eligible.firstIndex(of: seat) else { return 1 }
    let hands = eligible.map { holes[$0]! }
    if board.isEmpty {
      if hands.count == 2 { return EquityCalculator.preflop(hands[index], hands[1 - index]).equity }
      var rng = SeededRNG(seed: seed)
      let ranges = hands.map { HandRange(combo: Combo($0[0], $0[1])) }
      let results = EquityCalculator.monteCarlo(ranges, board: [], samples: samples, using: &rng)
      return results.isEmpty ? 1 / Double(hands.count) : results[index].equity
    }
    return EquityCalculator.exact(hands, board: board)[index].equity
  }
}
