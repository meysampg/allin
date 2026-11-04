import Foundation
import PokerCore
import PokerEquity

/// Bet sizes of a personality, as pot fractions unless stated otherwise.
public struct SizingProfile: Codable, Sendable, Hashable {
  /// Preflop open size in big blinds (+1 bb per limper).
  public var openRaiseBB: Double
  /// Multiplier of the raise faced for a 3-bet in position; +0.5 out of position.
  public var threeBetMultiplier: Double
  /// Pot fraction for medium and strong value bets.
  public var value: Double
  /// Pot fraction for nutted hands.
  public var nutted: Double
  /// Pot fraction for bluffs and semi-bluffs.
  public var bluff: Double
  /// Share of value and bluff bets made at 1.5x pot.
  public var overbetFrequency: Double

  public init(
    openRaiseBB: Double, threeBetMultiplier: Double, value: Double, nutted: Double, bluff: Double,
    overbetFrequency: Double
  ) {
    self.openRaiseBB = openRaiseBB
    self.threeBetMultiplier = threeBetMultiplier
    self.value = value
    self.nutted = nutted
    self.bluff = bluff
    self.overbetFrequency = overbetFrequency
  }
}

/// Why a parameter set is invalid.
public enum PersonalityParamsError: Error, Sendable, Equatable {
  case probabilityOutOfRange(field: String, value: Double)
  case nonPositive(field: String, value: Double)
}

/// The knobs of a white-box personality bot. Probabilities are in 0...1, thresholds and sizes are positive.
public struct PersonalityParams: Codable, Sendable, Hashable {
  // Preflop
  /// Target share of hands played voluntarily (6-max reference).
  public var vpip: Double
  /// Share of played hands entered with a raise.
  public var pfrRatio: Double
  /// Top share of all combos 3-bet when facing an open.
  public var threeBet: Double
  /// Share of the opening range folded to a 3-bet (weakest first).
  public var foldTo3Bet: Double
  /// 0 = same range everywhere, 1 = full position scaling.
  public var positionAwareness: Double
  // Postflop
  /// Flop c-bet probability with non-value hands as preflop aggressor.
  public var cbet: Double
  /// Keep betting with non-value hands after betting the previous street.
  public var barrel: Double
  /// Base bluff probability with air when checked to (draws x 1.5).
  public var bluffFreq: Double
  /// Equity against the perceived range needed to bet or raise for value.
  public var valueThreshold: Double
  /// Continue facing a bet if equity >= potOdds x continueThreshold.
  public var continueThreshold: Double
  /// Fraction of would-be folds turned into calls (station factor).
  public var stickiness: Double
  /// Probability of checking or calling with nutted hands.
  public var slowplay: Double
  public var sizing: SizingProfile
  /// Trust in line reading; the perceived range blur is `1 - readSkill`.
  public var readSkill: Double
  /// Mixes the policy with a uniform over safe legal actions.
  public var randomness: Double
  /// `PreflopOrdering.perturbed` amount.
  public var shapeNoise: Double

  public init(
    vpip: Double, pfrRatio: Double, threeBet: Double, foldTo3Bet: Double, positionAwareness: Double,
    cbet: Double, barrel: Double, bluffFreq: Double, valueThreshold: Double, continueThreshold: Double,
    stickiness: Double, slowplay: Double, sizing: SizingProfile, readSkill: Double, randomness: Double,
    shapeNoise: Double
  ) {
    self.vpip = vpip
    self.pfrRatio = pfrRatio
    self.threeBet = threeBet
    self.foldTo3Bet = foldTo3Bet
    self.positionAwareness = positionAwareness
    self.cbet = cbet
    self.barrel = barrel
    self.bluffFreq = bluffFreq
    self.valueThreshold = valueThreshold
    self.continueThreshold = continueThreshold
    self.stickiness = stickiness
    self.slowplay = slowplay
    self.sizing = sizing
    self.readSkill = readSkill
    self.randomness = randomness
    self.shapeNoise = shapeNoise
  }

  /// Fields a `variation` may name: scalar parameters with their valid range.
  private typealias Field = (name: String, path: WritableKeyPath<PersonalityParams, Double>, range: ClosedRange<Double>)

  private static var scalarFields: [Field] {
    [
      ("vpip", \.vpip, 0...1), ("pfrRatio", \.pfrRatio, 0...1), ("threeBet", \.threeBet, 0...1),
      ("foldTo3Bet", \.foldTo3Bet, 0...1), ("positionAwareness", \.positionAwareness, 0...1),
      ("cbet", \.cbet, 0...1), ("barrel", \.barrel, 0...1), ("bluffFreq", \.bluffFreq, 0...1),
      ("valueThreshold", \.valueThreshold, 0.05...1), ("continueThreshold", \.continueThreshold, 0.05...3),
      ("stickiness", \.stickiness, 0...1), ("slowplay", \.slowplay, 0...1), ("readSkill", \.readSkill, 0...1),
      ("randomness", \.randomness, 0...1), ("shapeNoise", \.shapeNoise, 0...1),
    ]
  }

  /// Names accepted as keys of `varied(by:seed:)` and of a character's `variation`.
  public static var variableFieldNames: Set<String> { Set(scalarFields.map(\.name)) }

  /// Throws when a probability leaves 0...1 or a threshold or size is not positive.
  public func validate() throws {
    for field in Self.scalarFields {
      let value = self[keyPath: field.path]
      guard value.isFinite else { throw PersonalityParamsError.probabilityOutOfRange(field: field.name, value: value) }
      if field.range.lowerBound > 0 {
        guard value > 0 else { throw PersonalityParamsError.nonPositive(field: field.name, value: value) }
      } else if !(0...1).contains(value) {
        throw PersonalityParamsError.probabilityOutOfRange(field: field.name, value: value)
      }
    }
    for (name, value) in [("overbetFrequency", sizing.overbetFrequency)] where !(0...1).contains(value) {
      throw PersonalityParamsError.probabilityOutOfRange(field: name, value: value)
    }
    let sizes = [
      ("openRaiseBB", sizing.openRaiseBB), ("threeBetMultiplier", sizing.threeBetMultiplier),
      ("value", sizing.value), ("nutted", sizing.nutted), ("bluff", sizing.bluff),
    ]
    for (name, value) in sizes where !(value.isFinite && value > 0) {
      throw PersonalityParamsError.nonPositive(field: name, value: value)
    }
  }

  /// Patrons: each named field is drawn uniformly in value +- halfWidth, then clamped to the valid range.
  /// Deterministic in `seed`; unknown names are ignored.
  public func varied(by variation: [String: Double], seed: UInt64) -> PersonalityParams {
    var result = self
    var rng = SeededRNG(seed: StableSeed.mix(seed, 0x5041_5452))
    for field in Self.scalarFields {
      guard let halfWidth = variation[field.name], halfWidth > 0 else { continue }
      let draw = Double.random(in: -halfWidth...halfWidth, using: &rng)
      let value = self[keyPath: field.path] + draw
      result[keyPath: field.path] = min(max(value, field.range.lowerBound), field.range.upperBound)
    }
    return result
  }
}
