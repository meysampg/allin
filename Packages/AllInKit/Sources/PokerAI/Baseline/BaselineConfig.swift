import PokerCore

/// Tunable numbers of ``BaselineStrategy`` (Oryn). The defaults are the shipped values.
public struct BaselineConfig: Sendable, Hashable {
  /// Blur of the perceived ranges (0 trusts the line model fully, 1 assumes random hands).
  public var rangeBlur: Double
  /// Monte Carlo samples for flop and turn equity (the river is exact).
  public var equitySamples: Int
  /// Equity against a *calling* range needed to bet or raise for value.
  public var valueThreshold: [Street: Double]
  /// Villains call with the top share of their perceived range, by board strength.
  public var callingRangeTop: Double
  /// The share of the minimum defence frequency the hero defends.
  public var mdfFactor: Double
  public var bluffRatioScale: Double
  public var drySize: Double
  public var mediumSize: Double
  public var wetSize: Double
  public var riverPolarSize: Double
  /// Open-raise size in big blinds (heads-up too).
  public var openRaiseBB: Double
  /// 3-bet size as a multiple of the raise it answers, in position and out of position.
  public var threeBetIP: Double
  public var threeBetOOP: Double
  /// 4-bet size as a multiple of the 3-bet.
  public var fourBet: Double
  /// Share of every decision spread evenly over the actions the plan already uses.
  public var randomness: Double

  public init(
    rangeBlur: Double = 0.20,
    equitySamples: Int = 128,
    valueThreshold: [Street: Double] = [.flop: 0.60, .turn: 0.62, .river: 0.58],
    callingRangeTop: Double = 0.60,
    mdfFactor: Double = 0.90,
    bluffRatioScale: Double = 1.0,
    drySize: Double = 0.33,
    mediumSize: Double = 0.55,
    wetSize: Double = 0.75,
    riverPolarSize: Double = 0.85,
    openRaiseBB: Double = 2.5,
    threeBetIP: Double = 3.0,
    threeBetOOP: Double = 4.0,
    fourBet: Double = 2.3,
    randomness: Double = 0.02
  ) {
    self.rangeBlur = rangeBlur
    self.equitySamples = equitySamples
    self.valueThreshold = valueThreshold
    self.callingRangeTop = callingRangeTop
    self.mdfFactor = mdfFactor
    self.bluffRatioScale = bluffRatioScale
    self.drySize = drySize
    self.mediumSize = mediumSize
    self.wetSize = wetSize
    self.riverPolarSize = riverPolarSize
    self.openRaiseBB = openRaiseBB
    self.threeBetIP = threeBetIP
    self.threeBetOOP = threeBetOOP
    self.fourBet = fourBet
    self.randomness = randomness
  }

  public static let `default` = BaselineConfig()

  func threshold(_ street: Street) -> Double { valueThreshold[street] ?? 0.60 }
}
