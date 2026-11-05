import Foundation
import Testing

@testable import Curriculum

@Suite struct ToolOutputTests {
  private let library = ContentTestSupport.fixture

  @Test func previewIsDeterministic() throws {
    for (id, count) in [("fx.potodds.obvious", 1), ("fx.ranks.pick-winner", 4), ("fx.rules.next-to-act", 4)] {
      let a = try ContentPreviewFormatter.render(library: library, templateID: id, count: count, seed: 1, budget: .test)
      let b = try ContentPreviewFormatter.render(library: library, templateID: id, count: count, seed: 1, budget: .test)
      #expect(a == b, "\(id)")
      #expect(a.filter { $0.hasPrefix("#") }.count == count)
      #expect(!a.contains { $0.contains("error:") }, "\(a)")
    }
  }

  @Test func previewSeedChangesOutput() throws {
    let id = "fx.ranks.pick-winner"
    let a = try ContentPreviewFormatter.render(library: library, templateID: id, count: 3, seed: 1)
    let b = try ContentPreviewFormatter.render(library: library, templateID: id, count: 3, seed: 2)
    #expect(a != b)
  }

  @Test func previewSections() throws {
    let lines = try ContentPreviewFormatter.render(
      library: library, templateID: "fx.potodds.obvious", count: 1, seed: 1, budget: .test)
    let text = lines.joined(separator: "\n")
    for section in [
      "seed ", "hash ", "table:  2p ", "cards:  board ", "line:   pre: ", "prompt: ", "answer: ", "EV bb:",
    ] {
      #expect(text.contains(section), "missing '\(section)' in\n\(text)")
    }
  }

  @Test func unknownTemplateThrows() {
    #expect(throws: SpotFactoryError.self) {
      _ = try ContentPreviewFormatter.render(library: library, templateID: "fx.nope", count: 1, seed: 1)
    }
  }

  @Test func statsAreStableAndConsistent() {
    let a = ContentStats(library)
    #expect(a == ContentStats(library))
    #expect(a.lines() == ContentStats(library).lines())
    #expect(a.templatesPerSkill.values.reduce(0, +) == library.templates.count)
    #expect(a.templatesPerMethod.values.reduce(0, +) == library.templates.count)
    #expect(a.difficultyHistogram.reduce(0, +) == library.templates.count)
    #expect(a.venues.first?.venueID == "fx.tavern")
  }

  @Test func reportLineFormat() {
    let report = TemplateReport(
      templateID: "fx.x", requested: 10, generated: 10, failureReasons: [],
      answerShares: ["check": 0.52, "bet": 0.48], gapShare: 0.94, generateP95Ms: 3.2, evaluateP95Ms: 41,
      issues: [])
    #expect(report.line == "ok   fx.x  10/10  check 52% bet 48%  gap 94%  p95 gen 3 ms eval 41 ms")
  }
}
