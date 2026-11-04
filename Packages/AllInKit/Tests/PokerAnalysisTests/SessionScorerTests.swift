import Testing

@testable import PokerAnalysis

@Suite struct SessionScorerTests {
  @Test func weightedScoreOfThreeHands() {
    var scorer = SessionScorer()
    #expect(scorer.score.decisionScore == nil)
    let hands: [(Double, Double, Int, [ReviewedDecision])] = [
      (6, 8, 30, [fakeDecision(index: 0, lossBB: 0), fakeDecision(index: 1, lossBB: 6)]),
      (3, 4, -10, [fakeDecision(index: 0, lossBB: 3)]),
      (0, 2, -20, [fakeDecision(index: 0, lossBB: 6)]),
    ]
    for (wq, w, net, decisions) in hands {
      scorer.add(fakeAnalysis(net: net, decisions: decisions, weightedQuality: wq, weight: w))
    }
    let score = scorer.score
    #expect(score.hands == 3)
    #expect(score.decisions == 4)
    #expect(score.counts.good == 1 && score.counts.smallMiss == 1 && score.counts.leak == 2)
    #expect(score.netChips == 0)
    #expect(score.weightedQuality == 9 && score.weight == 14)
    #expect(abs((score.decisionScore ?? 0) - 100 * 9.0 / 14.0) < 1e-12)
    #expect(abs(score.evLossBB - 15) < 1e-12)
  }

  @Test func handsWithoutDecisionsDoNotMoveTheScore() {
    var scorer = SessionScorer()
    scorer.add(fakeAnalysis(net: 4))
    #expect(scorer.score.hands == 1)
    #expect(scorer.score.decisionScore == nil)
  }
}
