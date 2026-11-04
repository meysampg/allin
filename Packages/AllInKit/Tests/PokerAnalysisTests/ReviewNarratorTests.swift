import PokerAI
import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct ReviewNarratorTests {
  private let minus = "\u{2212}"

  private func counts(_ good: Int, _ miss: Int, _ leak: Int) -> GradeCounts {
    var c = GradeCounts()
    c.good = good
    c.smallMiss = miss
    c.leak = leak
    return c
  }

  private func headline(net: Int, counts: GradeCounts) -> String {
    let analysis = fakeAnalysis(net: net)
    let withCounts = HandAnalysis(
      handID: analysis.handID, heroSeat: 0, bigBlind: 2, netChips: net, potTotal: 100, decisions: [], counts: counts,
      luck: analysis.luck, weightedQuality: 0, weight: 0, decisionScore: nil, evLossBB: 0, budget: .test)
    return withCounts.headline
  }

  @Test func headlineVariants() {
    #expect(headline(net: 29, counts: counts(3, 0, 1)) == "You won 29 · decisions: 3 good, 1 leak")
    #expect(headline(net: -40, counts: counts(1, 2, 0)) == "You lost 40 · decisions: 1 good, 2 small misses")
    #expect(headline(net: 0, counts: counts(0, 1, 2)) == "You broke even · decisions: 1 small miss, 2 leaks")
    #expect(headline(net: 6, counts: counts(0, 0, 0)) == "You won 6 · decisions: no decisions")
  }

  @Test func luckTextOnlyForAllIn() {
    #expect(fakeAnalysis(net: 40).luckText == nil)
    let luck = LuckResult(
      netChips: 420, expectedNetChips: 480, luckChips: -60, wasAllIn: true, allInStreet: .flop, heroEquity: 0.6)
    #expect(fakeAnalysis(net: 420, luck: luck).luckText == "Chips +420 (luck \(minus)60)")
    let down = LuckResult(
      netChips: -200, expectedNetChips: -228, luckChips: 28.4, wasAllIn: true, allInStreet: .preflop, heroEquity: 0.8)
    #expect(fakeAnalysis(net: -200, luck: down).luckText == "Chips \(minus)200 (luck +28)")
  }

  @Test func timelineTextUsesTheTrueMinus() {
    #expect(ReviewNarrator.timelineText(tag: "open BTN", graded: fakeGraded(lossBB: 0)) == "✓ open BTN")
    #expect(ReviewNarrator.timelineText(tag: "call", graded: fakeGraded(lossBB: 3)) == "≈ call (\(minus)3.0 bb)")
    #expect(ReviewNarrator.timelineText(tag: "check", graded: fakeGraded(lossBB: 6.04)) == "✗ check (\(minus)6.0 bb)")
  }

  private func demoPoints() throws -> [DecisionPoint] {
    let hand = try GoldenHands.reviewDemo()
    return try DecisionPoints.extract(from: hand.log).filter { $0.context.seat == hand.heroSeat }
  }

  @Test func tagsOfTheDemoHand() throws {
    let points = try demoPoints()
    #expect(points.count == 4)
    let tags = points.map {
      ReviewNarrator.tag(for: $0.action, context: $0.context, heroCards: $0.context.holeCards)
    }
    #expect(tags == ["open BTN", "c-bet ⅓", "check", "value bet"])
  }

  @Test func preflopTags() throws {
    // Seat 3 opens (UTG), seat 4 3-bets, seat 5 4-bets.
    let log = try scriptedLog(
      seatCount: 6, button: 0, stacks: Array(repeating: 200, count: 6),
      holes: [0: "2c 3d", 1: "4c 5d", 2: "6c 7d", 3: "Ah Ad", 4: "Kh Kd", 5: "Qh Qd"], board: "2h 5s 9c Jd 8s",
      actions: [.raise(to: 6), .raise(to: 18), .raise(to: 50)])
    let points = try DecisionPoints.extract(from: log)
    let tags = points.map {
      ReviewNarrator.tag(for: $0.action, context: $0.context, heroCards: $0.context.holeCards)
    }
    #expect(tags == ["open UTG", "3-bet", "4-bet"])
  }

  @Test func styleSentences() {
    #expect(
      ReviewNarrator.styleSentence(name: "Zib", style: "calling station")
        == "Zib is a calling station. They call with any pair and many draws.")
    #expect(
      ReviewNarrator.styleSentence(name: "Mott", style: "nit")
        == "Mott plays few hands and rarely bluffs, so their bets mean strength.")
    let rock = ReviewNarrator.styleSentence(name: "Mott", style: "rock")
    #expect(rock == ReviewNarrator.styleSentence(name: "Mott", style: "nit"))
    #expect(ReviewNarrator.styleSentence(name: "X", style: nil) == "")
    #expect(ReviewNarrator.styleSentence(name: "X", style: "mystery") == "")
  }

  @Test func titlesAndBody() throws {
    let spot = try GoldenSpots.riverValueBetVsStation()
    let miss = try spot.grade(.check).graded
    let title = ReviewNarrator.title(street: .river, graded: miss, context: spot.context)
    #expect(title == "River: you checked. Better: go all-in.")
    let draft = ReviewedDecisionDraft(
      graded: miss, kind: DecisionKind(street: .river, facing: .none, chosen: .passive, best: .aggressive),
      focusName: "Zib", focusStyle: "calling station", equityVsFocus: 0.93, potOddsNeeded: nil)
    #expect(
      ReviewNarrator.body(decision: draft)
        == "Zib is a calling station. They call with any pair and many draws. "
        + "Your hand is ahead of most of what they continue with (about 93%), so betting earns more.")
    let good = try spot.grade(.allIn).graded
    #expect(
      ReviewNarrator.title(street: .river, graded: good, context: spot.context)
        == "River: you went all-in. That was the best play.")
  }

  @Test func closeSpotTitle() {
    let graded = fakeGraded(lossBB: 0.5)
    // Loss 0.5 bb is inside the 1.0 bb tolerance at this pot.
    #expect(graded.grade == .good)
    let context = (try? GoldenSpots.riverValueBetVsStation().context)!
    let title = ReviewNarrator.title(street: .turn, graded: graded, context: context)
    #expect(title.hasPrefix("Turn: close spot: "))
    #expect(title.hasSuffix("within 1.0 bb."))
  }
}
