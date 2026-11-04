import PokerCore

/// Inputs of a Monte Carlo run: optional known hand (player 0) followed by one sampler per range.
struct MonteCarloSetup: Sendable {
  let fixed: [UInt64]
  let samplers: [RangeSampler]
  let boardMask: UInt64
  let boardCount: Int

  var playerCount: Int { fixed.count + samplers.count }

  /// Ranges only. nil when there are fewer than 2 or more than 9 players, or the board is invalid.
  init?(ranges: [HandRange], board: [Card], dead: CardSet) {
    guard (2...9).contains(ranges.count), board.count <= 5 else { return nil }
    let blocked = dead.union(CardSet(board))
    fixed = []
    samplers = ranges.map { RangeSampler($0, excluding: blocked) }
    boardMask = CardSet(board).bits
    boardCount = board.count
  }

  /// Known hand vs ranges. nil when the hand is not 2 distinct live cards or the field size is invalid.
  init?(hero: [Card], ranges: [HandRange], board: [Card], dead: CardSet) {
    guard hero.count == 2, (1...8).contains(ranges.count), board.count <= 5 else { return nil }
    let heroMask = CardSet(hero).bits
    let boardMask = CardSet(board).bits
    guard heroMask.nonzeroBitCount == 2, heroMask & (boardMask | dead.bits) == 0 else { return nil }
    let blocked = CardSet(bits: heroMask | boardMask | dead.bits)
    fixed = [heroMask]
    samplers = ranges.map { RangeSampler($0, excluding: blocked) }
    self.boardMask = boardMask
    boardCount = board.count
  }

  var hasEmptyRange: Bool { samplers.contains { $0.isEmpty } }
}

extension EquityCalculator {
  /// Seeded Monte Carlo, ranges vs ranges (2...9 players), rejection sampling for card removal.
  /// Returns zero-sample results when a range has no live combo.
  public static func monteCarlo(
    _ ranges: [HandRange], board: [Card], dead: CardSet = CardSet(), samples: Int,
    using rng: inout some RandomNumberGenerator
  ) -> [EquityResult] {
    precondition((2...9).contains(ranges.count), "Equity needs 2 to 9 ranges")
    precondition(board.count <= 5, "At most 5 board cards")
    guard let setup = MonteCarloSetup(ranges: ranges, board: board, dead: dead) else { return [] }
    return runMonteCarlo(setup, samples: samples, rng: &rng).results(isExact: false)
  }

  /// Hero's known hand vs one or more villain ranges. Zero-sample result when a range has no live combo.
  public static func monteCarlo(
    hero: [Card], vs ranges: [HandRange], board: [Card], dead: CardSet = CardSet(), samples: Int,
    using rng: inout some RandomNumberGenerator
  ) -> EquityResult {
    precondition(hero.count == 2, "Hero needs 2 cards")
    precondition((1...8).contains(ranges.count), "Equity needs 1 to 8 villain ranges")
    precondition(board.count <= 5, "At most 5 board cards")
    guard let setup = MonteCarloSetup(hero: hero, ranges: ranges, board: board, dead: dead) else {
      return EquityResult(win: 0, tie: 0, equity: 0, samples: 0, isExact: false)
    }
    return runMonteCarlo(setup, samples: samples, rng: &rng).result(player: 0, isExact: false)
  }

  /// Chunked TaskGroup; chunk i uses SeededRNG(seed: StableSeed.mix(seed, i)); merged in chunk order (deterministic).
  public static func parallelMonteCarlo(
    _ ranges: [HandRange], board: [Card], dead: CardSet = CardSet(), samples: Int, seed: UInt64,
    chunks: Int = 8
  ) async -> [EquityResult] {
    precondition((2...9).contains(ranges.count), "Equity needs 2 to 9 ranges")
    precondition(board.count <= 5, "At most 5 board cards")
    guard let setup = MonteCarloSetup(ranges: ranges, board: board, dead: dead) else { return [] }
    let count = max(1, min(chunks, max(samples, 1)))
    let base = max(samples, 0) / count
    let extra = max(samples, 0) % count
    let parts = await withTaskGroup(of: (Int, EquityTally).self, returning: [EquityTally].self) { group in
      for i in 0..<count {
        let size = base + (i < extra ? 1 : 0)
        group.addTask {
          var rng = SeededRNG(seed: StableSeed.mix(seed, UInt64(i)))
          return (i, runMonteCarlo(setup, samples: size, rng: &rng))
        }
      }
      var collected = [EquityTally?](repeating: nil, count: count)
      for await (i, tally) in group { collected[i] = tally }
      return collected.map { $0! }
    }
    var merged = EquityTally(players: setup.playerCount)
    for part in parts { merged.merge(part) }
    return merged.results(isExact: false)
  }

  /// Draws up to `samples` outcomes. Stops early (fewer samples) when the spot is impossible, for example when a
  /// range is empty or the players' ranges cannot be dealt without sharing a card.
  static func runMonteCarlo<R: RandomNumberGenerator>(
    _ setup: MonteCarloSetup, samples: Int, rng: inout R
  ) -> EquityTally {
    var tally = EquityTally(players: setup.playerCount)
    guard samples > 0, !setup.hasEmptyRange else { return tally }
    let nFixed = setup.fixed.count
    let n = setup.playerCount
    var base = setup.boardMask
    for m in setup.fixed { base |= m }
    var masks = [UInt64](repeating: 0, count: n)
    for i in 0..<nFixed { masks[i] = setup.fixed[i] }
    var raws = [UInt16](repeating: 0, count: n)
    let needBoard = 5 - setup.boardCount
    let boardMask = setup.boardMask
    var done = 0
    var failures = 0
    masks.withUnsafeMutableBufferPointer { mk in
      raws.withUnsafeMutableBufferPointer { rw in
        while done < samples {
          var used = base
          var ok = true
          for j in 0..<setup.samplers.count {
            let m = setup.samplers[j].drawMask(&rng)
            if m & used != 0 {
              ok = false
              break
            }
            used |= m
            mk[nFixed + j] = m
          }
          if !ok {
            failures += 1
            if failures > 100_000 { return }
            continue
          }
          failures = 0
          var board = boardMask
          var need = needBoard
          while need > 0 {
            let bit: UInt64 = 1 << rng.next(upperBound: 52 as UInt64)
            if used & bit == 0 {
              used |= bit
              board |= bit
              need -= 1
            }
          }
          for i in 0..<n { rw[i] = HandEvaluator.evaluate(CardSet(bits: mk[i] | board)).rawValue }
          tally.record(raws: UnsafeBufferPointer(rw), weight: 1)
          done += 1
        }
      }
    }
    return tally
  }
}
