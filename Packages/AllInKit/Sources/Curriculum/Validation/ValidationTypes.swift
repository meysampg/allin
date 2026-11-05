import Foundation

/// What `ContentValidator.validate` generates and how strictly it checks.
public struct ValidationOptions: Sendable, Hashable {
  /// Instances per exact template.
  public var instances = 500
  /// Instances per EV template (rollouts are slow).
  public var evInstances = 100
  public var seed: UInt64 = 1
  public var budget: EvaluationBudget = .validation
  /// Only these template ids (nil = all).
  public var templates: Set<String>?
  /// Chunks of instances generated and evaluated concurrently.
  public var parallelism = 8

  public init() {}

  /// 100 exact and 20 EV instances per template.
  public static let quick: ValidationOptions = {
    var options = ValidationOptions()
    options.instances = 100
    options.evInstances = 20
    return options
  }()
}

/// The outcome of generating and evaluating one template many times.
public struct TemplateReport: Sendable, Hashable {
  public let templateID: String
  public let requested: Int
  /// Instances that were generated and evaluated.
  public let generated: Int
  /// Up to 5 lines like "seed 17: could not build ... (line 1990)".
  public let failureReasons: [String]
  /// Share of generated instances per answer class.
  public let answerShares: [String: Double]
  /// Share of instances with gap at least `minGapBB` (EV methods with a minimum gap).
  public let gapShare: Double?
  public let generateP95Ms: Double
  public let evaluateP95Ms: Double
  public let issues: [ContentIssue]

  public init(
    templateID: String, requested: Int, generated: Int, failureReasons: [String], answerShares: [String: Double],
    gapShare: Double?, generateP95Ms: Double, evaluateP95Ms: Double, issues: [ContentIssue]
  ) {
    self.templateID = templateID
    self.requested = requested
    self.generated = generated
    self.failureReasons = failureReasons
    self.answerShares = answerShares
    self.gapShare = gapShare
    self.generateP95Ms = generateP95Ms
    self.evaluateP95Ms = evaluateP95Ms
    self.issues = issues
  }

  public var hasErrors: Bool { issues.contains { $0.severity == .error } }

  /// `ok   fx.value.river-bet-or-check  500/500  check 52% bet 48%  gap 94%  p95 gen 3 ms eval 41 ms`
  public var line: String {
    let status = hasErrors ? "FAIL" : (issues.isEmpty ? "ok  " : "warn")
    let shares = answerShares.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    var parts = ["\(status) \(templateID)", "\(generated)/\(requested)"]
    if !shares.isEmpty {
      let shown = shares.prefix(5).map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }
      parts.append(shown.joined(separator: " ") + (shares.count > 5 ? " …" : ""))
    }
    if let gapShare { parts.append("gap \(Int((gapShare * 100).rounded()))%") }
    parts.append("p95 gen \(Int(generateP95Ms.rounded())) ms eval \(Int(evaluateP95Ms.rounded())) ms")
    return parts.joined(separator: "  ")
  }
}

public struct ValidationReport: Sendable {
  /// Every issue: structural, text and generation, without repeats.
  public let issues: [ContentIssue]
  public let templates: [TemplateReport]

  public init(issues: [ContentIssue], templates: [TemplateReport]) {
    self.issues = issues
    self.templates = templates
  }

  public var errors: [ContentIssue] { issues.filter { $0.severity == .error } }
  public var warnings: [ContentIssue] { issues.filter { $0.severity == .warning } }
  public var hasErrors: Bool { issues.contains { $0.severity == .error } }

  /// Issue lines, then one line per template.
  public func lines() -> [String] { issues.map(\.description) + templates.map(\.line) }
}
