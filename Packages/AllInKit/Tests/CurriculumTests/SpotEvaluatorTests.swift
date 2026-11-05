import Foundation
import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SpotEvaluatorTests {
  static let evaluator = EvaluationTestSupport.evaluator
  static let generator = EvaluationTestSupport.generator

  /// Seeds per template: 20 for exact methods, 2 for the EV ones (rollouts and tracking are slow in debug).
  static func seedCount(_ template: SpotTemplate) -> Int {
    template.evaluation.method.isEV ? 2 : 20
  }

  @Test(arguments: GenerationTestSupport.allTemplates.map(\.id))
  func fixtureTemplateEvaluates(id: String) async throws {
    let template = GenerationTestSupport.template(id)
    let clock = ContinuousClock()
    var samples: [Double] = []
    for k in 0..<Self.seedCount(template) {
      let instance = try Self.generator.generate(template, seed: UInt64(5_000 + k))
      var solution: SpotSolution?
      let elapsed = try await clock.measure {
        solution = try await Self.evaluator.evaluate(instance, template: template)
      }
      samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
      try Self.check(try #require(solution), template: template, instance: instance)
    }
    samples.sort()
    print(
      "SPOTEVAL \(id) (\(template.evaluation.method.rawValue)): p50 \(Int(samples[samples.count / 2])) ms, "
        + "p95 \(Int(samples[min(samples.count - 1, samples.count * 95 / 100)])) ms")
  }

  static func check(_ solution: SpotSolution, template: SpotTemplate, instance: SpotInstance) throws {
    #expect(solution.templateID == template.id)
    #expect(solution.method == template.evaluation.method)
    #expect(solution.question == template.question.type)
    #expect(solution.decisionType.templateID == template.id)
    #expect(Set(solution.bindings.values.keys) == TextBinder.keys(for: template.evaluation.method))
    // Every text of the template binds.
    _ = try TextBinder.bind(template.prompt, solution.bindings)
    _ = try TextBinder.bind(solution.hint, solution.bindings)
    #expect(solution.difficulty >= template.difficulty && solution.difficulty <= 1)
    // The correct answer grades as good, and a wrong kind of response does not.
    let grade = SpotEvaluator.grade(solution.correct, solution: solution)
    #expect(grade.grade == .good && grade.isCorrect && grade.quality > 0.99)
    #expect(!grade.verdictTitle.isEmpty && !grade.verdictDetail.isEmpty)
    // Options.
    let ids = solution.options.map(\.id)
    #expect(Set(ids).count == ids.count)
    switch template.evaluation.method {
    case .closedFormEV, .policyEV, .pushFold:
      let evs = try #require(solution.evs)
      #expect(evs.candidates.count == solution.options.count)
      let tokens = template.question.options ?? []
      #expect(ids == tokens)
      for (option, candidate) in zip(solution.options, evs.candidates) {
        #expect(option.evBB == candidate.evBB && option.label == candidate.label)
      }
      #expect(
        solution.answerClass
          == ids[evs.candidates.firstIndex { $0.action == evs.best.action }!].split(separator: ":")[0])
      if let gap = solution.gapBB { #expect(gap >= 0) }
      if case .option(let id) = solution.correct {
        #expect(ids.contains(id))
      } else {
        Issue.record("EV answer is an option")
      }
    case .showdownWinner:
      #expect(ids.contains("split"))
      #expect(ids.count == instance.state.liveSeats.count + 1)
    case .nextToAct:
      #expect(Set(ids) == Set(instance.state.seats.filter { $0.status == .active }.map { "seat:\($0.seat)" }))
      #expect(solution.correct == .option("seat:\(instance.actor)"))
    case .nuts where template.question.type == .pickHandClass:
      #expect(Set(ids) == Set(template.question.options ?? []))
    case .beatsMeCount where template.question.type == .choice:
      #expect(ids == template.question.options)
    case .legalSizes where template.evaluation.ask == .minRaise:
      #expect(ids.contains("size:\(instance.actorContext.legal.minRaiseTo!)"))
      #expect(ids == ids.sorted { Int($0.dropFirst(5))! < Int($1.dropFirst(5))! })
    default:
      break
    }
    if template.question.type == .number { #expect(solution.tolerance != nil) }
    if template.question.type == .pickCards { #expect(solution.pick == template.question.pick) }
  }

  @Test(arguments: GenerationTestSupport.allTemplates.map(\.id))
  func serialMatchesAsyncAndIsDeterministic(id: String) async throws {
    let template = GenerationTestSupport.template(id)
    let instance = try Self.generator.generate(template, seed: 7_001)
    let serial = try Self.evaluator.evaluateSerial(instance, template: template)
    let async = try await Self.evaluator.evaluate(instance, template: template)
    let again = try await Self.evaluator.evaluate(instance, template: template)
    #expect(serial == async)
    #expect(async == again)
  }

  @Test func evCandidatesRestrictToOptionsInOptionOrder() async throws {
    // value-river offers check, bet:0.5, bet:1.0; the estimator's standard set has other sizes too.
    let template = GenerationTestSupport.template("fx.value.river-bet-or-check")
    let instance = try Self.generator.generate(template, seed: 12)
    let solution = try await Self.evaluator.evaluate(instance, template: template)
    #expect(solution.options.map(\.id) == ["check", "bet:0.5", "bet:1.0"])
    let evs = try #require(solution.evs)
    #expect(evs.candidates.count == 3)
    #expect(evs.candidates[0].action == .check)
    #expect(!solution.villainRanges.isEmpty)
    // The chosen action is among the candidates for every option.
    for option in solution.options {
      let grade = SpotEvaluator.grade(.option(option.id), solution: solution)
      #expect(grade.graded != nil)
    }
  }

  @Test func closedFormUsesTheTrackedRangeAndReportsText() async throws {
    let template = GenerationTestSupport.template("fx.potodds.obvious")
    let instance = try Self.generator.generate(template, seed: 21)
    let solution = try await Self.evaluator.evaluate(instance, template: template)
    let villain = try #require(instance.villainSeats.first)
    #expect(solution.villainRanges[villain] != nil)
    #expect(solution.bindings["equity"]?.hasSuffix("%") == true)
    #expect(solution.bindings["priceNeeded"]?.hasSuffix("%") == true)
    #expect(solution.bindings["evGain"]?.hasSuffix(" bb") == true)
    // AhQh on Kh9h4c with a flush draw and overcards is a clear call against a 40-55% pot bet.
    #expect(solution.answerClass == "call" || solution.answerClass == "raise")
  }

  @Test func notTheHeroTurnIsReported() throws {
    let template = GenerationTestSupport.template("fx.rules.next-to-act")
    var found: SpotInstance?
    for seed in 0..<40 {
      let instance = try Self.generator.generate(template, seed: UInt64(seed))
      if instance.actor != instance.heroSeat {
        found = instance
        break
      }
    }
    let instance = try #require(found)
    // The exact methods do not need the hero; an EV method does.
    let ev = EvaluationTestSupport.variant(
      GenerationTestSupport.template("fx.potodds.obvious"),
      question: QuestionSpec(type: .action, options: ["fold", "call"]))
    #expect(throws: SpotEvaluationError.heroNotToAct) { try Self.evaluator.evaluateSerial(instance, template: ev) }
  }

  @Test func unavailableOptionIsReported() throws {
    let template = EvaluationTestSupport.variant(
      GenerationTestSupport.template("fx.potodds.obvious"),
      question: QuestionSpec(type: .action, options: ["fold", "check"]))
    let instance = try Self.generator.generate(template, seed: 4)
    #expect(throws: SpotEvaluationError.optionUnavailable("check")) {
      try Self.evaluator.evaluateSerial(instance, template: template)
    }
  }
}
