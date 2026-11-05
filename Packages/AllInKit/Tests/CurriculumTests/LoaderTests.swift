import Foundation
import Testing

@testable import Curriculum

@Suite struct LoaderTests {
  private let library = CurriculumTestSupport.fixture

  @Test func fixtureLoadsWithCounts() {
    #expect(library.venues.count == 1)
    #expect(library.venues[0].nodes.count == 7)
    #expect(library.lessons.count == 4)
    #expect(library.drills.count == 2)
    #expect(library.templates.count == 16)
    #expect(library.bosses.count == 1 && library.exams.count == 1)
    #expect(library.skills.skills.count == 14 && library.realm.venues.count == 4)
    #expect(library.warnings.isEmpty)
  }

  @Test func lookups() {
    #expect(library.node("fx.tavern.n4")?.node.lesson == "fx.tavern.l4.pot-odds")
    #expect(library.node("fx.tavern.n4")?.venue.id == "fx.tavern")
    #expect(library.title(of: library.venues[0].node("fx.tavern.n4")!) == "Pot odds: is the call worth it?")
    #expect(library.title(of: library.venues[0].node("fx.tavern.n6")!) == "Tavern night")
    #expect(library.title(of: library.venues[0].node("fx.tavern.n7")!) == "Bram Ironmug, Tavern Champion")
    #expect(library.venueID(ofContent: "fx.potodds.flush-draw") == "fx.tavern")
    #expect(library.venueID(ofContent: "math.pot-odds") == nil)
    #expect(library.templates(forSkill: "math.pot-odds").map(\.id) == ["fx.potodds.flush-draw", "fx.potodds.obvious"])
    #expect(library.characters.contains("bram") && library.characters.name("bram") == "Bram")
    #expect(library.characters.strategy("vexa") != nil)
    #expect(ContentLibrary.hasCurriculum(at: ContentLibrary.fixtureRoot))
    #expect(!ContentLibrary.hasCurriculum(at: ContentLibrary.sourceTreeRoot))
  }

  @Test func diskLoadEqualsMemoryLoad() throws {
    let disk = try ContentLibrary.load(root: ContentLibrary.fixtureRoot)
    #expect(disk.realm == library.realm && disk.skills == library.skills && disk.venues == library.venues)
    #expect(disk.lessons == library.lessons && disk.templates == library.templates)
    #expect(disk.drills == library.drills && disk.bosses == library.bosses && disk.exams == library.exams)
    #expect(disk.fileOf == library.fileOf)
  }

  @Test func issuesAggregate() {
    var files = CurriculumTestSupport.mutate(file: "venues/fx.tavern/spots/next-to-act.json") { $0["explainr"] = 1 }
    files["venues/fx.tavern/drills/d1-which-wins.json"] = Data("{\"schemaVersion\":1,\"id\":\"x\"}".utf8)
    let issues = CurriculumTestSupport.issues(files)
    #expect(issues.contains { $0.code == "json.unknownKey" && $0.message.contains("unknown key 'explainr'") })
    #expect(issues.contains { $0.code == "json.decode" && $0.message == "missing key 'title'" })
    #expect(issues.count == 2)
  }

  @Test func unknownKeySuggestsNearest() {
    let files = CurriculumTestSupport.mutate(file: "venues/fx.tavern/spots/pot-count.json") { $0["explainn"] = [] }
    let issues = CurriculumTestSupport.issues(files)
    #expect(issues.first?.message.contains("(did you mean 'explain'?)") == true)
  }

  @Test func issueDescription() {
    let issue = ContentIssue(.error, code: "x", file: "a.json", path: "b[1]", message: "oops")
    #expect(issue.description == "error: a.json: b[1]: oops")
    #expect(ContentIssue(.warning, code: "x", file: "", message: "m").description == "warning: m")
  }

  @Test func badSchemaVersionAndMissingRealm() {
    let files = CurriculumTestSupport.mutate(file: "skills.json") { $0["schemaVersion"] = 2 }
    #expect(
      CurriculumTestSupport.issues(files).contains {
        $0.code == "schema.version" && $0.message.contains("schemaVersion 2 is not supported (expected 1)")
      })
    var noRealm = CurriculumTestSupport.fixtureFiles
    noRealm["realm.json"] = nil
    #expect(CurriculumTestSupport.issues(noRealm).first?.file == "realm.json")
  }
}
