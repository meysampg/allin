import Foundation
import PokerCore

@testable import AllInStore

enum StoreFixtures {
  /// A finished 6-max hand played with simple deterministic choices.
  static func log(seed: UInt64 = 7, handID: HandID = 1) throws -> EventLog {
    let config = try TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100)
    let stacks = (0..<6).map { SeatStack(seat: $0, stack: 10_000) }
    var step = try HandReducer.start(config: config, button: 0, stacks: stacks, seed: seed)
    var steps = [step]
    var count = 0
    while let legal = step.state.legalActions, count < 200 {
      count += 1
      let action: Action
      if legal.canCheck {
        action = .check
      } else if legal.canCall && count % 3 != 0 {
        action = .call
      } else {
        action = .fold
      }
      step = try HandReducer.apply(action, to: step.state)
      steps.append(step)
    }
    return EventLog(handID: handID, steps: steps)
  }

  static let seats: [ArchivedSeat] = (0..<6).map {
    ArchivedSeat(
      seat: $0, name: $0 == 0 ? "You" : "Bot \($0)", characterID: $0 == 0 ? nil : "bot\($0)",
      style: $0 == 0 ? nil : "balanced", isHero: $0 == 0)
  }

  static func input(
    session: UUID, hand: UInt64, at: Date = Date(timeIntervalSinceReferenceDate: 1000), seed: UInt64 = 7
  ) throws -> ArchivedHandInput {
    ArchivedHandInput(
      key: ArchiveKey(sessionID: session, handID: HandID(hand)), playedAt: at, heroSeat: 0, seats: seats,
      log: try log(seed: seed, handID: HandID(hand)), strategySeed: UInt64.max - 3, netChips: -150, potTotal: 400,
      bigBlind: 100)
  }

  static let grades = HandGradeSummary(
    good: 3, smallMiss: 1, leak: 1, evLossBB: 2.5, luckChips: -40.5, weightedQuality: 0.75, weight: 4,
    decisionScore: 72.5)
}
