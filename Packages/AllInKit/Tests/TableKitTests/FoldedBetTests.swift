import PokerCore
import SpriteKit
import Testing

@testable import TableKit

/// A 6-max hand where the small blind folds after posting and the rest see a flop.
private func smallBlindFoldsLog(seed: UInt64) throws -> EventLog {
  let config = try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2)
  let stacks = (0..<6).map { SeatStack(seat: $0, stack: 200) }
  var step = try HandReducer.start(config: config, button: 0, stacks: stacks, seed: seed)
  var steps = [step]
  var guardCount = 0
  while !step.state.isComplete, let legal = step.state.legalActions, guardCount < 200 {
    let action: Action
    if step.state.street == .preflop {
      if legal.seat == 3 {
        action = .call
      } else if legal.canCheck {
        action = .check
      } else {
        action = .fold
      }
    } else {
      action = legal.canCheck ? .check : .call
    }
    step = try HandReducer.apply(action, to: step.state)
    steps.append(step)
    guardCount += 1
  }
  return EventLog(handID: HandID(seed), steps: steps)
}

@Suite struct FoldedBetModelTests {
  @Test func aFoldedSeatsBetIsSweptWhenTheStreetChanges() throws {
    let log = try smallBlindFoldsLog(seed: 3)
    var table = TableModel(
      config: try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2), seats: TableDemo.seats(count: 6),
      heroSeat: 0)
    var sawFoldedBet = false
    var checkedFlop = false
    for event in log.filtered(for: .seat(0)) {
      let cues = table.apply(event)
      if case .streetDealt(let street, _) = event.event, street == .flop {
        #expect(sawFoldedBet)
        #expect(table.snapshot.seats.allSatisfy { $0.committed == 0 })
        #expect(table.snapshot.seat(1)?.status == .folded)
        #expect(cues.contains(.collectBets))
        checkedFlop = true
      } else if table.snapshot.seat(1)?.status == .folded, table.snapshot.street == .preflop,
        (table.snapshot.seat(1)?.committed ?? 0) > 0
      {
        sawFoldedBet = true
      }
    }
    #expect(checkedFlop)
  }
}

@MainActor @Suite struct FoldedBetSceneTests {
  @Test func aFoldedSeatsBetNodeIsHiddenOnTheFlop() async throws {
    var options = TableSceneOptions()
    options.driver = .immediate
    let scene = TableScene(resolver: .codeDrawn, options: options)
    scene.configure(
      table: try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2), seats: TableDemo.seats(count: 6), heroSeat: 0)
    var flopChecked = false
    scene.onPresented = { event, snapshot in
      guard case .streetDealt(let street, _) = event.event, street == .flop else { return }
      flopChecked = true
      let node = scene.childNode(withName: "//seat.1") as? SeatNode
      #expect(snapshot.seat(1)?.committed == 0)
      #expect(node?.betStack.isHidden == true)
      #expect(node?.betStack.amount == 0)
    }
    scene.enqueue(contentsOf: try smallBlindFoldsLog(seed: 3).filtered(for: .seat(0)))
    await scene.waitUntilIdle()
    #expect(flopChecked)
  }
}
