import Foundation
import PokerAnalysis
import PokerCore

/// Verdict texts.
enum Verdicts {
  static func noun(_ answerClass: String) -> String {
    answerClass == "allin" ? "all-in" : answerClass
  }

  static func gerund(_ answerClass: String) -> String {
    switch answerClass {
    case "fold": "Folding"
    case "check": "Checking"
    case "call": "Calling"
    case "bet": "Betting"
    case "raise": "Raising"
    case "allin": "Going all-in"
    default: answerClass.capitalized
    }
  }

  private static func lowerFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.lowercased() + text.dropFirst()
  }

  /// "+1.8 big blinds on average".
  static func average(_ evBB: Double) -> String {
    let rounded = (evBB * 10).rounded() / 10
    let body = TextBinder.number(abs(rounded))
    let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
    return "\(sign)\(body) big \(abs(rounded) == 1 ? "blind" : "blinds") on average"
  }

  static func ev(_ graded: GradedDecision, chosenClass: String, bestClass: String) -> (title: String, detail: String) {
    switch graded.grade {
    case .good:
      return ("✓ Good \(noun(chosenClass))", average(graded.chosen.evBB))
    case .smallMiss:
      return (
        "≈ Close: \(lowerFirst(graded.best.shortLabel)) was a bit better",
        "\(TextBinder.bb(-graded.evLossBB, signed: true)) against \(graded.best.label)"
      )
    case .leak:
      return (
        "✗ \(gerund(bestClass)) was better",
        "\(TextBinder.bb(-graded.evLossBB, signed: true)) against \(graded.best.label)"
      )
    }
  }

  static func exact(_ grade: Grade, solution: SpotSolution, detail: String? = nil) -> (title: String, detail: String) {
    let text = detail ?? solution.explanation
    switch grade {
    case .good: return ("✓ Correct", text)
    case .smallMiss: return ("≈ Close: \(solution.answerText)", text)
    case .leak: return ("✗ Not quite: \(solution.answerText)", text)
    }
  }
}
