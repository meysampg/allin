import Foundation
import PokerCore
import PokerEquity

/// The facts a decision's explanation is written from.
struct ReviewedDecisionDraft {
  let graded: GradedDecision
  let kind: DecisionKind
  let focusName: String?
  let focusStyle: String?
  let equityVsFocus: Double?
  let potOddsNeeded: Double?
}

/// Pure templates: the same inputs always give the same text.
public enum ReviewNarrator {
  static let minus = "\u{2212}"

  // MARK: Hand level

  /// "You won 29 · decisions: 3 good, 1 leak".
  public static func headline(_ analysis: HandAnalysis) -> String {
    let result: String
    if analysis.netChips > 0 {
      result = "You won \(analysis.netChips)"
    } else if analysis.netChips < 0 {
      result = "You lost \(-analysis.netChips)"
    } else {
      result = "You broke even"
    }
    return "\(result) · decisions: \(countsPhrase(analysis.counts))"
  }

  static func countsPhrase(_ counts: GradeCounts) -> String {
    var parts: [String] = []
    if counts.good > 0 { parts.append("\(counts.good) good") }
    if counts.smallMiss > 0 {
      parts.append("\(counts.smallMiss) small miss\(counts.smallMiss == 1 ? "" : "es")")
    }
    if counts.leak > 0 { parts.append("\(counts.leak) leak\(counts.leak == 1 ? "" : "s")") }
    return parts.isEmpty ? "no decisions" : parts.joined(separator: ", ")
  }

  /// "Chips +420 (luck −60)"; nil unless the hand went all-in.
  public static func luckText(_ analysis: HandAnalysis) -> String? {
    guard analysis.luck.wasAllIn else { return nil }
    return "Chips \(signed(analysis.netChips)) (luck \(signed(Int(analysis.luck.luckChips.rounded()))))"
  }

  static func signed(_ value: Int) -> String { value < 0 ? "\(minus)\(-value)" : "+\(value)" }

  // MARK: Decision level

  /// One sentence about the focus villain's style; empty for an unknown style.
  public static func styleSentence(name: String, style: String?) -> String {
    switch style?.trimmingCharacters(in: .whitespaces).lowercased() {
    case "calling station": "\(name) is a calling station. They call with any pair and many draws."
    case "maniac": "\(name) bets and raises far too often, with many bluffs."
    case "rock", "nit": "\(name) plays few hands and rarely bluffs, so their bets mean strength."
    case "balanced": "\(name) mixes value bets and bluffs, so there is no simple exploit."
    case "loose-passive, never bluffs": "\(name) calls a lot but never bluffs: when they bet, believe them."
    case "loose beginner": "\(name) plays too many hands and calls too often."
    default: ""
    }
  }

  /// "open BTN", "3-bet", "c-bet ⅓", "value bet", "bluff", "check", "call", "fold", "bet ⅔", "raise", "all-in".
  public static func tag(for action: Action, context: DecisionContext, heroCards: [Card]) -> String {
    let legal = context.legal
    let aggressive = DecisionClassifier.actionClass(action, legal: legal) == .aggressive
    let facing = DecisionClassifier.facing(context)
    let priorRaises = DecisionClassifier.aggressiveCount(context, street: context.street)
    if aggressive {
      if context.street == .preflop {
        if priorRaises == 0 {
          let position = TablePosition.of(
            seat: context.seat, button: context.button, seats: context.seats.map(\.seat))
          return "open \(positionName(position))"
        }
        return "\(priorRaises + 2)-bet"
      }
      if facing == .none {
        if context.street == .flop, SpotFeatures(context).preflopAggressor == context.seat {
          return "c-bet \(fractionName(action, context: context))"
        }
        if context.street == .river, context.board.count == 5 {
          switch HandFeatures(hole: heroCards, board: context.board).bucket {
          case .medium, .strong, .nutted: return "value bet"
          case .air, .draw: return "bluff"
          case .weakMade: break
          }
        }
      }
    }
    switch action {
    case .fold: return "fold"
    case .check: return "check"
    case .call: return "call"
    case .bet: return "bet \(fractionName(action, context: context))"
    case .raise: return "raise"
    case .allIn: return legal.callIsAllIn && legal.canCall ? "call" : "all-in"
    }
  }

  /// "✓ open BTN" | "≈ call (−0.6 bb)" | "✗ check (−3.1 bb)".
  public static func timelineText(tag: String, graded: GradedDecision) -> String {
    switch graded.grade {
    case .good: "✓ \(tag)"
    case .smallMiss: "≈ \(tag) (\(minus)\(oneDecimal(graded.evLossBB)) bb)"
    case .leak: "✗ \(tag) (\(minus)\(oneDecimal(graded.evLossBB)) bb)"
    }
  }

  /// "Turn: you checked. Better: bet ⅔ pot."
  public static func title(street: Street, graded: GradedDecision, context: DecisionContext) -> String {
    let name = street.rawValue.prefix(1).uppercased() + street.rawValue.dropFirst()
    let chosen = graded.chosen
    let best = graded.best
    if graded.grade == .good {
      if chosen.action == best.action || graded.evLossBB == 0 {
        return "\(name): you \(past(chosen.action, context: context)). That was the best play."
      }
      return
        "\(name): close spot: \(chosen.shortLabel) and \(best.shortLabel) are within \(oneDecimal(graded.toleranceBB)) bb."
    }
    return "\(name): you \(past(chosen.action, context: context)). Better: \(phrase(best.action, context: context))."
  }

  static func body(decision: ReviewedDecisionDraft) -> String {
    var sentences: [String] = []
    if let name = decision.focusName {
      let style = styleSentence(name: name, style: decision.focusStyle)
      if !style.isEmpty { sentences.append(style) }
    }
    sentences.append(reason(decision))
    return sentences.joined(separator: " ")
  }

  private static func reason(_ d: ReviewedDecisionDraft) -> String {
    if d.graded.grade == .good { return "That matches the best play by expected value." }
    let eq = d.equityVsFocus.map { percent($0) }
    let need = d.potOddsNeeded.map { percent($0) }
    switch (d.kind.chosen, d.kind.best) {
    case (.passive, .aggressive):
      if let eq {
        return "Your hand is ahead of most of what they continue with (about \(eq)%), so betting earns more."
      }
    case (.fold, .passive):
      if let eq, let need { return "You need \(need)% to call and have about \(eq)% against their range." }
    case (.passive, .fold):
      if let eq, let need { return "You need \(need)% but have only about \(eq)% against their range." }
    case (.aggressive, .passive):
      return "Against their range, betting mostly gets called by better hands or folds out worse ones."
    default:
      break
    }
    return "\(d.graded.best.label) has the highest expected value here."
  }

  // MARK: Formatting

  private static func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }

  static func oneDecimal(_ value: Double) -> String {
    let tenths = Int((value * 10).rounded())
    return "\(tenths / 10).\(tenths % 10)"
  }

  private static func positionName(_ position: TablePosition) -> String {
    switch position {
    case .early: "UTG"
    case .middle: "HJ"
    case .cutoff: "CO"
    case .button: "BTN"
    case .smallBlind: "SB"
    case .bigBlind: "BB"
    }
  }

  private static func fractionName(_ action: Action, context: DecisionContext) -> String {
    ActionLabel.potFractionName(ActionLabel.fraction(to: target(action, context: context), context: context))
  }

  private static func target(_ action: Action, context: DecisionContext) -> Int {
    switch action {
    case .bet(let to), .raise(let to): to
    default: context.legal.allInTo ?? context.legal.committed + context.legal.stack
    }
  }

  /// "bet ⅔ pot", "bet the pot", "raise to 90", "check".
  static func phrase(_ action: Action, context: DecisionContext) -> String {
    switch action {
    case .fold: return "fold"
    case .check: return "check"
    case .call: return "call"
    case .bet(let to):
      let name = ActionLabel.potFractionName(ActionLabel.fraction(to: to, context: context))
      return name == "pot" ? "bet the pot" : "bet \(name) pot"
    case .raise(let to): return "raise to \(to)"
    case .allIn: return context.legal.callIsAllIn && context.legal.canCall ? "call all-in" : "go all-in"
    }
  }

  private static func past(_ action: Action, context: DecisionContext) -> String {
    switch action {
    case .fold: "folded"
    case .check: "checked"
    case .call: "called"
    case .bet: phrase(action, context: context)
    case .raise(let to): "raised to \(to)"
    case .allIn: context.legal.callIsAllIn && context.legal.canCall ? "called all-in" : "went all-in"
    }
  }
}
