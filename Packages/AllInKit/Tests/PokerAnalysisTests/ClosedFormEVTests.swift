import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct ClosedFormEVTests {
  @Test func callFormula() {
    #expect(abs(ClosedFormEV.call(equity: 0.5, pot: 60, toCall: 20) - 20) < 1e-12)
    #expect(abs(ClosedFormEV.call(equity: 0, pot: 60, toCall: 20) + 20) < 1e-12)
  }

  @Test func betFormula() {
    #expect(abs(ClosedFormEV.bet(foldEquity: 1, equityWhenCalled: 0.3, pot: 40, bet: 20, call: 20) - 40) < 1e-12)
    // Never folds, wins half: 0.5 * (40 + 20 + 20) - 20.
    #expect(abs(ClosedFormEV.bet(foldEquity: 0, equityWhenCalled: 0.5, pot: 40, bet: 20, call: 20) - 20) < 1e-12)
  }

  @Test func riverCallClosesAction() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 40)])
    #expect(ClosedFormEV.callClosesAction(built.spot))
  }

  @Test func flopCallVsLiveStackDoesNotClose() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: [.raise(to: 20), .call, .bet(to: 20)])
    #expect(!ClosedFormEV.callClosesAction(built.spot))
  }

  @Test func flopCallVsAllInCloses() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: [.raise(to: 20), .call, .allIn])
    #expect(ClosedFormEV.callClosesAction(built.spot))
  }
}
