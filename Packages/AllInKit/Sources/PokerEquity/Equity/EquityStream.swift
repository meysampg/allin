import PokerCore

extension EquityCalculator {
  /// Progressive estimate: batches of `batch` samples (batch k seeded by mix(seed, k)); last value has isFinal.
  /// Each estimate is cumulative. Cancelling the consumer stops the producer between batches.
  public static func stream(
    _ ranges: [HandRange], board: [Card], dead: CardSet = CardSet(), totalSamples: Int,
    batch: Int = 2000, seed: UInt64
  ) -> AsyncStream<EquityEstimate> {
    AsyncStream(EquityEstimate.self, bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        guard (2...9).contains(ranges.count), board.count <= 5,
          let setup = MonteCarloSetup(ranges: ranges, board: board, dead: dead)
        else {
          continuation.yield(EquityEstimate(results: [], samples: 0, isFinal: true))
          continuation.finish()
          return
        }
        let step = max(batch, 1)
        var tally = EquityTally(players: setup.playerCount)
        var index: UInt64 = 0
        var remaining = max(totalSamples, 0)
        repeat {
          if Task.isCancelled { break }
          let size = min(step, remaining)
          var rng = SeededRNG(seed: StableSeed.mix(seed, index))
          let part = runMonteCarlo(setup, samples: size, rng: &rng)
          tally.merge(part)
          remaining -= size
          index += 1
          let isFinal = remaining <= 0 || part.samples < size
          continuation.yield(
            EquityEstimate(results: tally.results(isExact: false), samples: tally.samples, isFinal: isFinal))
          if isFinal { break }
        } while true
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
