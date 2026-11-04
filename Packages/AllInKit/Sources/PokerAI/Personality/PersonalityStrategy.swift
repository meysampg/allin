import Foundation
import PokerCore
import PokerEquity

/// A white-box bot driven by ``PersonalityParams``. Pure: the distribution depends only on the params, the init
/// seed and the context, and every random draw inside is seeded from the context.
public struct PersonalityStrategy: StrategyProvider {
  public let params: PersonalityParams
  /// Preflop ordering with the character's shape noise applied.
  let ordering: PreflopOrdering
  /// Softening width of every threshold comparison.
  let width: Double
  /// Share of hands played voluntarily per position (see `positionIndex`).
  let playFractions: [Double]

  /// Scales the target VPIP into the unopened play fraction (tuned so measured 6-max VPIP matches the target).
  static let vpipScale = 0.86

  /// - Parameter seed: only feeds the shape noise of the preflop ordering.
  public init(params: PersonalityParams, seed: UInt64 = 0) {
    self.params = params
    ordering =
      params.shapeNoise > 0
      ? PreflopOrdering.standard.perturbed(seed: seed, amount: params.shapeNoise) : PreflopOrdering.standard
    width = 0.02 + 0.08 * params.randomness
    let a = params.positionAwareness
    let multipliers = [1 - 0.45 * a, 1 - 0.25 * a, 1 + 0.15 * a, 1 + 0.6 * a, 1 + 0.1 * a, 1.0, 1 + 0.8 * a]
    playFractions = multipliers.map { min(max(params.vpip * $0 * Self.vpipScale, 0), 1) }
  }

  public func distribution(for context: DecisionContext) -> ActionDistribution {
    let acts = SafeActions(context: context)
    guard context.holeCards.count == 2, !context.legal.isFoldOnly else { return acts.certain(acts.passive) }
    let spot = SpotFeatures(context)
    var policy = PolicyWeights()
    if context.street == .preflop {
      preflop(context, spot: spot, acts: acts, policy: &policy)
    } else {
      postflop(context, spot: spot, acts: acts, policy: &policy)
    }
    return finish(policy, context: context, acts: acts)
  }

  /// Logistic softening of `x > 0`.
  func soft(_ x: Double) -> Double { 1 / (1 + exp(-x / width)) }

  /// Index into `playFractions`.
  func playFraction(_ spot: SpotFeatures) -> Double {
    if spot.isHeadsUp && spot.position == .button { return playFractions[6] }
    switch spot.position {
    case .early: return playFractions[0]
    case .middle: return playFractions[1]
    case .cutoff: return playFractions[2]
    case .button: return playFractions[3]
    case .smallBlind: return playFractions[4]
    case .bigBlind: return playFractions[5]
    }
  }

  /// Normalizes the policy, mixes in the randomness and validates against the legal actions.
  private func finish(_ policy: PolicyWeights, context: DecisionContext, acts: SafeActions) -> ActionDistribution {
    let total = policy.items.reduce(0.0) { $0 + $1.weight }
    guard total > 0, total.isFinite else { return acts.certain(acts.passive) }
    let r = min(max(params.randomness, 0), 1)
    var probabilities: [(action: Action, p: Double)] = []
    func add(_ action: Action, _ p: Double) {
      if let i = probabilities.firstIndex(where: { $0.action == action }) {
        probabilities[i].p += p
      } else {
        probabilities.append((action, p))
      }
    }
    for item in policy.items { add(item.action, item.weight / total * (1 - r)) }
    if r > 0 {
      for entry in UniformRandomStrategy().distribution(for: context).entries {
        add(entry.action, entry.probability * r)
      }
    }
    // Dyadic weights summing to exactly 1: the distribution is then bit-identical on every call, whatever the
    // iteration order of the dictionary inside `ActionDistribution`.
    let scale = Double(1 << 24)
    var units = probabilities.map { Int(($0.p * scale).rounded()) }
    if let top = units.indices.max(by: { units[$0] < units[$1] }) { units[top] += (1 << 24) - units.reduce(0, +) }
    let weights = zip(probabilities, units).filter { $1 > 0 }.map { ($0.action, Double($1) / scale) }
    return (try? ActionDistribution(weights: weights, legal: context.legal)) ?? acts.certain(acts.passive)
  }
}

extension LegalActions {
  /// Nothing but folding is possible (cannot happen for a seat to act; guards the bot against bad input).
  fileprivate var isFoldOnly: Bool { !canCheck && !canCall && !canAllIn && raiseRange == nil }
}

/// Weighted actions a policy wants, before normalization.
struct PolicyWeights {
  private(set) var items: [(action: Action, weight: Double)] = []

  mutating func add(_ action: Action, _ weight: Double) {
    if weight > 1e-12 { items.append((action, weight)) }
  }
}

/// The legal ways to fold, continue and bet, derived only from `LegalActions`.
struct SafeActions {
  let legal: LegalActions
  let pot: Int
  /// Fold, or check when folding would be free.
  let foldOrCheck: Action
  /// Call, the all-in that is a call for less, or the free alternative when nothing is owed.
  let call: Action
  /// Check when possible, else `call`.
  let passive: Action

  init(context: DecisionContext) {
    legal = context.legal
    pot = context.pot
    foldOrCheck = legal.canCheck ? .check : .fold
    if legal.canCall {
      call = .call
    } else if legal.callIsAllIn {
      call = .allIn
    } else {
      call = foldOrCheck
    }
    passive = legal.canCheck ? .check : call
  }

  func certain(_ action: Action) -> ActionDistribution {
    (try? ActionDistribution(certain: action, legal: legal)) ?? (try! ActionDistribution(certain: .fold, legal: legal))
  }

  /// Bet or raise to `amount` total, snapped to the legal range; all-in when only that is possible.
  func raise(to amount: Double) -> Action? {
    if let a = ActionDistribution.snapRaise(to: Int(amount.rounded()), legal: legal) { return a }
    return allInRaise
  }

  /// Bet at `fraction` of the pot (raise: of the pot after calling).
  func bet(fraction: Double) -> Action? {
    if let a = ActionDistribution.potSizedRaises(fractions: [fraction], pot: pot, legal: legal).first { return a }
    return allInRaise
  }

  /// `.allIn` as an aggressive action; nil when it would only be a call or is illegal.
  var allInRaise: Action? {
    legal.canAllIn && legal.raiseRange == nil && !legal.callIsAllIn ? .allIn : nil
  }

  var canShove: Bool { legal.canAllIn && !legal.callIsAllIn }
}
