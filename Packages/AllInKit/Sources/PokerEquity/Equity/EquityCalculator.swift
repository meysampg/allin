import PokerCore

/// Equity engine: exact enumeration, seeded Monte Carlo (sync, parallel, progressive) and the bots' fast path.
///
/// Documented deviation from PLAN 1.7: hand vs a full range on the flop is exact in tens of milliseconds (not 5 ms,
/// which only holds for narrow ranges or hand vs hand). Live UI uses Monte Carlo or `stream` for that case.
public enum EquityCalculator {
  /// Known hands (2...9), exact over every remaining board. Preflop heads-up enumerates 1,712,304 boards.
  public static func exact(_ hands: [[Card]], board: [Card], dead: CardSet = CardSet()) -> [EquityResult] {
    precondition((2...9).contains(hands.count), "Equity needs 2 to 9 hands")
    precondition(hands.allSatisfy { $0.count == 2 }, "Every hand needs 2 cards")
    precondition(board.count <= 5, "At most 5 board cards")
    let masks = hands.map { CardSet($0).bits }
    let boardMask = CardSet(board).bits
    var used = boardMask | dead.bits
    for m in masks {
      precondition(m.nonzeroBitCount == 2 && used & m == 0, "Cards must be distinct")
      used |= m
    }
    let n = masks.count
    let remaining = remainingBits(excluding: used)
    var tally = EquityTally(players: n)
    var raws = [UInt16](repeating: 0, count: n)
    masks.withUnsafeBufferPointer { hm in
      remaining.withUnsafeBufferPointer { bits in
        raws.withUnsafeMutableBufferPointer { rb in
          forEachRunout(bits, k: 5 - board.count) { runout in
            let common = boardMask | runout
            for i in 0..<n {
              rb[i] = HandEvaluator.evaluate(CardSet(bits: hm[i] | common)).rawValue
            }
            tally.record(raws: UnsafeBufferPointer(rb), weight: 1)
          }
        }
      }
    }
    return tally.results(isExact: true)
  }

  /// Exact: every remaining board × every live villain combo (weighted), with card removal.
  /// An empty or dead range returns equity 1 (nothing to beat).
  public static func exact(hero: [Card], vs range: HandRange, board: [Card], dead: CardSet = CardSet())
    -> EquityResult
  {
    precondition(hero.count == 2, "Hero needs 2 cards")
    precondition(board.count <= 5, "At most 5 board cards")
    let heroMask = CardSet(hero).bits
    let boardMask = CardSet(board).bits
    let used = heroMask | boardMask | dead.bits
    precondition(heroMask.nonzeroBitCount == 2 && heroMask & (boardMask | dead.bits) == 0, "Cards must be distinct")
    let table = ComboMasks.table
    var liveMasks: [UInt64] = []
    var liveWeights: [Double] = []
    for i in 0..<1326 where range.weights[i] > 0 && table[i] & used == 0 {
      liveMasks.append(table[i])
      liveWeights.append(Double(range.weights[i]))
    }
    guard !liveMasks.isEmpty else { return EquityResult(win: 1, tie: 0, equity: 1, samples: 0, isExact: true) }
    let remaining = remainingBits(excluding: used)
    var tally = EquityTally(players: 1)
    var win = 0.0
    var tie = 0.0
    var share = 0.0
    var total = 0.0
    var samples = 0
    liveMasks.withUnsafeBufferPointer { vm in
      liveWeights.withUnsafeBufferPointer { vw in
        remaining.withUnsafeBufferPointer { bits in
          forEachRunout(bits, k: 5 - board.count) { runout in
            let common = boardMask | runout
            let heroRaw = HandEvaluator.evaluate(CardSet(bits: heroMask | common)).rawValue
            for j in 0..<vm.count where vm[j] & runout == 0 {
              let w = vw[j]
              let villain = HandEvaluator.evaluate(CardSet(bits: vm[j] | common)).rawValue
              total += w
              samples += 1
              if heroRaw < villain {
                win += w
                share += w
              } else if heroRaw == villain {
                tie += w
                share += 0.5 * w
              }
            }
          }
        }
      }
    }
    tally.win[0] = win
    tally.tie[0] = tie
    tally.share[0] = share
    tally.total = total
    tally.samples = samples
    return tally.result(player: 0, isExact: true)
  }

  /// Bots' fast path (pure, deterministic): river → exact vs range; otherwise MC with SeededRNG(seed).
  /// Multiple villains: joint MC. An empty or dead range returns equity 1 (nothing to beat).
  public static func heroEquity(
    hole: [Card], vs ranges: [HandRange], board: [Card], samples: Int, seed: UInt64
  ) -> Double {
    guard !ranges.isEmpty else { return 1 }
    if board.count == 5, ranges.count == 1 {
      return exact(hero: hole, vs: ranges[0], board: board).equity
    }
    guard let setup = MonteCarloSetup(hero: hole, ranges: ranges, board: board, dead: CardSet()) else { return 1 }
    var rng = SeededRNG(seed: seed)
    let tally = runMonteCarlo(setup, samples: max(samples, 1), rng: &rng)
    return tally.samples == 0 ? 1 : tally.result(player: 0, isExact: false).equity
  }

  /// Card masks of every card not in `used`, ascending.
  private static func remainingBits(excluding used: UInt64) -> [UInt64] {
    (0..<52).compactMap { used & (1 << UInt64($0)) == 0 ? 1 << UInt64($0) : nil }
  }

  /// Calls `body` with the OR-mask of every k-subset of `bits` (k in 0...5).
  @inline(__always)
  static func forEachRunout(_ bits: UnsafeBufferPointer<UInt64>, k: Int, _ body: (UInt64) -> Void) {
    let n = bits.count
    switch k {
    case 0:
      body(0)
    case 1:
      for a in 0..<n { body(bits[a]) }
    case 2:
      for a in 0..<n {
        let ma = bits[a]
        for b in (a + 1)..<n { body(ma | bits[b]) }
      }
    case 3:
      for a in 0..<n {
        let ma = bits[a]
        for b in (a + 1)..<n {
          let mb = ma | bits[b]
          for c in (b + 1)..<n { body(mb | bits[c]) }
        }
      }
    case 4:
      for a in 0..<n {
        let ma = bits[a]
        for b in (a + 1)..<n {
          let mb = ma | bits[b]
          for c in (b + 1)..<n {
            let mc = mb | bits[c]
            for d in (c + 1)..<n { body(mc | bits[d]) }
          }
        }
      }
    default:
      for a in 0..<n {
        let ma = bits[a]
        for b in (a + 1)..<n {
          let mb = ma | bits[b]
          for c in (b + 1)..<n {
            let mc = mb | bits[c]
            for d in (c + 1)..<n {
              let md = mc | bits[d]
              for e in (d + 1)..<n { body(md | bits[e]) }
            }
          }
        }
      }
    }
  }
}
