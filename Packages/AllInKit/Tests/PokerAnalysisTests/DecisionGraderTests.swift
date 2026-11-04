import Foundation
import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct DecisionGraderTests {
  private func evs(_ values: [(Action, Double)]) -> ActionEVResult {
    ActionEVResult(
      candidates: values.map {
        CandidateEV(
          action: $0.0, label: "\($0.0)", shortLabel: "\($0.0)", evBB: $0.1, standardError: 0, samples: 0,
          method: .rollout)
      })
  }

  // Pot 100 chips, bb 2: 50 bb, tolerance max(0.15, 0.02 * 50) = 1.0 bb.
  private let abc = [(Action.check, 5.0), (.bet(to: 20), 4.5), (.allIn, 1.0)]

  @Test func goldenCloseSpot() {
    let result = evs(abc)
    let close = DecisionGrader.grade(result, chosen: .bet(to: 20), potBefore: 100, bigBlind: 2)
    #expect(close.grade == .good)
    #expect(close.isClose)
    #expect(close.toleranceBB == 1.0)
    #expect(close.second?.action == .bet(to: 20))
    let miss = DecisionGrader.grade(result, chosen: .allIn, potBefore: 100, bigBlind: 2)
    #expect(miss.grade == .smallMiss)
    #expect(miss.evLossBB == 4.0)
    #expect(abs(miss.quality - 0.68) < 1e-12)
    #expect(abs(miss.weight - 51.0.log2) < 1e-12)
  }

  @Test func goldenLeak() {
    let result = evs([(.check, 7.0), (.bet(to: 20), 3.0), (.allIn, 1.0)])
    let graded = DecisionGrader.grade(result, chosen: .allIn, potBefore: 100, bigBlind: 2)
    #expect(graded.evLossBB == 6.0)
    #expect(graded.grade == .leak)
    #expect(!graded.isClose)
  }

  @Test func toleranceFloor() {
    let result = evs([(.check, 1.0), (.bet(to: 3), 0.9)])
    let graded = DecisionGrader.grade(result, chosen: .bet(to: 3), potBefore: 4, bigBlind: 2)
    #expect(graded.toleranceBB == 0.15)
    #expect(graded.grade == .good)
    let worse = DecisionGrader.grade(
      evs([(.check, 1.0), (.bet(to: 3), 0.5)]), chosen: .bet(to: 3), potBefore: 4, bigBlind: 2)
    #expect(worse.grade == .leak)
  }

  @Test func bestChosenIsGood() {
    let graded = DecisionGrader.grade(evs(abc), chosen: .check, potBefore: 100, bigBlind: 2)
    #expect(graded.grade == .good)
    #expect(graded.evLossBB == 0)
    #expect(graded.quality == 1)
    #expect(graded.best.action == .check)
  }

  @Test func qualityClamps() {
    let result = evs([(.check, 40.0), (.allIn, -10.0)])
    let graded = DecisionGrader.grade(result, chosen: .allIn, potBefore: 100, bigBlind: 2)
    #expect(graded.quality == 0)
    #expect(graded.grade == .leak)
    let single = DecisionGrader.grade(evs([(.check, 2.0)]), chosen: .check, potBefore: 100, bigBlind: 2)
    #expect(single.second == nil)
    #expect(!single.isClose)
    #expect(single.grade == .good)
  }

  @Test func gradeCounts() {
    var counts = GradeCounts()
    counts.add(.good)
    counts.add(.good)
    counts.add(.leak)
    #expect(counts.total == 3)
    #expect(counts.good == 2 && counts.leak == 1 && counts.smallMiss == 0)
  }
}

private extension Double {
  var log2: Double { Foundation.log2(self) }
}
