import PokerCore
import Testing

@testable import AllInUI

@Suite struct CardPickerTests {
  private func card(_ text: String) -> Card { parseCards(text)[0] }

  @Test func selectionLimitDropsOldest() {
    var selection: [Card] = []
    for text in ["Ah", "Kd", "Qs"] {
      selection = CardPickerLogic.toggled(selection, card: card(text), limit: 2)
    }
    #expect(selection == parseCards("KdQs"))
  }

  @Test func toggleOffRemoves() {
    let selection = CardPickerLogic.toggled(parseCards("AhKd"), card: card("Ah"), limit: 2)
    #expect(selection == parseCards("Kd"))
  }

  @Test func deadCardsCannotBeSelected() {
    let dead = CardSet(parseCards("Ah"))
    let selection = CardPickerLogic.toggled(parseCards("Kd"), card: card("Ah"), limit: 2, dead: dead)
    #expect(selection == parseCards("Kd"))
  }

  @Test func unlimitedKeepsEverything() {
    var selection: [Card] = []
    for c in Card.all.prefix(10) { selection = CardPickerLogic.toggled(selection, card: c, limit: nil) }
    #expect(selection.count == 10)
  }

  @Test func sanitizeDropsDeadAndTrims() {
    let result = CardPickerLogic.sanitized(
      parseCards("AhKdQs"), limit: 1, dead: CardSet(parseCards("Qs")))
    #expect(result == parseCards("Kd"))
  }
}
