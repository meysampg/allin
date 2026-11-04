/// Streaming mean and variance (Welford). Mergeable, so shards can be combined in a fixed order.
public struct RunningStats: Sendable, Hashable {
  public private(set) var count: Int
  public private(set) var mean: Double
  private var m2: Double

  public init() {
    count = 0
    mean = 0
    m2 = 0
  }

  public mutating func add(_ x: Double) {
    count += 1
    let delta = x - mean
    mean += delta / Double(count)
    m2 += delta * (x - mean)
  }

  /// Combines two sets of samples (Chan et al.).
  public mutating func merge(_ other: RunningStats) {
    guard other.count > 0 else { return }
    guard count > 0 else {
      self = other
      return
    }
    let n1 = Double(count)
    let n2 = Double(other.count)
    let total = n1 + n2
    let delta = other.mean - mean
    m2 += other.m2 + delta * delta * n1 * n2 / total
    mean += delta * n2 / total
    count += other.count
  }

  /// Sample variance (n - 1 denominator); 0 with fewer than two samples.
  public var variance: Double { count > 1 ? m2 / Double(count - 1) : 0 }
}

/// A win rate in big blinds per 100 hands with its standard error.
public struct WinRate: Sendable, Hashable {
  /// Independent samples (duplicate pairs, or hands).
  public let samples: Int
  /// 2 for a duplicate pair, 1 otherwise.
  public let handsPerSample: Int
  public let bbPer100: Double
  /// In bb/100.
  public let standardError: Double

  public var ciLow: Double { bbPer100 - 1.96 * standardError }
  public var ciHigh: Double { bbPer100 + 1.96 * standardError }

  /// - Parameter stats: statistics over the per-sample results in big blinds.
  public init(stats: RunningStats, handsPerSample: Int) {
    let hps = Double(max(1, handsPerSample))
    samples = stats.count
    self.handsPerSample = max(1, handsPerSample)
    bbPer100 = 100 * stats.mean / hps
    standardError = stats.count > 0 ? 100 * (stats.variance / Double(stats.count)).squareRoot() / hps : 0
  }
}
