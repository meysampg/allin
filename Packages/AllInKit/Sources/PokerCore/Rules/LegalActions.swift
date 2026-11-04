/// Whether the aggressive option is an opening bet or a raise.
public enum RaiseKind: String, Codable, Sendable, Hashable {
  case bet
  case raise
}

/// The options of one player to act, with exact amounts. Pure value computed from the street's betting state.
public struct LegalActions: Codable, Sendable, Hashable {
  public let seat: Int
  public let stack: Int
  /// Chips this seat already committed on this street.
  public let committed: Int
  public let currentBet: Int
  public let chipUnit: Int
  /// Chips needed to match the current bet (may exceed the stack).
  public let toCall: Int
  /// Folding is always allowed for the player to act.
  public var canFold: Bool { true }
  /// Check is legal only when nothing is owed.
  public let canCheck: Bool
  /// `call` is legal when something is owed and the stack covers it (a call using the whole stack is also `allIn`).
  /// A call for less is only `allIn`.
  public let canCall: Bool
  /// Chips added by a `call` (equals `toCall`), or by an all-in call for less (the whole stack).
  public var callAmount: Int { min(toCall, stack) }
  /// `bet` when no bet exists on the street, `raise` otherwise; nil if neither is possible (only all-in remains
  /// or nothing).
  public let raiseKind: RaiseKind?
  /// Legal "to" totals for `bet`/`raise`. The upper bound is the all-in total.
  public let raiseRange: ClosedRange<Int>?
  /// Total committed after going all-in, or nil if all-in is not legal (a raise that betting does not allow).
  public let allInTo: Int?

  public var minRaiseTo: Int? { raiseRange?.lowerBound }
  public var maxRaiseTo: Int? { raiseRange?.upperBound }
  public var canAllIn: Bool { allInTo != nil }
  /// True when the only way to continue is to put in the whole stack (call for less than owed).
  public var callIsAllIn: Bool { toCall > 0 && stack <= toCall }

  /// Computes the options.
  /// - Parameters:
  ///   - lastRaiseSize: size of the last full bet/raise increment this street (the minimum bet when none exists).
  ///   - canRaise: false when the player already acted and no full raise has reopened the betting.
  public static func compute(
    seat: Int, stack: Int, committed: Int, currentBet: Int, lastRaiseSize: Int, canRaise: Bool, chipUnit: Int = 1
  ) -> LegalActions {
    let toCall = max(0, currentBet - committed)
    let total = committed + stack
    let minTo = currentBet + lastRaiseSize
    var kind: RaiseKind?
    var range: ClosedRange<Int>?
    if canRaise && stack > toCall && total >= minTo {
      kind = currentBet == 0 ? .bet : .raise
      range = minTo...total
    }
    let allIn: Int? = stack > 0 && (stack <= toCall || canRaise) ? total : nil
    return LegalActions(
      seat: seat, stack: stack, committed: committed, currentBet: currentBet, chipUnit: chipUnit,
      toCall: toCall, canCheck: toCall == 0, canCall: toCall > 0 && stack >= toCall,
      raiseKind: kind, raiseRange: range, allInTo: allIn)
  }

  /// Throws if `action` is not legal.
  public func validate(_ action: Action) throws {
    switch action {
    case .fold: return
    case .check: if !canCheck { throw ActionError.notLegal(action) }
    case .call: if !canCall { throw ActionError.notLegal(action) }
    case .allIn: if !canAllIn { throw ActionError.notLegal(action) }
    case .bet(let to), .raise(let to):
      let expected: RaiseKind = if case .bet = action { .bet } else { .raise }
      guard let range = raiseRange, raiseKind == expected else { throw ActionError.notLegal(action) }
      guard range.contains(to), to == range.upperBound || to % chipUnit == 0 else {
        throw ActionError.amountOutOfRange(action, min: range.lowerBound, max: range.upperBound)
      }
    }
  }

  public func isLegal(_ action: Action) -> Bool { (try? validate(action)) != nil }
}
