import Foundation
import Testing

@testable import Curriculum

@Suite struct StructuralValidationTests {
  private let tavern = CurriculumTestSupport.tavern

  private func expect(
    _ files: [String: Data], code: String, contains text: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let issues = CurriculumTestSupport.issues(files)
    #expect(
      issues.contains { $0.code == code && $0.message.contains(text) }, "\(code) '\(text)' in \(issues)",
      sourceLocation: sourceLocation)
  }

  private func spot(_ name: String, _ edit: @escaping (inout [String: Any]) -> Void) -> [String: Data] {
    CurriculumTestSupport.mutate(file: "\(tavern)spots/\(name).json", edit)
  }

  @Test func fixtureHasNoIssues() {
    #expect(ContentValidator.structural(CurriculumTestSupport.fixture).isEmpty)
  }

  @Test func idFormat() {
    expect(spot("pot-count") { $0["id"] = "Fx Bad" }, code: "id.format", contains: "'Fx Bad'")
    #expect(ContentValidator.isValidID("a.b-c.d1"))
    #expect(!ContentValidator.isValidID("a..b") && !ContentValidator.isValidID("a-") && !ContentValidator.isValidID(""))
  }

  @Test func duplicateId() {
    var files = CurriculumTestSupport.fixtureFiles
    files["\(tavern)spots/copy.json"] = files["\(tavern)spots/pot-count.json"]
    expect(files, code: "id.duplicate", contains: "duplicate template id 'fx.money.pot-count'")
  }

  @Test func venueFolderAndMissingVenue() {
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)venue.json") { $0["id"] = "fx.other" }, code: "venue.folder",
      contains: "does not match folder")
    var files = CurriculumTestSupport.fixtureFiles
    files["\(tavern)venue.json"] = nil
    expect(files, code: "realm.missingVenue", contains: "fx.tavern")
  }

  @Test func unknownReferences() {
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)venue.json") {
        var nodes = $0["nodes"] as! [[String: Any]]
        nodes[0]["lesson"] = "fx.tavern.l9"
        $0["nodes"] = nodes
      }, code: "ref.unknown", contains: "unknown lesson 'fx.tavern.l9'")
    expect(
      spot("pot-count") { $0["skill"] = "nope.skill" }, code: "ref.unknown", contains: "unknown skill 'nope.skill'")
    expect(
      spot("call-cost") { $0["villain"] = ["character": "ghost"] }, code: "ref.unknown",
      contains: "unknown character 'ghost'")
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)drills/d1-which-wins.json") {
        $0["spots"] = [["template": "fx.nope", "weight": 1]]
      }, code: "ref.unknown", contains: "unknown template 'fx.nope'")
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)boss.json") { $0["exam"] = "fx.nope" }, code: "ref.unknown",
      contains: "unknown exam 'fx.nope'")
    expect(
      CurriculumTestSupport.mutate(file: "realm.json") {
        var venues = $0["venues"] as! [[String: Any]]
        venues[1]["unlock"] = ["afterVenue": "fx.nowhere"]
        $0["venues"] = venues
      }, code: "ref.unknown", contains: "unknown venue 'fx.nowhere'")
    expect(
      CurriculumTestSupport.mutate(file: "skills.json") {
        var skills = $0["skills"] as! [[String: Any]]
        skills[0]["axes"] = ["bogus": 1.0]
        $0["skills"] = skills
      }, code: "ref.unknown", contains: "unknown axis 'bogus'")
  }

  @Test func graphCycleAndUnreachable() {
    let cycle = CurriculumTestSupport.mutate(file: "\(tavern)venue.json") {
      var nodes = $0["nodes"] as! [[String: Any]]
      nodes[0]["unlock"] = ["after": ["fx.tavern.n2"]]
      $0["nodes"] = nodes
    }
    expect(cycle, code: "graph.cycle", contains: "fx.tavern.n1 -> ")
    expect(cycle, code: "graph.unreachable", contains: "node 'fx.tavern.n3' can never unlock")
    expect(
      CurriculumTestSupport.mutate(file: "realm.json") {
        var venues = $0["venues"] as! [[String: Any]]
        venues[0]["unlock"] = ["afterVenue": "fx.guild"]
        $0["venues"] = venues
      }, code: "graph.cycle", contains: "venues form a cycle")
  }

  @Test func templateRules() {
    expect(
      spot("potodds-flush-draw") { $0["question"] = ["type": "pickWinner"] }, code: "template.methodQuestion",
      contains: "closedFormEV cannot answer a pickWinner question")
    expect(
      spot("pick-winner") { $0["board"] = ["street": "flop"] }, code: "template.street",
      contains: "showdownWinner needs street river")
    expect(
      spot("potodds-flush-draw") { $0["hero"] = ["position": "LJ"] }, code: "template.position",
      contains: "position 'LJ' does not exist at 2 players")
    expect(
      spot("potodds-flush-draw") { $0["question"] = ["type": "action", "options": ["fold", "raise:1"]] },
      code: "template.option", contains: "option 'raise:1' is not valid for closedFormEV")
    expect(
      spot("potodds-obvious") { $0["board"] = ["street": "turn"] }, code: "template.fixed",
      contains: "fixed board has 3 cards but street is turn")
    expect(
      spot("potodds-obvious") { $0["fixed"] = ["hero": "AhQh", "board": "Ah9h4c"] }, code: "template.fixed",
      contains: "duplicate")
    expect(
      spot("value-river") { $0["villain"] = ["position": "BB"] }, code: "template.character",
      contains: "policyEV needs a villain character")
    expect(
      spot("call-cost") { $0["evaluation"] = ["method": "legalSizes"] }, code: "template.methodQuestion",
      contains: "needs 'ask'")
    expect(
      spot("paint-open") { $0["line"] = ["stopAt": "hero"] }, code: "template.methodQuestion",
      contains: "stopAt villain")
    expect(
      spot("push-sb") { $0["question"] = ["type": "action", "options": ["fold", "call"]] }, code: "template.option",
      contains: "option 'call' is not valid for pushFold")
    expect(
      spot("what-beats-me") { $0["question"] = ["type": "choice", "options": ["tons"]] }, code: "template.option",
      contains: "'tons' is not a bucket id")
  }

  @Test func templateRangeIsADecodeIssue() {
    expect(
      spot("potodds-flush-draw") { $0["hero"] = ["hand": ["range": "ZZ+"]] }, code: "template.range",
      contains: "bad range 'ZZ+'")
  }

  @Test func lessonRules() {
    let lesson = "\(tavern)lessons/l4-pot-odds.json"
    expect(
      CurriculumTestSupport.mutate(file: lesson) {
        var steps = $0["steps"] as! [[String: Any]]
        steps.removeSubrange(0..<2)
        $0["steps"] = steps
      }, code: "lesson.steps", contains: "sandbox step needs an earlier hook or puzzle step")
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)lessons/l5-worse-calls.json") {
        var steps = $0["steps"] as! [[String: Any]]
        steps[2]["explainers"] = [["explainer": "whoCallsMe", "bind": ["sz": "x"]]]
        $0["steps"] = steps
      }, code: "lesson.explainer", contains: "unknown bind key 'sz' for whoCallsMe")
  }

  @Test func examAndTableRules() {
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)exam.json") {
        var draw = $0["draw"] as! [[String: Any]]
        draw[0]["count"] = 0
        $0["draw"] = draw
      }, code: "exam.count", contains: "draws add up to 11, count is 12")
    expect(
      CurriculumTestSupport.mutate(file: "\(tavern)venue.json") {
        var nodes = $0["nodes"] as! [[String: Any]]
        var table = nodes[5]["table"] as! [String: Any]
        table["opponents"] = ["bram", "patron", "patron", "patron"]
        nodes[5]["table"] = table
        $0["nodes"] = nodes
      }, code: "table.opponents", contains: "cash6 needs 5 opponents, got 4")
  }

  @Test func unusedSkillIsAWarning() {
    let files = CurriculumTestSupport.mutate(file: "skills.json") {
      var skills = $0["skills"] as! [[String: Any]]
      skills.append(["id": "extra.skill", "name": "Extra", "axes": ["rules": 1.0], "baseDifficulty": 0.5])
      $0["skills"] = skills
    }
    let issues = CurriculumTestSupport.issues(files)
    #expect(
      issues.contains { $0.code == "skill.unused" && $0.severity == .warning && $0.message.contains("extra.skill") })
  }
}
