import PokerCore

/// The five size shortcuts of the action bar (keys 1...5).
public enum BetPreset: Int, CaseIterable, Sendable {
  case third = 1
  case half
  case twoThirds
  case pot
  case allIn

  public var label: String {
    switch self {
    case .third: "⅓"
    case .half: "½"
    case .twoThirds: "⅔"
    case .pot: "Pot"
    case .allIn: "All-in"
    }
  }

  /// Share of the pot after calling; nil for all-in.
  public var fraction: Double? {
    switch self {
    case .third: 1.0 / 3.0
    case .half: 0.5
    case .twoThirds: 2.0 / 3.0
    case .pot: 1
    case .allIn: nil
    }
  }
}

/// Pure bet-sizing maths for the action bar. Every result is a legal "to" total or nil when no raise exists.
public enum BetSizing {
  /// `currentBet + fraction * (potTotal + toCall)`, clamped. `potTotal` counts every chip in the middle.
  public static func raiseTo(_ preset: BetPreset, legal: LegalActions, potTotal: Int) -> Int? {
    guard let fraction = preset.fraction else { return legal.allInTo ?? legal.maxRaiseTo }
    let raw = legal.currentBet + Int((Double(potTotal + legal.toCall) * fraction).rounded())
    return clamp(raw, legal: legal)
  }

  /// A sensible starting size: half pot for a bet, three times the current bet for a raise.
  public static func defaultRaiseTo(legal: LegalActions, potTotal: Int, bigBlind: Int) -> Int? {
    if legal.currentBet == 0 {
      return raiseTo(.half, legal: legal, potTotal: potTotal)
    }
    return clamp(legal.currentBet * 3, legal: legal)
  }

  /// Moves by `steps` big blinds, staying inside the legal range.
  public static func step(_ raiseTo: Int, by steps: Int, legal: LegalActions, bigBlind: Int) -> Int {
    let moved = raiseTo + steps * max(1, bigBlind)
    return clamp(moved, legal: legal) ?? raiseTo
  }

  /// Forces `amount` into the legal range (rounded down to a chip-unit multiple, never below the minimum).
  /// With no raise range, a short all-in is the only size.
  public static func clamp(_ amount: Int, legal: LegalActions) -> Int? {
    guard let range = legal.raiseRange else { return legal.allInTo }
    if amount >= range.upperBound { return range.upperBound }
    let unit = max(1, legal.chipUnit)
    let rounded = amount - ((amount % unit) + unit) % unit
    return min(max(rounded, range.lowerBound), range.upperBound)
  }

  /// The engine action for a chosen size; nil when it is not legal.
  public static func action(raiseTo: Int, legal: LegalActions) -> Action? {
    if let allIn = legal.allInTo, raiseTo == allIn { return .allIn }
    let action: Action
    switch legal.raiseKind {
    case .bet?: action = .bet(to: raiseTo)
    case .raise?: action = .raise(to: raiseTo)
    case nil: return nil
    }
    return legal.isLegal(action) ? action : nil
  }

  /// What the primary button does: check, call, a short all-in call, or (nothing else possible) fold.
  public static func checkCallAction(_ legal: LegalActions) -> Action {
    if legal.canCheck { return .check }
    if legal.canCall { return .call }
    if legal.canAllIn { return .allIn }
    return .fold
  }

  public static func checkCallLabel(_ legal: LegalActions) -> String {
    if legal.canCheck { return "Check" }
    if legal.callIsAllIn { return "Call all-in \(legal.stack)" }
    if legal.canCall { return "Call \(legal.callAmount)" }
    return "Check"
  }
}
