import Foundation
import PokerAnalysis
import PokerCore
import PokerEquity

/// The solved form of a spot: the correct answer, the options and everything the verdict and the text need.
public struct SpotSolution: Sendable, Hashable {
  public let templateID: String
  public let method: EvaluationMethod
  public let question: QuestionType
  /// Empty for pickCards, number and rangePaint.
  public let options: [AnswerOption]
  /// The canonical correct answer.
  public let correct: SpotResponse
  public let answerClass: String
  public var decisionType: DecisionTypeKey { DecisionTypeKey(templateID: templateID, answerClass: answerClass) }
  /// Restricted to the options, in option order (EV methods).
  public let evs: ActionEVResult?
  /// Best minus second (EV methods).
  public let gapBB: Double?
  /// Number questions.
  public let tolerance: Int?
  /// pickCards selection size (nil = any).
  public let pick: Int?
  /// Tracked ranges used (empty for exact methods).
  public let villainRanges: [Int: HandRange]
  /// Every key the method provides.
  public let bindings: TextBindings
  /// `clamp(template.difficulty + (isEV && gap < 2·minGap ? 0.1 : 0), 0, 1)`.
  public let difficulty: Double
  /// Bound: template hint, else the method default.
  public let hint: String

  // Facts the verdict and grading need (not part of the M5 contract; additive).
  /// The decision's pot in chips, current bets included (EV methods).
  public let potBefore: Int
  public let bigBlind: Int
  public let heroCards: [Card]
  public let boardCards: [Card]
  /// Short statement of the answer for a miss: "Bram wins", "the pot is 150".
  public let answerText: String
  /// Why the answer is right: "Two Pair, Kings and Nines beats Pair of Kings".
  public let explanation: String

  public init(
    templateID: String, method: EvaluationMethod, question: QuestionType, options: [AnswerOption],
    correct: SpotResponse, answerClass: String, evs: ActionEVResult? = nil, gapBB: Double? = nil,
    tolerance: Int? = nil, pick: Int? = nil, villainRanges: [Int: HandRange] = [:],
    bindings: TextBindings = TextBindings(), difficulty: Double, hint: String, potBefore: Int = 0,
    bigBlind: Int = 1, heroCards: [Card] = [], boardCards: [Card] = [], answerText: String = "",
    explanation: String = ""
  ) {
    self.templateID = templateID
    self.method = method
    self.question = question
    self.options = options
    self.correct = correct
    self.answerClass = answerClass
    self.evs = evs
    self.gapBB = gapBB
    self.tolerance = tolerance
    self.pick = pick
    self.villainRanges = villainRanges
    self.bindings = bindings
    self.difficulty = difficulty
    self.hint = hint
    self.potBefore = potBefore
    self.bigBlind = bigBlind
    self.heroCards = heroCards
    self.boardCards = boardCards
    self.answerText = answerText
    self.explanation = explanation
  }

  func replacingHint(_ hint: String) -> SpotSolution {
    SpotSolution(
      templateID: templateID, method: method, question: question, options: options, correct: correct,
      answerClass: answerClass, evs: evs, gapBB: gapBB, tolerance: tolerance, pick: pick,
      villainRanges: villainRanges, bindings: bindings, difficulty: difficulty, hint: hint, potBefore: potBefore,
      bigBlind: bigBlind, heroCards: heroCards, boardCards: boardCards, answerText: answerText,
      explanation: explanation)
  }
}
