import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct ActionLabelTests {
  /// River, pot 40 after a checked-down hand with 20 each; hero (seat 1) to act with 180 behind.
  private func openingContext() throws -> DecisionContext {
    try spot(
      heroSeat: 1, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: checkedToRiver
    ).spot.context
  }

  /// Hero faces a bet of 18 into 40 (pot 58).
  private func facingContext() throws -> DecisionContext {
    try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [200, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: checkedToRiver + [.bet(to: 18)]
    ).spot.context
  }

  @Test func longLabels() throws {
    let open = try openingContext()
    #expect(ActionLabel.long(.check, context: open) == "Check")
    #expect(ActionLabel.long(.bet(to: 27), context: open) == "Bet 27 (⅔ pot)")
    #expect(ActionLabel.long(.bet(to: 40), context: open) == "Bet 40 (pot)")
    #expect(ActionLabel.long(.allIn, context: open) == "All-in 180")
    let facing = try facingContext()
    #expect(ActionLabel.long(.fold, context: facing) == "Fold")
    #expect(ActionLabel.long(.call, context: facing) == "Call 18")
    #expect(ActionLabel.long(.raise(to: 90), context: facing) == "Raise to 90")
  }

  @Test func shortLabels() throws {
    let open = try openingContext()
    #expect(ActionLabel.short(.check, context: open) == "Check")
    #expect(ActionLabel.short(.bet(to: 13), context: open) == "Bet ⅓")
    #expect(ActionLabel.short(.bet(to: 20), context: open) == "Bet ½")
    #expect(ActionLabel.short(.bet(to: 27), context: open) == "Bet ⅔")
    #expect(ActionLabel.short(.bet(to: 40), context: open) == "Bet pot")
    #expect(ActionLabel.short(.allIn, context: open) == "All-in")
    let facing = try facingContext()
    #expect(ActionLabel.short(.call, context: facing) == "Call")
    // Pot after calling is 58 + 18 = 76; a raise to 18 + 50 is about two thirds.
    #expect(ActionLabel.short(.raise(to: 69), context: facing) == "Raise ⅔")
  }

  @Test func callAllInLabel() throws {
    let built = try spot(
      heroSeat: 0, seatCount: 2, button: 0, stacks: [50, 200], holes: [0: "Kd Qc", 1: "Ah Qh"],
      board: riverBoard, actions: [.raise(to: 20), .call, .check, .check, .check, .check, .bet(to: 30)])
    let context = built.spot.context
    #expect(context.legal.callIsAllIn)
    #expect(ActionLabel.long(.allIn, context: context) == "Call all-in 30")
  }

  @Test func potFractionName() {
    #expect(ActionLabel.potFractionName(0.3) == "⅓")
    #expect(ActionLabel.potFractionName(0.5) == "½")
    #expect(ActionLabel.potFractionName(0.66) == "⅔")
    #expect(ActionLabel.potFractionName(0.8) == "¾")
    #expect(ActionLabel.potFractionName(1.05) == "pot")
    #expect(ActionLabel.potFractionName(1.4) == "1.5×")
    #expect(ActionLabel.potFractionName(5) == "2×")
  }
}
