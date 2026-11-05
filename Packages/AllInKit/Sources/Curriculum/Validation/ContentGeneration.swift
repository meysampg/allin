import Foundation
import PokerEquity

/// What happened to one instance index.
private struct InstanceOutcome: Sendable {
  var seed: UInt64 = 0
  var generateMs = 0.0
  var evaluateMs = 0.0
  var failure: Failure?
  var answerClass: String?
  var gapBB: Double?
  /// Unbound-placeholder messages with the site they came from.
  var textProblems: [TextProblem] = []

  struct Failure: Sendable {
    let code: String
    let reason: String
  }

  struct TextProblem: Sendable, Hashable {
    let file: String
    let path: String
    let message: String
  }
}

private func milliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

private func percentile95(_ values: [Double]) -> Double {
  guard !values.isEmpty else { return 0 }
  let sorted = values.sorted()
  return sorted[max(0, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)]
}

private func unresolvedName(in message: String) -> String? {
  guard let open = message.range(of: "placeholder '{"),
    let close = message.range(of: "}'", range: open.upperBound..<message.endIndex)
  else { return nil }
  return String(message[open.upperBound..<close.lowerBound])
}

extension ContentValidator {
  /// Structural + text + generation. Generation is skipped while there are structural errors.
  public static func validate(
    _ library: ContentLibrary, options: ValidationOptions = ValidationOptions()
  ) async -> ValidationReport {
    var issues = library.warnings + structural(library) + placeholders(library)
    var reports: [TemplateReport] = []
    if !issues.contains(where: { $0.severity == .error }) {
      reports = await generation(library, options: options)
      issues += reports.flatMap(\.issues)
    }
    var seen = Set<ContentIssue>()
    return ValidationReport(issues: issues.filter { seen.insert($0).inserted }, templates: reports)
  }

  /// Generates and solves `instances` (exact) or `evInstances` (EV) spots of each template; instance `i` uses seed
  /// `StableSeed.mix(options.seed, i)`. Deterministic: results are kept by index and reduced in index order.
  public static func generation(_ library: ContentLibrary, options: ValidationOptions) async -> [TemplateReport] {
    var reports: [TemplateReport] = []
    let sites = textSites(library)
    for id in library.templates.keys.sorted() {
      guard let template = library.templates[id], options.templates?.contains(id) ?? true else { continue }
      let count = template.evaluation.method.isEV ? options.evInstances : options.instances
      let ownSites = sites.filter { $0.templateID == id }
      let outcomes = await outcomes(of: template, count: count, sites: ownSites, library: library, options: options)
      reports.append(report(template, outcomes: outcomes, count: count, file: library.fileOf[id] ?? ""))
    }
    return reports
  }

  private static func outcomes(
    of template: SpotTemplate, count: Int, sites: [TextSite], library: ContentLibrary, options: ValidationOptions
  ) async -> [InstanceOutcome] {
    let chunks = max(1, min(options.parallelism, count))
    let generator = SpotGenerator(characters: library.characters)
    let evaluator = SpotEvaluator(characters: library.characters, budget: options.budget)
    let clock = ContinuousClock()
    var byIndex = [InstanceOutcome](repeating: InstanceOutcome(), count: count)
    await withTaskGroup(of: [(Int, InstanceOutcome)].self) { group in
      for chunk in 0..<chunks {
        group.addTask {
          var done: [(Int, InstanceOutcome)] = []
          var index = chunk
          while index < count {
            let outcome = solve(
              template, seed: StableSeed.mix(options.seed, UInt64(index)), sites: sites, generator: generator,
              evaluator: evaluator, clock: clock)
            done.append((index, outcome))
            index += chunks
          }
          return done
        }
      }
      for await part in group { for (index, outcome) in part { byIndex[index] = outcome } }
    }
    return byIndex
  }

  /// What `SpotFactory.make` does for one seed: attempts `mix(seed, k)` until the gap is clear enough, keeping the last
  /// spot; times are summed over the attempts.
  private static func solve(
    _ template: SpotTemplate, seed: UInt64, sites: [TextSite], generator: SpotGenerator, evaluator: SpotEvaluator,
    clock: ContinuousClock
  ) -> InstanceOutcome {
    var outcome = InstanceOutcome()
    outcome.seed = seed
    var failure: InstanceOutcome.Failure?
    var solved: SpotSolution?
    for k in 0..<max(1, template.quality.maxRetries + 1) {
      let attemptSeed = StableSeed.mix(seed, UInt64(k))
      let startGenerate = clock.now
      let instance: SpotInstance
      do {
        instance = try generator.generate(template, seed: attemptSeed)
        outcome.generateMs += milliseconds(startGenerate.duration(to: clock.now))
      } catch {
        outcome.generateMs += milliseconds(startGenerate.duration(to: clock.now))
        var code = "gen.invalid"
        if let error = error as? SpotGenerationError, case .exhausted = error { code = "gen.exhausted" }
        failure = .init(code: code, reason: "\(error)")
        continue
      }
      let startEvaluate = clock.now
      do {
        let solution = try evaluator.evaluateSerial(instance, template: template)
        outcome.evaluateMs += milliseconds(startEvaluate.duration(to: clock.now))
        solved = solution
        failure = nil
        if SpotFactory.accepts(solution, template: template, target: nil) { break }
      } catch {
        outcome.evaluateMs += milliseconds(startEvaluate.duration(to: clock.now))
        let text = "\(error)"
        if let name = unresolvedName(in: text) {
          outcome.textProblems.append(.init(file: "", path: "", message: "unknown placeholder {\(name)}"))
        }
        failure = .init(code: "gen.evaluate", reason: text)
      }
    }
    guard let solution = solved else {
      outcome.failure = failure
      return outcome
    }
    outcome.answerClass = solution.answerClass
    outcome.gapBB = solution.gapBB
    for site in sites {
      do { _ = try TextBinder.bind(site.text, solution.bindings) } catch {
        let message = unresolvedName(in: "\(error)").map { "unknown placeholder {\($0)}" } ?? "\(error)"
        outcome.textProblems.append(.init(file: site.file, path: site.path, message: message))
      }
    }
    return outcome
  }

  private static func report(
    _ template: SpotTemplate, outcomes: [InstanceOutcome], count: Int, file: String
  ) -> TemplateReport {
    var issues: [ContentIssue] = []
    func add(_ severity: IssueSeverity, _ code: String, _ message: String) {
      issues.append(ContentIssue(severity, code: code, file: file, message: message))
    }
    // Failures: first reasons, one issue per code.
    var reasons: [String] = []
    var failedByCode: [String: [InstanceOutcome]] = [:]
    for outcome in outcomes {
      guard let failure = outcome.failure else { continue }
      failedByCode[failure.code, default: []].append(outcome)
      if reasons.count < 5 { reasons.append("seed \(outcome.seed): \(failure.reason)") }
    }
    for code in failedByCode.keys.sorted() {
      let failed = failedByCode[code] ?? []
      let first = failed[0]
      let reason = first.failure?.reason ?? ""
      add(.error, code, "\(template.id): \(failed.count) of \(count) instances failed; seed \(first.seed): \(reason)")
    }
    // Text that does not bind.
    var seenText = Set<InstanceOutcome.TextProblem>()
    for problem in outcomes.flatMap(\.textProblems) where seenText.insert(problem).inserted {
      issues.append(
        ContentIssue(
          .error, code: "placeholder.unresolved", file: problem.file.isEmpty ? file : problem.file, path: problem.path,
          message: "\(template.id): \(problem.message)"))
    }
    let good = outcomes.filter { $0.failure == nil && $0.answerClass != nil }
    let generated = good.count
    var shares: [String: Double] = [:]
    for outcome in good { shares[outcome.answerClass ?? "", default: 0] += 1 }
    for key in shares.keys { shares[key] = (shares[key] ?? 0) / Double(max(generated, 1)) }
    if generated > 0 {
      for (answer, range) in template.quality.answerBalance.sorted(by: { $0.key < $1.key }) {
        let share = shares[answer] ?? 0
        if share < range.lo || share > range.hi {
          add(
            .error, "gen.balance",
            "\(template.id): answer '\(answer)' share \(String(format: "%.2f", share)) outside "
              + "[\(String(format: "%.2f", range.lo)), \(String(format: "%.2f", range.hi))]")
        }
      }
    }
    var gapShare: Double?
    if template.evaluation.method.isEV, let minGap = template.quality.minGapBB, generated > 0 {
      let wide = good.filter { ($0.gapBB ?? 0) >= minGap - 1e-9 }.count
      let share = Double(wide) / Double(generated)
      gapShare = share
      if share < 0.9 {
        add(
          .error, "gen.gap",
          "\(template.id): gap ≥ \(formatNumber(minGap)) bb in \(Int((share * 100).rounded()))% of instances (need 90%)"
        )
      }
    }
    let generateP95 = percentile95(outcomes.map(\.generateMs))
    let evaluateP95 = percentile95(good.map(\.evaluateMs))
    let limit = template.evaluation.method.isEV ? 500.0 : 50.0
    if evaluateP95 > limit {
      add(
        .warning, "gen.slow",
        "\(template.id): p95 evaluate \(Int(evaluateP95.rounded())) ms is above \(Int(limit)) ms")
    }
    return TemplateReport(
      templateID: template.id, requested: count, generated: generated, failureReasons: reasons,
      answerShares: shares, gapShare: gapShare, generateP95Ms: generateP95, evaluateP95Ms: evaluateP95,
      issues: issues)
  }
}
