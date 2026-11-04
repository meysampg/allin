/// A strategy as a white box: it exposes its full probability distribution for a decision. Sampling is a
/// separate step (seat + `SeededRNG`), so graders and coaches can read the distribution exactly.
public protocol StrategyProvider: Sendable {
  /// The distribution over legal actions. Every action must be legal for `context.legal`.
  func distribution(for context: DecisionContext) -> ActionDistribution
}

/// Uniform over the legal actions: call or check, fold (only when something is owed), and a few bet sizes
/// (minimum, half pot, pot, all-in). A free fold is left out so it never gives up a check.
public struct UniformRandomStrategy: StrategyProvider {
  /// Pot fractions used for bets and raises, besides the minimum and the all-in.
  public let sizeFractions: [Double]

  public init(sizeFractions: [Double] = [0.5, 1.0]) {
    self.sizeFractions = sizeFractions
  }

  public func distribution(for context: DecisionContext) -> ActionDistribution {
    let legal = context.legal
    var actions: [Action] = []
    if !legal.canCheck { actions.append(.fold) }
    if legal.canCheck { actions.append(.check) }
    if legal.canCall { actions.append(.call) }
    if let range = legal.raiseRange,
      let min = ActionDistribution.snapRaise(to: range.lowerBound, legal: legal)
    {
      actions.append(min)
      actions += ActionDistribution.potSizedRaises(
        fractions: sizeFractions, pot: context.pot, legal: legal)
    }
    if legal.canAllIn { actions.append(.allIn) }
    if actions.isEmpty { actions = [.fold] }
    // Every action above comes from `legal`, so this cannot throw.
    return try! ActionDistribution(uniform: actions, legal: legal)
  }
}
