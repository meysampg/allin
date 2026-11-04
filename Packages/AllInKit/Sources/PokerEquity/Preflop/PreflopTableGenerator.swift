import Foundation
import PokerCore

/// Builds the bytes of `preflop169.bin` by exact enumeration of all C(52,5) boards (deterministic, parallel).
public enum PreflopTableGenerator {
  private static let totalBoards = 2_598_960

  /// Counts for every matchup, in matchup order.
  private struct Counts: Sendable {
    var wins: [UInt32]
    var ties: [UInt32]
    var losses: [UInt32]

    init(count: Int) {
      wins = [UInt32](repeating: 0, count: count)
      ties = wins
      losses = wins
    }
  }

  public static func generate(progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Data {
    // 1. Canonical matchups (sorted unique keys) with their combo indices and masks.
    var keySet = Set<UInt32>()
    let combos = Combo.all
    for i in 0..<1326 {
      for j in (i + 1)..<1326 where combos[i].mask.bits & combos[j].mask.bits == 0 {
        keySet.insert(PreflopEquityTable.canonicalKey(combos[i].cards, combos[j].cards).key)
      }
    }
    let keys = keySet.sorted()
    let matchupCount = keys.count
    var comboA = [UInt16](repeating: 0, count: matchupCount)
    var comboB = [UInt16](repeating: 0, count: matchupCount)
    var union = [UInt64](repeating: 0, count: matchupCount)
    for (m, key) in keys.enumerated() {
      let cards = PreflopEquityTable.cards(ofKey: key)
      let a = Combo(cards[0], cards[1])
      let b = Combo(cards[2], cards[3])
      comboA[m] = UInt16(a.index)
      comboB[m] = UInt16(b.index)
      union[m] = a.mask.bits | b.mask.bits
    }
    let comboMasks = combos.map { $0.mask.bits }

    // 2. Shard boards by their first two cards and run them on a bounded task group.
    var shards: [(Int, Int)] = []
    for c0 in 0..<48 { for c1 in (c0 + 1)..<49 { shards.append((c0, c1)) } }
    // Biggest shards first for balance; the order does not affect the (integer) result.
    shards.sort { ($0.1, $0.0) < ($1.1, $1.0) }
    let width = max(ProcessInfo.processInfo.activeProcessorCount, 1)
    var total = Counts(count: matchupCount)
    var doneBoards = 0
    let ctx = Context(comboA: comboA, comboB: comboB, union: union, comboMasks: comboMasks)

    await withTaskGroup(of: (Int, Counts).self) { group in
      var next = 0
      func addNext() {
        guard next < shards.count else { return }
        let (c0, c1) = shards[next]
        next += 1
        group.addTask { (boardCount(c1), runShard(c0: c0, c1: c1, ctx)) }
      }
      for _ in 0..<width { addNext() }
      while let (boards, counts) = await group.next() {
        for m in 0..<matchupCount {
          total.wins[m] &+= counts.wins[m]
          total.ties[m] &+= counts.ties[m]
          total.losses[m] &+= counts.losses[m]
        }
        doneBoards += boards
        progress(Double(doneBoards) / Double(totalBoards))
        addNext()
      }
    }

    // 3. Quantise and serialise.
    var eqQ = [UInt16](repeating: 0, count: matchupCount)
    var tieQ = [UInt16](repeating: 0, count: matchupCount)
    let n = Double(PreflopEquityTable.boardsPerMatchup)
    for m in 0..<matchupCount {
      precondition(
        total.wins[m] + total.ties[m] + total.losses[m] == PreflopEquityTable.boardsPerMatchup,
        "Matchup \(m) saw the wrong number of boards")
      let equity = (Double(total.wins[m]) + Double(total.ties[m]) / 2) / n
      eqQ[m] = UInt16((equity * 65535).rounded())
      tieQ[m] = UInt16((Double(total.ties[m]) / n * 65535).rounded())
    }
    return PreflopEquityTable.makeFile(keys: keys, equityQ: eqQ, tieQ: tieQ)
  }

  private struct Context: Sendable {
    let comboA: [UInt16]
    let comboB: [UInt16]
    let union: [UInt64]
    let comboMasks: [UInt64]
  }

  /// C(51 - c1, 3): boards whose two lowest cards are (c0, c1).
  private static func boardCount(_ c1: Int) -> Int {
    let r = 51 - c1
    return r * (r - 1) * (r - 2) / 6
  }

  private static func runShard(c0: Int, c1: Int, _ ctx: Context) -> Counts {
    let m = ctx.comboA.count
    var counts = Counts(count: m)
    var values = [UInt16](repeating: 0, count: 1326)
    let base: UInt64 = 1 << UInt64(c0) | 1 << UInt64(c1)
    ctx.comboMasks.withUnsafeBufferPointer { cm in
      ctx.comboA.withUnsafeBufferPointer { ca in
        ctx.comboB.withUnsafeBufferPointer { cb in
          ctx.union.withUnsafeBufferPointer { un in
            values.withUnsafeMutableBufferPointer { vals in
              counts.wins.withUnsafeMutableBufferPointer { wins in
                counts.ties.withUnsafeMutableBufferPointer { ties in
                  counts.losses.withUnsafeMutableBufferPointer { losses in
                    func board(_ b: UInt64) {
                      for i in 0..<1326 where cm[i] & b == 0 {
                        vals[i] = HandEvaluator.evaluate(CardSet(bits: cm[i] | b)).rawValue
                      }
                      for k in 0..<m {
                        let valid: UInt32 = un[k] & b == 0 ? 1 : 0
                        let x = vals[Int(ca[k])]
                        let y = vals[Int(cb[k])]
                        // Lower raw value is the stronger hand.
                        wins[k] &+= valid & (x < y ? 1 : 0)
                        ties[k] &+= valid & (x == y ? 1 : 0)
                        losses[k] &+= valid & (x > y ? 1 : 0)
                      }
                    }
                    for c2 in (c1 + 1)..<50 {
                      let m2 = base | 1 << UInt64(c2)
                      for c3 in (c2 + 1)..<51 {
                        let m3 = m2 | 1 << UInt64(c3)
                        for c4 in (c3 + 1)..<52 { board(m3 | 1 << UInt64(c4)) }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    return counts
  }
}
