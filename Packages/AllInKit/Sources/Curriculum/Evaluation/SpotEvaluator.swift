import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity

public enum SpotEvaluationError: Error, Sendable, Equatable, CustomStringConvertible {
  case heroNotToAct
  case needsOneVillain
  case optionUnavailable(String)
  case invalid(String)

  public var description: String {
    switch self {
    case .heroNotToAct: "the hero is not the seat to act"
    case .needsOneVillain: "this method needs exactly one live villain"
    case .optionUnavailable(let option): "option '\(option)' is not available in this spot"
    case .invalid(let message): message
    }
  }
}

/// Everything a method needs to solve one instance.
struct EvalInput: Sendable {
  let instance: SpotInstance
  let template: SpotTemplate
  let characters: CharacterCatalog
  let budget: EvaluationBudget

  var heroCards: [Card] { instance.holeCards[instance.heroSeat] ?? [] }
  var board: [Card] { instance.board }
  var bigBlind: Int { instance.config.bigBlind }

  func name(_ seat: Int) -> String { instance.seatNames[seat] ?? "Seat \(seat + 1)" }

  func heroContext() throws -> DecisionContext {
    guard let context = instance.heroContext else { throw SpotEvaluationError.heroNotToAct }
    return context
  }

  /// The single live opponent of the hero.
  func soleVillain(_ context: DecisionContext) throws -> Int {
    let live = context.liveSeats.filter { $0 != instance.heroSeat }
    guard live.count == 1 else { throw SpotEvaluationError.needsOneVillain }
    return live[0]
  }
}

/// What a method decides; `finish` adds the common fields.
struct Draft {
  var options: [AnswerOption] = []
  var correct: SpotResponse
  var answerClass: String
  var evs: ActionEVResult?
  var gapBB: Double?
  var tolerance: Int?
  var pick: Int?
  var villainRanges: [Int: HandRange] = [:]
  var bindings = TextBindings()
  var potBefore = 0
  var answerText = ""
  var explanation = ""

  init(correct: SpotResponse, answerClass: String) {
    self.correct = correct
    self.answerClass = answerClass
  }
}

extension EvalInput {
  func finish(_ draft: Draft) throws -> SpotSolution {
    let method = template.evaluation.method
    let bindings = TextBinder.bindings(for: instance, characters: characters).merging(draft.bindings)
    var difficulty = template.difficulty
    if method.isEV, let gap = draft.gapBB, let minGap = template.quality.minGapBB, gap < 2 * minGap {
      difficulty += 0.1
    }
    difficulty = min(max(difficulty, 0), 1)
    let hintText = template.hint ?? SpotEvaluator.defaultHint(for: method)
    let hint: String
    do {
      hint = try TextBinder.bind(hintText, bindings)
    } catch {
      throw SpotEvaluationError.invalid("hint of \(template.id): \(error)")
    }
    return SpotSolution(
      templateID: template.id, method: method, question: template.question.type, options: draft.options,
      correct: draft.correct, answerClass: draft.answerClass, evs: draft.evs, gapBB: draft.gapBB,
      tolerance: draft.tolerance, pick: draft.pick, villainRanges: draft.villainRanges, bindings: bindings,
      difficulty: difficulty, hint: hint, potBefore: draft.potBefore, bigBlind: bigBlind, heroCards: heroCards,
      boardCards: board, answerText: draft.answerText, explanation: draft.explanation)
  }
}

/// Solves spots (the correct answer, the options, the numbers behind them) and grades responses.
public struct SpotEvaluator: Sendable {
  let characters: CharacterCatalog
  let budget: EvaluationBudget

  public init(characters: CharacterCatalog, budget: EvaluationBudget = .lesson) {
    self.characters = characters
    self.budget = budget
  }

  public static func defaultHint(for method: EvaluationMethod) -> String {
    switch method {
    case .closedFormEV, .pushFold: "Compare the price ({priceNeeded}) with your chance to win ({equity})."
    case .policyEV: "Which of {villain}'s hands call, and which fold?"
    case .showdownWinner, .bestFive: "Build each best five from all seven cards."
    case .nuts: "What is the best hand this board allows?"
    case .outs: "Which cards make your hand?"
    case .beatsMeCount: "Which hands beat yours on this board?"
    case .potCount: "Add every bet to the pot."
    case .legalSizes: "A raise must add at least the last raise."
    case .nextToAct: "Action moves clockwise from the first player after the button."
    case .rangeMatch: "Which hands open this seat?"
    }
  }

  private func input(_ instance: SpotInstance, _ template: SpotTemplate) -> EvalInput {
    EvalInput(instance: instance, template: template, characters: characters, budget: budget)
  }

  // MARK: Async

  public func evaluate(_ instance: SpotInstance, template: SpotTemplate) async throws -> SpotSolution {
    let input = input(instance, template)
    switch template.evaluation.method {
    case .showdownWinner, .bestFive, .nuts, .beatsMeCount, .potCount, .legalSizes, .nextToAct, .outs, .rangeMatch:
      return try input.finish(try Self.exactDraft(input))
    case .closedFormEV:
      let ranges = try await trackedRanges(input)
      return try input.finish(try ClosedFormMethod.solve(input, ranges: ranges))
    case .pushFold:
      let ranges = try await trackedRanges(input)
      return try input.finish(try PushFoldMethod.solve(input, ranges: ranges))
    case .policyEV:
      let ranges = try await trackedRanges(input)
      let plan = try PolicyEVMethod.plan(input, ranges: ranges)
      var results: [ActionEVResult] = []
      for request in plan.requests { results.append(try await ActionEVEstimator.estimate(request)) }
      return try input.finish(try PolicyEVMethod.assemble(plan, results: results))
    }
  }

  private func trackedRanges(_ input: EvalInput) async throws -> [Int: HandRange] {
    try await SpotRanges.villainRanges(input.instance, characters: characters, options: budget.tracker)
  }

  // MARK: Serial

  /// The same numbers as `evaluate`, on the calling thread.
  public func evaluateSerial(_ instance: SpotInstance, template: SpotTemplate) throws -> SpotSolution {
    let input = input(instance, template)
    switch template.evaluation.method {
    case .showdownWinner, .bestFive, .nuts, .beatsMeCount, .potCount, .legalSizes, .nextToAct, .outs, .rangeMatch:
      return try input.finish(try Self.exactDraft(input))
    case .closedFormEV:
      return try input.finish(try ClosedFormMethod.solve(input, ranges: try serialRanges(input)))
    case .pushFold:
      return try input.finish(try PushFoldMethod.solve(input, ranges: try serialRanges(input)))
    case .policyEV:
      let plan = try PolicyEVMethod.plan(input, ranges: try serialRanges(input))
      let results = try plan.requests.map { try ActionEVEstimator.estimateSerial($0) }
      return try input.finish(try PolicyEVMethod.assemble(plan, results: results))
    }
  }

  /// `SpotRanges.villainRanges` with serial tracker updates.
  private func serialRanges(_ input: EvalInput) throws -> [Int: HandRange] {
    let instance = input.instance
    let points = try DecisionPoints.extract(from: instance.log)
    let strategies = SpotRanges.strategies(instance, characters: characters)
    let heroCards = input.heroCards
    let tracked = instance.villainSeats.filter { instance.seatCharacters[$0] != nil }
    var tracker = RangeTracker(
      seats: tracked, observer: instance.heroSeat, observerCards: heroCards,
      strategies: strategies.filter { tracked.contains($0.key) }, options: budget.tracker)
    for point in points where point.context.seat != instance.heroSeat && tracked.contains(point.context.seat) {
      tracker.observe(point.context, action: point.action)
    }
    let dead = CardSet(heroCards + instance.board)
    var result: [Int: HandRange] = [:]
    for seat in instance.villainSeats {
      result[seat] =
        tracked.contains(seat) ? ((tracker.range(of: seat) ?? .full).removing(dead)) : HandRange.full.removing(dead)
    }
    return result
  }

  private static func exactDraft(_ input: EvalInput) throws -> Draft {
    switch input.template.evaluation.method {
    case .showdownWinner: try ExactMethods.showdownWinner(input)
    case .bestFive: try ExactMethods.bestFive(input)
    case .nuts: try ExactMethods.nuts(input)
    case .potCount: try ExactMethods.potCount(input)
    case .legalSizes: try ExactMethods.legalSizes(input)
    case .nextToAct: try ExactMethods.nextToAct(input)
    case .outs: try CountMethods.outs(input)
    case .beatsMeCount: try CountMethods.beatsMeCount(input)
    case .rangeMatch: try RangeMatchMethod.solve(input)
    case .closedFormEV, .policyEV, .pushFold: throw SpotEvaluationError.invalid("not an exact method")
    }
  }
}
