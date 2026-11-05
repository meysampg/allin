import Foundation
import PokerCore
import PokerEquity

/// Methods that count cards or hands: outs and hands that beat the hero.
enum CountMethods {
  // MARK: Outs

  static func outs(_ input: EvalInput) throws -> Draft {
    let outs = BoardAnalyzer.outs(hole: input.heroCards, board: input.board)
    let count = outs.count
    let answerClass = count == 0 ? "none" : (count <= 8 ? "few" : "many")
    var draft: Draft
    if input.template.question.type == .number {
      draft = Draft(correct: .number(count), answerClass: answerClass)
      draft.tolerance = input.template.question.tolerance ?? 1
    } else {
      draft = Draft(correct: .cards(outs), answerClass: answerClass)
      draft.pick = input.template.question.pick
    }
    draft.bindings["outs"] = outs.isEmpty ? "none" : TextBinder.pretty(outs)
    draft.bindings["outsCount"] = String(count)
    draft.answerText = "you have \(count) out\(count == 1 ? "" : "s")"
    draft.explanation =
      outs.isEmpty
      ? "No unseen card makes a straight or better."
      : "\(count) card\(count == 1 ? "" : "s") make a straight or better: \(TextBinder.pretty(outs))."
    return draft
  }

  // MARK: Hands that beat the hero

  static let defaultBuckets: [CountBucket] = [
    CountBucket(id: "none", label: "None", range: IntRangeSpec(lo: 0, hi: 0)),
    CountBucket(id: "few", label: "A few", range: IntRangeSpec(lo: 1, hi: 20)),
    CountBucket(id: "many", label: "Many", range: IntRangeSpec(lo: 21, hi: 1326)),
  ]

  static func beatsMeCount(_ input: EvalInput) throws -> Draft {
    let beating = BoardAnalyzer.beatingHands(hole: input.heroCards, board: input.board)
    let count = beating.reduce(0) { $0 + $1.combos.count }
    let buckets = input.template.evaluation.buckets ?? defaultBuckets
    let bucket = buckets.first { $0.range.range.contains(count) }
    var draft: Draft
    if input.template.question.type == .number {
      draft = Draft(correct: .number(count), answerClass: bucket?.id ?? "other")
      draft.tolerance = input.template.question.tolerance ?? max(1, Int((0.2 * Double(count)).rounded()))
    } else {
      guard let bucket else { throw SpotEvaluationError.invalid("no bucket holds \(count)") }
      draft = Draft(correct: .option(bucket.id), answerClass: bucket.id)
      let listed = (input.template.question.options ?? []).compactMap { id in buckets.first { $0.id == id } }
      var shown = listed.isEmpty ? buckets : listed
      if !shown.contains(where: { $0.id == bucket.id }) { shown.append(bucket) }
      draft.options = shown.map { AnswerOption(id: $0.id, label: $0.label) }
    }
    draft.bindings["beatsMeCount"] = String(count)
    draft.answerText = count == 0 ? "no hand beats you" : "\(count) hand\(count == 1 ? "" : "s") beat you"
    if let best = beating.first {
      draft.explanation = "\(count) combos beat you, the best being \(best.description)."
    } else {
      draft.explanation = "You hold the nuts: no hand beats you."
    }
    return draft
  }
}
