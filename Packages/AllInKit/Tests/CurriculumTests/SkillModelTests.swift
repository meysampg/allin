import Foundation
import Testing

@testable import Curriculum

@Suite struct SkillModelTests {
  let t = SRSTestSupport.t0

  @Test func qualityIsMonotone() {
    var hi = SkillModel()
    var mid = SkillModel()
    var lo = SkillModel()
    let a = hi.record(skill: "s", difficulty: 0.5, quality: 1, at: t)
    let b = mid.record(skill: "s", difficulty: 0.5, quality: 0.5, at: t)
    let c = lo.record(skill: "s", difficulty: 0.5, quality: 0, at: t)
    #expect(a.theta > SkillRating.initial.theta)
    #expect(c.theta < SkillRating.initial.theta)
    #expect(a.theta > b.theta && b.theta > c.theta)
    #expect(a.evidence == 1 && a.updatedAt == t)
  }

  @Test func kFactorDecays() {
    #expect(abs(SkillModel.kFactor(evidence: 0) - 0.4) < 1e-12)
    #expect(SkillModel.kFactor(evidence: 40) < 0.11)
    #expect(SkillModel.kFactor(evidence: 5) > SkillModel.kFactor(evidence: 6))
  }

  @Test func difficultyLogit() {
    #expect(SkillModel.difficultyLogit(0.5) == 0)
    #expect(SkillModel.difficultyLogit(-3) == -2)
    #expect(SkillModel.difficultyLogit(7) == 2)
  }

  @Test func meterZeroAtNoEvidence() {
    let m = SkillModel()
    #expect(m.meter("s", baseDifficulty: 0.4) == 0)
    #expect(!m.isMastered("s", baseDifficulty: 0.4))
    #expect(m.rating("s") == .initial)
  }

  @Test func fifteenGoodResultsMaster() {
    // Meter is measured against the skill's base difficulty (0.2); the results were at difficulty 0.4.
    var m = SkillModel()
    for i in 0..<14 {
      m.record(skill: "s", difficulty: 0.4, quality: 1, at: t)
      #expect(!m.isMastered("s", baseDifficulty: 0.2), "evidence \(i + 1)")
    }
    // 14 results already satisfy the meter rule; only the evidence rule holds mastery back.
    #expect(m.meter("s", baseDifficulty: 0.2) >= SkillModel.masteryMeter)
    m.record(skill: "s", difficulty: 0.4, quality: 1, at: t)
    #expect(m.meter("s", baseDifficulty: 0.2) >= SkillModel.masteryMeter)
    #expect(m.isMastered("s", baseDifficulty: 0.2))
  }

  @Test func thetaInvertsMeter() {
    for base in [0.2, 0.4, 0.8] {
      for target in [0.1, 0.5, 0.9] {
        var m = SkillModel()
        m.ratings["s"] = SkillRating(
          theta: SkillModel.theta(forMeter: target, baseDifficulty: base), evidence: 3, updatedAt: nil)
        #expect(abs(m.meter("s", baseDifficulty: base) - target) < 1e-9)
      }
    }
  }

  @Test func groupMeterAndAxisScores() {
    var m = SkillModel()
    m.ratings["a"] = SkillRating(
      theta: SkillModel.theta(forMeter: 0.8, baseDifficulty: 0.5), evidence: 5, updatedAt: nil)
    m.ratings["b"] = SkillRating(
      theta: SkillModel.theta(forMeter: 0.4, baseDifficulty: 0.5), evidence: 5, updatedAt: nil)
    let base = ["a": 0.5]  // b missing → 0.5
    #expect(abs(m.groupMeter(["a", "b"], baseDifficulty: base) - 0.6) < 1e-9)
    #expect(m.groupMeter([], baseDifficulty: base) == 0)
    let axes = m.axisScores(axisWeights: ["x": ["a": 3, "b": 1], "y": ["c": 1]], baseDifficulty: base)
    #expect(abs((axes["x"] ?? -1) - (3 * 0.8 + 0.4) / 4) < 1e-9)
    #expect(axes["y"] == 0)
  }
}
