import Foundation
import PokerAI
import PokerCore
import PokerEquity
import Testing

@testable import PokerAnalysis

@Suite struct ActionEVEstimatorTests {
  private let nuts = "Ah Qh"
  private let villainHand = "Kd Qc"

  private func request(
    _ built: BuiltSpot, villain: HandRange, villainSeat: Int, strategy: any StrategyProvider = AlwaysCall(),
    chosen: Action? = nil, budget: EVBudget = .test, seed: UInt64 = 11
  ) -> EVRequest {
    EVRequest(
      spot: built.spot, opponentRanges: [villainSeat: villain], opponents: [villainSeat: strategy],
      hero: AlwaysCall(), chosen: chosen, budget: budget, seed: seed)
  }

  private func riverNuts() throws -> BuiltSpot {
    try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: checkedToRiver)
  }

  @Test func riverNutsVsAlwaysCall() throws {
    let built = try riverNuts()
    let result = try ActionEVEstimator.estimateSerial(
      request(built, villain: range("KdQc"), villainSeat: 0))
    #expect(result.candidate(for: .check)?.evBB == 20.0)
    #expect(result.candidate(for: .allIn)?.evBB == 110.0)
    #expect(result.candidate(for: .bet(to: 40))?.evBB == 40.0)
    #expect(result.best.action == .allIn)
    #expect(result.candidate(for: .check)?.method == .rollout)
    #expect(result.candidate(for: .fold) == nil)
  }

  @Test func riverFoldVsNutsUsesClosedForm() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 40)])
    let result = try ActionEVEstimator.estimateSerial(
      request(built, villain: range("AhQh"), villainSeat: 1))
    let call = try #require(result.candidate(for: .call))
    #expect(call.evBB == -20.0)
    #expect(call.method == .closedForm)
    #expect(call.standardError == 0)
    let fold = try #require(result.candidate(for: .fold))
    #expect(fold.evBB == 0)
    #expect(fold.method == .exactFold)
    #expect(result.best.action == .fold)
  }

  @Test func bluffCatcherPotOdds() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 20)])
    let result = try ActionEVEstimator.estimateSerial(
      request(built, villain: range("AhQh", "JdTd"), villainSeat: 1))
    let call = try #require(result.candidate(for: .call))
    #expect(abs(call.evBB - 10.0) < 1e-9)
    #expect(call.method == .closedForm)
  }

  @Test func chosenOffGridSizeIsIncluded() throws {
    let built = try riverNuts()
    let context = built.spot.context
    let plain = ActionEVEstimator.candidates(for: context)
    #expect(!plain.contains(.bet(to: 31)))
    let withChosen = ActionEVEstimator.candidates(for: context, including: .bet(to: 31))
    #expect(withChosen.contains(.bet(to: 31)))
    #expect(withChosen.count == plain.count + 1)
    // A bet of the whole stack is the same as all-in.
    #expect(ActionEVEstimator.candidates(for: context, including: .bet(to: 180)) == plain)
    // Order: check, ascending bets, all-in.
    #expect(plain.first == .check && plain.last == .allIn)
    let result = try ActionEVEstimator.estimateSerial(
      request(built, villain: range("KdQc"), villainSeat: 0, chosen: .bet(to: 31)))
    #expect(result.candidate(for: .bet(to: 31))?.evBB == 35.5)
  }

  private func turnSpot() throws -> BuiltSpot {
    try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: [.raise(to: 20), .call, .check, .check])
  }

  @Test func sameSeedSameNumbers() async throws {
    let built = try turnSpot()
    let req = request(built, villain: .full, villainSeat: 0)
    let a = try await ActionEVEstimator.estimate(req)
    let b = try await ActionEVEstimator.estimate(req)
    #expect(a == b)
  }

  @Test func asyncEqualsSerial() async throws {
    let built = try turnSpot()
    let req = request(
      built, villain: .full, villainSeat: 0, budget: EVBudget(rolloutsPerCandidate: 30, policyStreets: 2, chunks: 7))
    let async = try await ActionEVEstimator.estimate(req)
    let serial = try ActionEVEstimator.estimateSerial(req)
    #expect(async == serial)
  }

  @Test func differentSeedsAgreeWithinError() throws {
    let built = try turnSpot()
    let villain = ClosureStrategy { context in
      context.legal.canCheck ? [(.check, 1)] : [(.call, 1)]
    }
    let a = try ActionEVEstimator.estimateSerial(
      request(built, villain: .full, villainSeat: 0, strategy: villain, seed: 1))
    let b = try ActionEVEstimator.estimateSerial(
      request(built, villain: .full, villainSeat: 0, strategy: villain, seed: 2))
    #expect(a.candidates.map(\.action) == b.candidates.map(\.action))
    for (x, y) in zip(a.candidates, b.candidates) {
      let tolerance = 5 * (x.standardError * x.standardError + y.standardError * y.standardError).squareRoot() + 0.01
      #expect(abs(x.evBB - y.evBB) <= tolerance, "\(x.label): \(x.evBB) vs \(y.evBB)")
    }
  }

  @Test func checkdownMatchesEquity() throws {
    let built = try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: [.raise(to: 20), .call])
    let flop = Array(built.spot.context.board)
    #expect(flop.count == 3)
    let equity = EquityCalculator.exact(hero: built.spot.context.holeCards, vs: range("KdQc"), board: flop)
    let budget = EVBudget(rolloutsPerCandidate: 300, policyStreets: 1)
    let result = try ActionEVEstimator.estimateSerial(
      request(built, villain: range("KdQc"), villainSeat: 0, budget: budget))
    let check = try #require(result.candidate(for: .check))
    let expected = equity.equity * 40 / 2
    #expect(abs(check.evBB - expected) <= 3 * check.standardError + 1e-9, "\(check.evBB) vs \(expected)")
  }

  @Test func replayMismatchThrows() throws {
    let built = try riverNuts()
    var actions = built.spot.priorActions
    actions[0] = .raise(to: 30)
    let broken = EVSpot(start: built.spot.start, priorActions: actions, context: built.spot.context)
    var req = request(built, villain: range("KdQc"), villainSeat: 0)
    req.spot = broken
    #expect(throws: EVError.replayMismatch) { try ActionEVEstimator.estimateSerial(req) }
  }

  @Test func missingStrategyThrows() throws {
    let built = try riverNuts()
    var req = request(built, villain: range("KdQc"), villainSeat: 0)
    req.opponents = [:]
    #expect(throws: EVError.missingStrategy(seat: 0)) { try ActionEVEstimator.estimateSerial(req) }
  }

  @Test func flopTimingWithBaseline() async throws {
    let built = try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: villainHand, 1: nuts],
      board: riverBoard, actions: [.raise(to: 20), .call])
    let baseline = BaselineStrategy()
    let req = EVRequest(
      spot: built.spot, opponentRanges: [0: .full], opponents: [0: baseline], hero: baseline, chosen: nil,
      budget: .test, seed: 5)
    let clock = ContinuousClock()
    var result: ActionEVResult?
    let elapsed = try await clock.measure { result = try await ActionEVEstimator.estimate(req) }
    let candidates = try #require(result).candidates.count
    print("EV flop timing (budget .test, \(candidates) candidates): \(elapsed)")
    #expect(candidates >= 3)
    #expect(elapsed < .seconds(30))
  }
}
