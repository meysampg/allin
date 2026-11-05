import Foundation
import PokerAnalysis
import PokerCore
import PokerEquity

extension SpotEvaluator {
  /// Grades a response from the solution alone.
  public static func grade(
    _ response: SpotResponse, solution: SpotSolution, tolerance: GradingTolerance = .standard
  ) -> SpotGrade {
    if solution.method.isEV { return gradeEV(response, solution: solution, tolerance: tolerance) }
    switch solution.correct {
    case .option(let correct):
      if case .option(let given) = response { return exact(given == correct, solution) }
      return exact(false, solution)
    case .options(let correct):
      if case .options(let given) = response { return exact(given == correct, solution) }
      return exact(false, solution)
    case .number(let correct):
      if case .number(let given) = response { return gradeNumber(given, correct: correct, solution: solution) }
      return exact(false, solution)
    case .cards(let correct):
      if case .cards(let given) = response { return gradeCards(given, correct: correct, solution: solution) }
      return exact(false, solution)
    case .range(let target):
      if case .range(let given) = response { return gradeRange(given, target: target, solution: solution) }
      return exact(false, solution)
    }
  }

  private static func exact(_ isCorrect: Bool, _ solution: SpotSolution) -> SpotGrade {
    let grade: Grade = isCorrect ? .good : .leak
    let verdict = Verdicts.exact(grade, solution: solution)
    return SpotGrade(
      grade: grade, quality: isCorrect ? 1 : 0, isCorrect: isCorrect, verdictTitle: verdict.title,
      verdictDetail: verdict.detail)
  }

  // MARK: EV

  private static func gradeEV(_ response: SpotResponse, solution: SpotSolution, tolerance: GradingTolerance)
    -> SpotGrade
  {
    guard case .option(let id) = response, let index = solution.options.firstIndex(where: { $0.id == id }),
      let evs = solution.evs, index < evs.candidates.count
    else { return exact(false, solution) }
    let graded = DecisionGrader.grade(
      evs, chosen: evs.candidates[index].action, potBefore: solution.potBefore, bigBlind: solution.bigBlind,
      tolerance: tolerance)
    let bestIndex = evs.candidates.firstIndex { $0.action == graded.best.action } ?? 0
    let verdict = Verdicts.ev(
      graded, chosenClass: tokenClass(id), bestClass: tokenClass(solution.options[bestIndex].id))
    return SpotGrade(
      grade: graded.grade, quality: graded.quality, isCorrect: graded.grade == .good, evLossBB: graded.evLossBB,
      graded: graded, verdictTitle: verdict.title, verdictDetail: verdict.detail)
  }

  private static func tokenClass(_ token: String) -> String { String(token.split(separator: ":")[0]) }

  // MARK: Numbers

  private static func gradeNumber(_ given: Int, correct: Int, solution: SpotSolution) -> SpotGrade {
    let tolerance = solution.tolerance ?? 0
    let distance = abs(given - correct)
    let grade: Grade
    let quality: Double
    if distance <= tolerance {
      grade = .good
      quality = 1
    } else if distance <= 2 * tolerance {
      grade = .smallMiss
      quality = 0.5
    } else {
      grade = .leak
      quality = 0
    }
    let verdict = Verdicts.exact(grade, solution: solution)
    return SpotGrade(
      grade: grade, quality: quality, isCorrect: grade == .good, verdictTitle: verdict.title,
      verdictDetail: verdict.detail)
  }

  // MARK: Cards

  private static func gradeCards(_ given: [Card], correct: [Card], solution: SpotSolution) -> SpotGrade {
    switch solution.method {
    case .bestFive:
      let pool = Set(solution.heroCards + solution.boardCards)
      let distinct = Set(given)
      let valid =
        given.count == 5 && distinct.count == 5 && distinct.isSubset(of: pool)
        && HandEvaluator.evaluate(given) == HandEvaluator.evaluate(correct)
      return exact(valid, solution)
    case .nuts:
      let board = Set(solution.boardCards)
      let distinct = Set(given)
      let valid =
        given.count == 2 && distinct.count == 2 && distinct.isDisjoint(with: board)
        && HandEvaluator.evaluate(given + solution.boardCards)
          == HandEvaluator.evaluate(correct + solution.boardCards)
      return exact(valid, solution)
    default:
      if let pick = solution.pick, given.count != pick { return exact(false, solution) }
      let g = Set(given)
      let c = Set(correct)
      if g == c { return exact(true, solution) }
      let hits = Double(g.intersection(c).count)
      let precision = g.isEmpty ? 0 : hits / Double(g.count)
      let recall = c.isEmpty ? 0 : hits / Double(c.count)
      let f1 = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
      let grade: Grade = f1 >= 0.75 - 1e-9 ? .smallMiss : .leak
      let verdict = Verdicts.exact(grade, solution: solution)
      return SpotGrade(
        grade: grade, quality: grade == .smallMiss ? f1 : 0, isCorrect: false, verdictTitle: verdict.title,
        verdictDetail: verdict.detail)
    }
  }

  // MARK: Ranges

  /// Σ min(u,t)·n / Σ max(u,t)·n over the hand classes, n = live combos.
  static func rangeScore(_ given: HandRange, target: HandRange, dead: CardSet) -> Double {
    var low = 0.0
    var high = 0.0
    for handClass in HandClass.all {
      let n = Double(handClass.combos.filter { $0.mask.isDisjoint(with: dead) }.count)
      guard n > 0 else { continue }
      let u = Double(given.weight(of: handClass))
      let t = Double(target.weight(of: handClass))
      low += min(u, t) * n
      high += max(u, t) * n
    }
    return high > 0 ? low / high : 1
  }

  private static func gradeRange(_ given: HandRange, target: HandRange, solution: SpotSolution) -> SpotGrade {
    let score = rangeScore(given, target: target, dead: CardSet(solution.heroCards + solution.boardCards))
    let grade: Grade = score >= 0.75 ? .good : (score >= 0.55 ? .smallMiss : .leak)
    let verdict = Verdicts.exact(
      grade, solution: solution, detail: "Your range matches \(TextBinder.percent(score)). \(solution.explanation)")
    return SpotGrade(
      grade: grade, quality: score, isCorrect: grade == .good, verdictTitle: verdict.title,
      verdictDetail: verdict.detail)
  }
}
