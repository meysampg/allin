import Foundation
import Testing

@testable import Curriculum

/// In-memory mutations of the fixture pack; each case must fail with the contract code and message.
@Suite struct BadFixtureTests {
  private let tavern = ContentTestSupport.tavern

  private func expect(
    _ files: [String: Data], code: String, contains text: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let issues = ContentTestSupport.staticIssues(files)
    #expect(
      issues.contains { $0.code == code && $0.message.contains(text) && $0.severity == .error },
      "\(code) '\(text)' in \(issues)", sourceLocation: sourceLocation)
  }

  private func expect(
    _ report: ValidationReport, code: String, contains text: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      report.errors.contains { $0.code == code && $0.message.contains(text) }, "\(code) '\(text)' in \(report.lines())",
      sourceLocation: sourceLocation)
  }

  @Test func unknownKey() {
    expect(
      ContentTestSupport.spot("pot-count") { $0["bogus"] = 1 }, code: "json.unknownKey", contains: "unknown key 'bogus'"
    )
  }

  @Test func schemaVersion() {
    expect(
      ContentTestSupport.spot("pot-count") { $0["schemaVersion"] = 2 }, code: "schema.version",
      contains: "schemaVersion 2 is not supported (expected 1)")
  }

  @Test func duplicateID() {
    var files = ContentTestSupport.fixtureFiles
    files["\(tavern)spots/copy.json"] = files["\(tavern)spots/pot-count.json"]
    expect(files, code: "id.duplicate", contains: "fx.money.pot-count")
  }

  @Test func unknownLesson() {
    expect(
      ContentTestSupport.mutate(file: "\(tavern)venue.json") {
        var nodes = $0["nodes"] as! [[String: Any]]
        nodes[0]["lesson"] = "fx.tavern.l9"
        $0["nodes"] = nodes
      }, code: "ref.unknown", contains: "unknown lesson 'fx.tavern.l9'")
  }

  @Test func unlockCycleAndUnreachableNode() {
    let files = ContentTestSupport.mutate(file: "\(tavern)venue.json") {
      var nodes = $0["nodes"] as! [[String: Any]]
      nodes[0]["unlock"] = ["after": ["fx.tavern.n2"]]
      $0["nodes"] = nodes
    }
    expect(files, code: "graph.cycle", contains: "fx.tavern.n1 -> ")
    expect(files, code: "graph.unreachable", contains: "node 'fx.tavern.n3' can never unlock")
  }

  @Test func unknownCharacter() {
    expect(
      ContentTestSupport.spot("call-cost") { $0["villain"] = ["character": "ghost"] }, code: "ref.unknown",
      contains: "unknown character 'ghost'")
  }

  @Test func misspelledPlaceholder() {
    expect(
      ContentTestSupport.spot("potodds-flush-draw") { $0["prompt"] = "{villian} bets {bet}. Call?" },
      code: "placeholder.unresolved", contains: "unknown placeholder {villian}")
    expect(
      ContentTestSupport.mutate(file: "\(tavern)lessons/l4-pot-odds.json") {
        var steps = $0["steps"] as! [[String: Any]]
        steps[1]["coach"] = "You have {heroHandName}. Pay {toCal}."
        $0["steps"] = steps
      }, code: "placeholder.unresolved", contains: "unknown placeholder {toCal}")
  }

  @Test func placeholderOfAnotherMethod() {
    // {priceNeeded} belongs to the EV methods, not to showdownWinner.
    expect(
      ContentTestSupport.spot("pick-winner") { $0["hint"] = "Price: {priceNeeded}" }, code: "placeholder.unresolved",
      contains: "unknown placeholder {priceNeeded}")
  }

  @Test func methodQuestionMismatch() {
    expect(
      ContentTestSupport.spot("potodds-flush-draw") { $0["question"] = ["type": "pickWinner"] },
      code: "template.methodQuestion", contains: "closedFormEV cannot answer a pickWinner question")
  }

  @Test func invalidPosition() {
    expect(
      ContentTestSupport.spot("potodds-flush-draw") { $0["hero"] = ["position": "LJ"] }, code: "template.position",
      contains: "position 'LJ' does not exist at 2 players")
  }

  @Test func badLineToken() {
    expect(
      ContentTestSupport.spot("potodds-flush-draw") {
        $0["line"] = ["preflop": ["villain:open:2.5", "hero:call"], "flop": ["hero:check", "villain:bet:x"]]
      }, code: "json.decode", contains: "bad line token 'villain:bet:x'")
  }

  @Test func unknownExplainerBindKey() {
    expect(
      ContentTestSupport.mutate(file: "\(tavern)lessons/l4-pot-odds.json") {
        var steps = $0["steps"] as! [[String: Any]]
        steps[2]["explainers"] = [["explainer": "whoCallsMe", "bind": ["sz": "bet:0.5"]]]
        $0["steps"] = steps
      }, code: "lesson.explainer", contains: "unknown bind key 'sz' for whoCallsMe")
  }

  @Test func examCountMismatch() {
    expect(
      ContentTestSupport.mutate(file: "\(tavern)exam.json") { $0["count"] = 13 }, code: "exam.count",
      contains: "draws add up to 12, count is 13")
  }

  // MARK: Generation

  @Test func impossiblePredicateExhausts() async {
    let files = ContentTestSupport.spot("what-beats-me") {
      $0["hero"] = ["hand": ["madeHand": ["flush"]]]
      $0["board"] = ["street": "river", "exclude": ["flushPossible"]]
      $0["quality"] = ["maxRetries": 0]
    }
    let report = await ContentTestSupport.validate(files, templates: ["fx.board.what-beats-me"], instances: 1)
    expect(report, code: "gen.exhausted", contains: "could not build fx.board.what-beats-me")
    #expect(report.templates.first?.generated == 0)
    #expect(report.templates.first?.failureReasons.count == 1)
  }

  @Test func answerBalanceViolated() async {
    let files = ContentTestSupport.spot("what-beats-me") {
      $0["quality"] = ["answerBalance": ["nothing": [0.5, 1.0]]]
    }
    let report = await ContentTestSupport.validate(files, templates: ["fx.board.what-beats-me"], instances: 20)
    expect(report, code: "gen.balance", contains: "answer 'nothing' share 0.00 outside [0.50, 1.00]")
  }

  @Test func gapViolated() async {
    let files = ContentTestSupport.spot("potodds-obvious") { $0["quality"] = ["minGapBB": 50, "maxRetries": 0] }
    let report = await ContentTestSupport.validate(files, templates: ["fx.potodds.obvious"], evInstances: 2)
    expect(report, code: "gen.gap", contains: "gap ≥ 50 bb in 0% of instances (need 90%)")
  }

  @Test func structuralErrorsSkipGeneration() async {
    let files = ContentTestSupport.spot("pot-count") { $0["skill"] = "nope.skill" }
    guard let library = try? ContentLibrary.load(files: files, characters: ContentTestSupport.catalog) else {
      Issue.record("pack does not load")
      return
    }
    let report = await ContentValidator.validate(library)
    #expect(report.hasErrors)
    #expect(report.templates.isEmpty)
  }
}
