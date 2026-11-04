import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct GoldenSpotTests {
  @Test func g1RiverValueBetVsStation() throws {
    let spot = try GoldenSpots.riverValueBetVsStation()
    let check = try spot.grade(.check)
    #expect(check.graded.grade == .leak)
    #expect(check.evs.candidate(for: .check)?.evBB == 20.0)
    #expect(check.evs.candidate(for: .allIn)?.evBB == 110.0)
    #expect(check.graded.best.action == .allIn)
    let shove = try spot.grade(.allIn)
    #expect(shove.graded.grade == .good)
    #expect(shove.graded.evLossBB == 0)
  }

  @Test func g2RiverFoldVsNuts() throws {
    let spot = try GoldenSpots.riverFoldVsNuts()
    let call = try spot.grade(.call)
    #expect(call.graded.grade == .leak)
    #expect(call.evs.candidate(for: .call)?.evBB == -20.0)
    #expect(call.graded.best.action == .fold)
    #expect(try spot.grade(.fold).graded.grade == .good)
  }

  @Test func g3BluffCatcherCall() throws {
    let spot = try GoldenSpots.bluffCatcherCall()
    let fold = try spot.grade(.fold)
    #expect(fold.graded.grade == .leak)
    let call = try #require(fold.evs.candidate(for: .call))
    #expect(abs(call.evBB - 10.0) < 1e-9)
    #expect(fold.graded.best.action == .call)
    #expect(try spot.grade(.call).graded.grade == .good)
  }

  @Test func g6PreflopAAvsShove() throws {
    let spot = try GoldenSpots.preflopAAvsShove()
    let fold = try spot.grade(.fold)
    #expect(fold.graded.grade == .leak)
    // Calling puts the hero all-in, so it is the all-in candidate (closed form).
    let call = try #require(fold.evs.candidate(for: .allIn))
    #expect(call.method == .closedForm)
    #expect(abs(call.evBB - 70) < 10, "call EV \(call.evBB)")
    #expect(fold.graded.best.action == .allIn)
    let calling = try spot.grade(.call)
    #expect(calling.graded.grade == .good)
    #expect(calling.graded.chosen.action == .allIn)
  }

  @Test func gradingIsDeterministic() throws {
    let spot = try GoldenSpots.bluffCatcherCall()
    let a = try spot.grade(.call).graded
    let b = try spot.grade(.call).graded
    #expect(a == b)
  }
}
