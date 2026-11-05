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
      evs([(.check, 1.0), (.bet(to: 3), 0.2)]), chosen: .bet(to: 3), potBefore: 4, bigBlind: 2)
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

  private func noisy(_ values: [(Action, Double, Double)]) -> ActionEVResult {
    ActionEVResult(
      candidates: values.map {
        CandidateEV(
          action: $0.0, label: "\($0.0)", shortLabel: "\($0.0)", evBB: $0.1, standardError: $0.2, samples: 100,
          method: .rollout)
      })
  }

  @Test func goodBandWidensWithSamplingError() {
    // Pot 20 bb: base tolerance 0.4 bb. A loss of 1.5 bb is within 2 * sqrt(0.6^2 + 0.6^2) = 1.70 bb.
    let result = noisy([(.check, 5.0, 0.6), (.bet(to: 20), 3.5, 0.6), (.allIn, 0.0, 0.6)])
    let graded = DecisionGrader.grade(result, chosen: .bet(to: 20), potBefore: 40, bigBlind: 2)
    #expect(abs(graded.toleranceBB - 2 * (0.72).squareRoot()) < 1e-12)
    #expect(graded.grade == .good)
    // Exact EVs keep the base band: the same loss is a miss.
    let exact = DecisionGrader.grade(
      noisy([(.check, 5.0, 0), (.bet(to: 20), 3.5, 0), (.allIn, 0.0, 0)]), chosen: .bet(to: 20), potBefore: 40,
      bigBlind: 2)
    #expect(exact.toleranceBB == 0.4)
    #expect(exact.grade != .good)
  }

  @Test func errorBandDoesNotHideARealLeak() {
    let result = noisy([(.check, 12.0, 0.3), (.allIn, 4.0, 0.3)])
    let graded = DecisionGrader.grade(result, chosen: .allIn, potBefore: 40, bigBlind: 2)
    #expect(graded.grade == .leak)
  }

  @Test func smallMissHasAHalfBigBlindFloor() {
    // Pot 2 bb: 10% is 0.2 bb, so the floor of 0.5 bb applies: a 0.45 bb loss is a small miss, 0.7 a leak.
    let small = DecisionGrader.grade(
      noisy([(.check, 1.0, 0), (.bet(to: 3), 0.55, 0)]), chosen: .bet(to: 3), potBefore: 4, bigBlind: 2)
    #expect(small.grade == .smallMiss)
    let big = DecisionGrader.grade(
      noisy([(.check, 1.0, 0), (.bet(to: 3), 0.3, 0)]), chosen: .bet(to: 3), potBefore: 4, bigBlind: 2)
    #expect(big.grade == .leak)
  }
}
