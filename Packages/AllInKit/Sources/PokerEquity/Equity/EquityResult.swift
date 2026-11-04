/// Equity of one player in a showdown simulation or enumeration.
public struct EquityResult: Sendable, Hashable {
  /// Fraction of outcomes won outright.
  public let win: Double
  /// Fraction of outcomes tied (any split).
  public let tie: Double
  /// Win plus tie shares (1/k for a k-way split); sums to 1 across players.
  public let equity: Double
  /// Boards × combos enumerated, or Monte Carlo samples.
  public let samples: Int
  public let isExact: Bool

  public init(win: Double, tie: Double, equity: Double, samples: Int, isExact: Bool) {
    self.win = win
    self.tie = tie
    self.equity = equity
    self.samples = samples
    self.isExact = isExact
  }

  /// 0 when exact; `sqrt(eq(1 − eq) / n)` otherwise.
  public var standardError: Double {
    guard !isExact, samples > 0 else { return 0 }
    return (max(equity * (1 - equity), 0) / Double(samples)).squareRoot()
  }
}

/// A progressive estimate: one result per input range, cumulative over all batches so far.
public struct EquityEstimate: Sendable, Hashable {
  public let results: [EquityResult]
  public let samples: Int
  public let isFinal: Bool

  public init(results: [EquityResult], samples: Int, isFinal: Bool) {
    self.results = results
    self.samples = samples
    self.isFinal = isFinal
  }
}

/// Accumulator shared by the exact and Monte Carlo engines. Counts are weights (plain counts when every weight is 1).
struct EquityTally: Sendable {
  var win: [Double]
  var tie: [Double]
  var share: [Double]
  /// Total weight of the outcomes seen.
  var total: Double = 0
  /// Number of outcomes seen (unweighted).
  var samples: Int = 0

  init(players: Int) {
    win = [Double](repeating: 0, count: players)
    tie = [Double](repeating: 0, count: players)
    share = [Double](repeating: 0, count: players)
  }

  mutating func merge(_ other: EquityTally) {
    for i in win.indices {
      win[i] += other.win[i]
      tie[i] += other.tie[i]
      share[i] += other.share[i]
    }
    total += other.total
    samples += other.samples
  }

  func results(isExact: Bool) -> [EquityResult] {
    (0..<win.count).map { result(player: $0, isExact: isExact) }
  }

  func result(player: Int, isExact: Bool) -> EquityResult {
    guard total > 0 else { return EquityResult(win: 0, tie: 0, equity: 0, samples: samples, isExact: isExact) }
    return EquityResult(
      win: win[player] / total, tie: tie[player] / total, equity: share[player] / total, samples: samples,
      isExact: isExact)
  }

  /// Records one outcome from the raw hand values (lower is better) of every player.
  @inline(__always)
  mutating func record(raws: UnsafeBufferPointer<UInt16>, weight: Double) {
    var best = UInt16.max
    var winners = 0
    for r in raws {
      if r < best {
        best = r
        winners = 1
      } else if r == best {
        winners += 1
      }
    }
    total += weight
    samples += 1
    if winners == 1 {
      for i in 0..<raws.count where raws[i] == best {
        win[i] += weight
        share[i] += weight
      }
    } else {
      let part = weight / Double(winners)
      for i in 0..<raws.count where raws[i] == best {
        tie[i] += weight
        share[i] += part
      }
    }
  }
}
