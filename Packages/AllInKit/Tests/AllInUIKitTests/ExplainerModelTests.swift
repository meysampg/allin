import PokerCore
import Testing

@testable import AllInUI

@Suite struct ExplainerModelTests {
  @Test func potSlices() {
    let model = PotSlicesModel(pot: 150, call: 50)
    #expect(model.slices == 4)
    #expect(model.priceNeeded == 0.25)
    #expect(model.caption == "You pay 1 part to win 3, so you need to win more than 1 in 4 times (25%).")
  }

  @Test func potSlicesEdgeCases() {
    #expect(PotSlicesModel(pot: 0, call: 0).slices == 2)
    #expect(PotSlicesModel(pot: 10, call: 100).slices == 2)
    #expect(PotSlicesModel(pot: 50, call: 0).priceNeeded == 0)
  }

  @Test func outsGlow() {
    let flop = OutsGlowModel(
      hole: parseCards("Ah7h"), board: parseCards("Kh9h4s"),
      outs: Array(repeating: (), count: 9).enumerated().map {
        Card(index: UInt8($0.offset))
      }, unseen: 47)
    #expect(percentText(flop.nextCard) == "19%")
    #expect(percentText(flop.byRiver ?? 0) == "35%")
    #expect(flop.caption.contains("19% next card"))
    #expect(flop.caption.contains("35% by the river"))
    var turn = flop
    turn.board = parseCards("Kh9h4s2c")
    #expect(turn.byRiver == nil)
    #expect(OutsGlowModel(hole: [], board: [], outs: [], unseen: 0).nextCard == 0)
  }

  @Test func potCounterTotal() {
    let model = PotCounterModel(
      entries: [.init(label: "Blinds", amount: 3), .init(label: "Bet", amount: 50)], toCall: 50)
    #expect(model.total == 53)
    #expect(model.runningTotals == [3, 53])
    #expect(PotCounterModel(entries: [], total: 7).total == 7)
  }

  @Test func whoCallsMeTotals() {
    var cells = [[WhoCallsMeModel.Cell]](
      repeating: [.none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none], count: 13)
    cells[0][0] = .betterCalls
    let model = WhoCallsMeModel(
      mode: .callers, villainName: "Vexa", heroCards: [], board: [], cells: cells, worseCalls: 0.3, betterCalls: 0.2,
      folds: 0.5)
    #expect(abs(model.total - 1) < 1e-9)
    #expect(abs(model.callShare - 0.5) < 1e-9)
    #expect(model.summary.contains("30%"))
    #expect(model.legend.map(\.title).first == "Worse hands that call")
    var bettors = model
    bettors.mode = .bettors
    #expect(bettors.legend.first?.title == "Worse hands that bet")
  }

  @Test func equityBarsClamp() {
    let model = EquityBarsModel(priceNeeded: 1.4, chance: -0.2)
    #expect(model.priceFraction == 1)
    #expect(model.chanceFraction == 0)
    #expect(model.priceText == "100%")
    #expect(EquityBarsModel(priceNeeded: nil, chance: .nan).chanceFraction == nil)
    #expect(EquityBarsModel(priceNeeded: 0.2, chance: 0.35).chanceText == "35%")
    #expect(EquityBarsModel(priceNeeded: 0.2, chance: 0.35).isProfitable == true)
    #expect(EquityBarsModel(priceNeeded: 0.4, chance: 0.35).isProfitable == false)
  }

  @Test func handLadderOrder() {
    #expect(HandLadderModel.order.first == .straightFlush)
    #expect(HandLadderModel.order.last == .highCard)
    #expect(HandLadderModel.order.count == 9)
  }
}
