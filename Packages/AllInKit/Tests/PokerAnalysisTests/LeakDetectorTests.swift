import Testing

@testable import PokerAnalysis

@Suite struct LeakDetectorTests {
  private func hand(_ decisions: [ReviewedDecision]) -> HandAnalysis { fakeAnalysis(decisions: decisions) }

  @Test func repeatedTurnChecksAreTheTopLeak() {
    var detector = LeakDetector()
    for i in 0..<3 {
      detector.add(
        hand([
          fakeDecision(index: 0, street: .flop, lossBB: 0),
          fakeDecision(index: 1, street: .turn, chosen: .passive, best: .aggressive, lossBB: 6),
        ]), handKey: "h\(i)")
    }
    detector.add(hand([fakeDecision(index: 0, street: .turn, lossBB: 0)]), handKey: "h3")
    let leaks = detector.leaks()
    #expect(leaks.count == 1)
    let top = leaks[0]
    #expect(top.title == "Turn: checking when betting earns more")
    #expect(top.occurrences == 3)
    #expect(top.opportunities == 4)
    #expect(abs(top.evLostBB - 18) < 1e-12)
    #expect(top.examples.count == 3)
    #expect(top.id == "turn.none.passive>aggressive")
  }

  @Test func belowMinimumNoLeak() {
    var detector = LeakDetector(minOccurrences: 2)
    detector.add(hand([fakeDecision(index: 0, lossBB: 6)]), handKey: "a")
    #expect(detector.leaks().isEmpty)
    detector.add(hand([fakeDecision(index: 0, lossBB: 3)]), handKey: "b")
    #expect(detector.leaks().count == 1)
  }

  @Test func goodDecisionsAndSameClassMissesDoNotCount() {
    var detector = LeakDetector(minOccurrences: 1)
    detector.add(hand([fakeDecision(index: 0, lossBB: 0)]), handKey: "a")
    detector.add(hand([fakeDecision(index: 0, chosen: .aggressive, best: .aggressive, lossBB: 6)]), handKey: "b")
    #expect(detector.leaks().isEmpty)
  }

  @Test func sortedByEVLostThenTopLimit() {
    var detector = LeakDetector(minOccurrences: 1)
    detector.add(
      hand([
        fakeDecision(index: 0, street: .river, facing: .bet, chosen: .passive, best: .fold, lossBB: 3),
        fakeDecision(index: 1, street: .turn, lossBB: 6),
      ]), handKey: "a")
    let leaks = detector.leaks()
    #expect(leaks.map(\.title) == ["Turn: checking when betting earns more", "River: calling when folding is better"])
    #expect(detector.leaks(top: 1).count == 1)
  }
}
