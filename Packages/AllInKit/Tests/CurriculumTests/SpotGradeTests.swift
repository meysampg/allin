import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SpotGradeTests {
  static func solution(
    method: EvaluationMethod, question: QuestionType, correct: SpotResponse, tolerance: Int? = nil,
    pick: Int? = nil, text: String = "the answer is X"
  ) -> SpotSolution {
    SpotSolution(
      templateID: "test.grade", method: method, question: question, options: [], correct: correct,
      answerClass: "x", tolerance: tolerance, pick: pick, difficulty: 0.3, hint: "", answerText: text,
      explanation: "because")
  }

  // MARK: Numbers

  @Test func numberToleranceBands() {
    let solution = Self.solution(method: .potCount, question: .number, correct: .number(100), tolerance: 5)
    func grade(_ n: Int) -> (Grade, Double) {
      let g = SpotEvaluator.grade(.number(n), solution: solution)
      return (g.grade, g.quality)
    }
    #expect(grade(100) == (.good, 1))
    #expect(grade(95) == (.good, 1))
    #expect(grade(105) == (.good, 1))
    #expect(grade(106) == (.smallMiss, 0.5))
    #expect(grade(90) == (.smallMiss, 0.5))
    #expect(grade(89) == (.leak, 0))
    #expect(grade(0) == (.leak, 0))
    #expect(SpotEvaluator.grade(.number(106), solution: solution).isCorrect == false)
    #expect(SpotEvaluator.grade(.number(100), solution: solution).verdictTitle == "✓ Correct")
    #expect(SpotEvaluator.grade(.number(0), solution: solution).verdictTitle == "✗ Not quite: the answer is X")
  }

  @Test func zeroToleranceIsExact() {
    let solution = Self.solution(method: .legalSizes, question: .number, correct: .number(40), tolerance: 0)
    #expect(SpotEvaluator.grade(.number(40), solution: solution).grade == .good)
    #expect(SpotEvaluator.grade(.number(41), solution: solution).grade == .leak)
  }

  @Test func aWrongKindOfResponseIsAMiss() {
    let solution = Self.solution(method: .potCount, question: .number, correct: .number(40), tolerance: 0)
    let grade = SpotEvaluator.grade(.option("x"), solution: solution)
    #expect(grade.grade == .leak && grade.quality == 0 && !grade.isCorrect)
  }

  // MARK: Cards

  @Test func outsF1() {
    let outs = EvaluationTestSupport.cards("5c5d5h5s" + "Tc" + "Td" + "Th" + "Ts")
    let solution = Self.solution(method: .outs, question: .pickCards, correct: .cards(outs))
    #expect(SpotEvaluator.grade(.cards(outs), solution: solution).grade == .good)
    // Seven of eight: precision 1, recall 7/8, F1 = 14/15.
    let missing = SpotEvaluator.grade(.cards(Array(outs.dropLast())), solution: solution)
    #expect(missing.grade == .smallMiss)
    #expect(abs(missing.quality - 14.0 / 15.0) < 1e-9)
    // One extra: precision 8/9, recall 1, F1 = 16/17.
    let extra = SpotEvaluator.grade(.cards(outs + EvaluationTestSupport.cards("2c")), solution: solution)
    #expect(extra.grade == .smallMiss)
    #expect(abs(extra.quality - 16.0 / 17.0) < 1e-9)
    // Half of them: F1 = 2/3, below 0.75.
    let half = SpotEvaluator.grade(.cards(Array(outs.prefix(4))), solution: solution)
    #expect(half.grade == .leak && half.quality == 0)
    // Exactly 0.75: precision 1 and recall 0.6 is F1 0.75.
    let five = Self.solution(
      method: .outs, question: .pickCards, correct: .cards(EvaluationTestSupport.cards("5c5d5h5s" + "Tc")))
    let three = SpotEvaluator.grade(.cards(EvaluationTestSupport.cards("5c5d5h")), solution: five)
    #expect(three.grade == .smallMiss && abs(three.quality - 0.75) < 1e-9)
  }

  @Test func pickSizeIsEnforced() {
    let cards = EvaluationTestSupport.cards("5c5d")
    let solution = Self.solution(method: .outs, question: .pickCards, correct: .cards(cards), pick: 2)
    #expect(SpotEvaluator.grade(.cards(cards), solution: solution).grade == .good)
    #expect(SpotEvaluator.grade(.cards(cards + EvaluationTestSupport.cards("5h")), solution: solution).grade == .leak)
  }

  // MARK: Options

  @Test func optionsAreExact() {
    let solution = Self.solution(
      method: .nextToAct, question: .choice, correct: .option("seat:2"), text: "Bram acts next")
    #expect(SpotEvaluator.grade(.option("seat:2"), solution: solution).isCorrect)
    let miss = SpotEvaluator.grade(.option("seat:3"), solution: solution)
    #expect(miss.grade == .leak && miss.verdictTitle == "✗ Not quite: Bram acts next")
    #expect(miss.verdictDetail == "because")
  }

  // MARK: Expected value

  static func candidate(_ action: Action, _ label: String, _ short: String, _ ev: Double, se: Double = 0)
    -> CandidateEV
  {
    CandidateEV(
      action: action, label: label, shortLabel: short, evBB: ev, standardError: se, samples: 100,
      method: se == 0 ? .closedForm : .rollout)
  }

  /// Pot 100 chips at 2 per big blind: 50 bb. Good band max(0.15, 0.02 * 50) = 1 bb, small misses up to 5 bb.
  static func evSolution(_ evs: [CandidateEV], ids: [String]) -> SpotSolution {
    let result = ActionEVResult(candidates: evs)
    return SpotSolution(
      templateID: "test.ev", method: .policyEV, question: .action,
      options: zip(ids, evs).map { AnswerOption(id: $0, label: $1.label, evBB: $1.evBB) },
      correct: .option(ids[evs.firstIndex { $0.action == result.best.action }!]),
      answerClass: String(ids[0].split(separator: ":")[0]), evs: result, gapBB: 1, difficulty: 0.3, hint: "",
      potBefore: 100, bigBlind: 2)
  }

  @Test func evGradesComeFromTheDecisionGrader() {
    let solution = Self.evSolution(
      [
        Self.candidate(.fold, "Fold", "Fold", 0),
        Self.candidate(.call, "Call 20", "Call", -3),
        Self.candidate(.raise(to: 60), "Raise to 60", "Raise ⅔", -9),
      ], ids: ["fold", "call", "raise:3"])
    let fold = SpotEvaluator.grade(.option("fold"), solution: solution)
    #expect(fold.grade == .good && fold.quality == 1 && fold.isCorrect)
    #expect(fold.verdictTitle == "✓ Good fold")
    #expect(fold.verdictDetail == "0 big blinds on average")
    #expect(fold.evLossBB == 0 && fold.graded != nil)

    let call = SpotEvaluator.grade(.option("call"), solution: solution)
    #expect(call.grade == .smallMiss && !call.isCorrect)
    #expect(call.verdictTitle == "≈ Close: fold was a bit better")
    #expect(call.verdictDetail == "−3 bb against Fold")
    #expect(abs(call.quality - (1 - 3.0 / 12.5)) < 1e-9)

    let raise = SpotEvaluator.grade(.option("raise:3"), solution: solution)
    #expect(raise.grade == .leak && raise.quality == 0.0 || raise.grade == .leak)
    #expect(raise.verdictTitle == "✗ Folding was better")
    #expect(raise.verdictDetail == "−9 bb against Fold")
    #expect(raise.evLossBB == 9)
  }

  @Test func evGoodCallShowsTheSignedEV() {
    let solution = Self.evSolution(
      [
        Self.candidate(.fold, "Fold", "Fold", 0),
        Self.candidate(.call, "Call 20", "Call", 1.84),
        Self.candidate(.raise(to: 60), "Raise to 60", "Raise ⅔", 1.2),
      ], ids: ["fold", "call", "raise:3"])
    let call = SpotEvaluator.grade(.option("call"), solution: solution)
    #expect(call.verdictTitle == "✓ Good call")
    #expect(call.verdictDetail == "+1.8 big blinds on average")
    // Within the good band of the best (0.64 < 1 bb).
    let raise = SpotEvaluator.grade(.option("raise:3"), solution: solution)
    #expect(raise.grade == .good && raise.verdictTitle == "✓ Good raise")
    let fold = SpotEvaluator.grade(.option("fold"), solution: solution)
    #expect(fold.grade == .smallMiss)
    #expect(fold.verdictTitle == "≈ Close: call was a bit better")
  }

  @Test func evNoiseWidensTheGoodBand() {
    // 2 bb apart, but the estimates are noisy: 2 * sqrt(1.5^2 + 1.5^2) = 4.2 bb.
    let solution = Self.evSolution(
      [
        Self.candidate(.check, "Check", "Check", 0.0, se: 1.5),
        Self.candidate(.bet(to: 30), "Bet 30 (½ pot)", "Bet ½", 2.0, se: 1.5),
      ], ids: ["check", "bet:0.5"])
    #expect(SpotEvaluator.grade(.option("check"), solution: solution).grade == .good)
  }

  @Test func evUnknownOptionIsAMiss() {
    let solution = Self.evSolution(
      [Self.candidate(.fold, "Fold", "Fold", 0), Self.candidate(.call, "Call 20", "Call", 1)], ids: ["fold", "call"])
    let grade = SpotEvaluator.grade(.option("allin"), solution: solution)
    #expect(grade.grade == .leak && grade.graded == nil)
  }

  @Test func allInVerdictWords() {
    #expect(Verdicts.noun("allin") == "all-in")
    #expect(Verdicts.gerund("allin") == "Going all-in")
    #expect(Verdicts.gerund("bet") == "Betting")
    #expect(Verdicts.gerund("raise") == "Raising")
    #expect(Verdicts.gerund("check") == "Checking")
    #expect(Verdicts.average(1) == "+1 big blind on average")
    #expect(Verdicts.average(-0.44) == "−0.4 big blinds on average")
  }
}
