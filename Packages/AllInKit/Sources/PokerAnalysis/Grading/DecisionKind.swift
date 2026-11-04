import PokerCore

public enum ActionClass: String, Codable, Sendable { case fold, passive, aggressive }

/// What the hero faced: nothing to call, one bet, or a raise (two or more aggressive actions this street).
public enum Facing: String, Codable, Sendable { case none, bet, raise }

public struct DecisionKind: Codable, Sendable, Hashable {
  public let street: Street
  public let facing: Facing
  public let chosen: ActionClass
  public let best: ActionClass

  public init(street: Street, facing: Facing, chosen: ActionClass, best: ActionClass) {
    self.street = street
    self.facing = facing
    self.chosen = chosen
    self.best = best
  }
}

enum DecisionClassifier {
  /// Fold; check or call (an all-in that only calls included); bet, raise or a raising all-in.
  static func actionClass(_ action: Action, legal: LegalActions) -> ActionClass {
    switch action {
    case .fold: .fold
    case .check, .call: .passive
    case .bet, .raise: .aggressive
    case .allIn: legal.callIsAllIn && legal.canCall ? .passive : .aggressive
    }
  }

  /// Which entries of `history` opened or raised the betting on their street (blinds are not actions).
  static func aggressiveFlags(_ history: [ActionEntry], bigBlind: Int) -> [Bool] {
    var street: Street?
    var maxCommitted = 0
    var flags: [Bool] = []
    for entry in history {
      if entry.street != street {
        street = entry.street
        maxCommitted = entry.street == .preflop ? bigBlind : 0
      }
      let aggressive = entry.committedAfter > maxCommitted && entry.action != .call && entry.action != .fold
      if aggressive { maxCommitted = entry.committedAfter }
      flags.append(aggressive)
    }
    return flags
  }

  static func aggressiveCount(_ context: DecisionContext, street: Street) -> Int {
    let flags = aggressiveFlags(context.history, bigBlind: context.config.bigBlind)
    var count = 0
    for (entry, flag) in zip(context.history, flags) where flag && entry.street == street { count += 1 }
    return count
  }

  static func facing(_ context: DecisionContext) -> Facing {
    guard context.legal.toCall > 0 else { return .none }
    return aggressiveCount(context, street: context.street) >= 2 ? .raise : .bet
  }

  static func kind(context: DecisionContext, chosen: Action, best: Action) -> DecisionKind {
    DecisionKind(
      street: context.street, facing: facing(context), chosen: actionClass(chosen, legal: context.legal),
      best: actionClass(best, legal: context.legal))
  }
}
