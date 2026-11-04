import Foundation
import PokerCore

/// Headless sample hands for tests, previews and menus.
public enum TableDemo {
  private static let opponents: [(name: String, id: String, hint: String)] = [
    ("Grumli", "grumli", "calls a lot"), ("Zib", "zib", "bets big, often"), ("Vexa", "vexa", "plays few hands"),
    ("Mott", "mott", "folds a lot"), ("Oryn", "oryn", "balanced"), ("Bram", "bram", "never bluffs"),
    ("Patron", "patron", "plays too many hands"), ("Morwen", "morwen", "studies you"),
  ]

  /// The hero ("You") at `heroSeat`, then Grumli, Zib, Vexa, Mott, Oryn, Bram, Patron around the table.
  public static func seats(count: Int, heroSeat: Int = 0) -> [TableSeatInfo] {
    var next = 0
    return (0..<count).map { seat in
      if seat == heroSeat {
        return TableSeatInfo(seat: seat, name: "You", characterID: "you", styleHint: nil, isHero: true)
      }
      let who = opponents[next % opponents.count]
      next += 1
      return TableSeatInfo(seat: seat, name: who.name, characterID: who.id, styleHint: who.hint, isHero: false)
    }
  }

  /// A host log of one hand where everyone checks when they can and calls otherwise, so it ends at showdown.
  public static func loggedHand(
    seed: UInt64, seatCount: Int = 6, button: Int = 0, stack: Int = 200, smallBlind: Int = 1, bigBlind: Int = 2
  ) throws -> EventLog {
    let config = try TableConfig(seatCount: seatCount, smallBlind: smallBlind, bigBlind: bigBlind)
    let stacks = (0..<seatCount).map { SeatStack(seat: $0, stack: stack) }
    var step = try HandReducer.start(config: config, button: button, stacks: stacks, seed: seed)
    var steps = [step]
    var guardCount = 0
    while !step.state.isComplete, let legal = step.state.legalActions, guardCount < 1_000 {
      let action: Action = legal.canCheck ? .check : (legal.canCall ? .call : .allIn)
      step = try HandReducer.apply(action, to: step.state)
      steps.append(step)
      guardCount += 1
    }
    return EventLog(handID: HandID(seed), steps: steps)
  }
}
