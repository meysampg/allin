import Foundation
import PokerEquity

/// A generated and solved spot.
public struct EvaluatedSpot: Sendable, Hashable {
  public let template: SpotTemplate
  public let instance: SpotInstance
  public let solution: SpotSolution
  /// `template.prompt` with its placeholders bound.
  public let prompt: String

  public init(template: SpotTemplate, instance: SpotInstance, solution: SpotSolution, prompt: String) {
    self.template = template
    self.instance = instance
    self.solution = solution
    self.prompt = prompt
  }
}

public enum SpotFactoryError: Error, Sendable {
  case unknownTemplate(String)
  case generation(SpotGenerationError)
  case evaluation(String)
}

/// Generate, evaluate, and retry until the spot is clear enough.
public struct SpotFactory: Sendable {
  let library: ContentLibrary
  let budget: EvaluationBudget

  public init(library: ContentLibrary, budget: EvaluationBudget = .lesson) {
    self.library = library
    self.budget = budget
  }

  /// Seeds `StableSeed.mix(seed, k)`, k = 0..<max(1, quality.maxRetries + 1): generate, then evaluate. Accepts the
  /// first whose gap is at least `minGapBB` (EV methods) and whose answerClass is `targetAnswerClass` (if given);
  /// otherwise returns the last. `hintOverride` replaces the template hint.
  public func make(
    templateID: String, seed: UInt64, avoid: Set<String> = [], targetAnswerClass: String? = nil,
    hintOverride: String? = nil
  ) async throws -> EvaluatedSpot {
    guard let template = library.template(templateID) else { throw SpotFactoryError.unknownTemplate(templateID) }
    let generator = SpotGenerator(characters: library.characters)
    let evaluator = SpotEvaluator(characters: library.characters, budget: budget)
    let attempts = max(1, template.quality.maxRetries + 1)
    var last: (SpotInstance, SpotSolution)?
    var failure: SpotFactoryError?
    for k in 0..<attempts {
      let mixed = StableSeed.mix(seed, UInt64(k))
      let instance: SpotInstance
      do {
        instance = try generator.generate(template, seed: mixed, avoid: avoid)
      } catch let error as SpotGenerationError {
        failure = .generation(error)
        continue
      }
      let solution: SpotSolution
      do {
        solution = try await evaluator.evaluate(instance, template: template)
      } catch {
        failure = .evaluation("\(error)")
        continue
      }
      last = (instance, solution)
      if Self.accepts(solution, template: template, target: targetAnswerClass) { break }
    }
    guard let (instance, solution) = last else {
      throw failure ?? SpotFactoryError.evaluation("no attempt produced a spot")
    }
    return try Self.assemble(template: template, instance: instance, solution: solution, hintOverride: hintOverride)
  }

  static func accepts(_ solution: SpotSolution, template: SpotTemplate, target: String?) -> Bool {
    if let minGap = template.quality.minGapBB, template.evaluation.method.isEV, let gap = solution.gapBB,
      gap < minGap
    {
      return false
    }
    if let target, solution.answerClass != target { return false }
    return true
  }

  static func assemble(
    template: SpotTemplate, instance: SpotInstance, solution: SpotSolution, hintOverride: String?
  ) throws -> EvaluatedSpot {
    do {
      var solved = solution
      if let hintOverride { solved = solved.replacingHint(try TextBinder.bind(hintOverride, solution.bindings)) }
      let prompt = try TextBinder.bind(template.prompt, solution.bindings)
      return EvaluatedSpot(template: template, instance: instance, solution: solved, prompt: prompt)
    } catch {
      throw SpotFactoryError.evaluation("text of \(template.id): \(error)")
    }
  }
}
