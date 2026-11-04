import PokerCore
import PokerEquity

@testable import PokerAI

/// A test-only strategy built from a closure that lists (action, weight) pairs for a context.
struct TableStrategy: StrategyProvider {
  let table: @Sendable (DecisionContext) -> [(Action, Double)]

  init(_ table: @escaping @Sendable (DecisionContext) -> [(Action, Double)]) { self.table = table }

  func distribution(for context: DecisionContext) -> ActionDistribution {
    let pairs = table(context).filter { $0.1 > 0 }
    return try! ActionDistribution(weights: pairs.map { (action: $0.0, weight: $0.1) }, legal: context.legal)
  }
}

/// Builders of scripted host logs for range tests (test targets cannot share files, so the names are unique).
enum RangeScript {
  static let card = AITestSupport.card
  static let cards = AITestSupport.cards

  /// A 52-card deck that deals `holes` (by seat) and `board` in the host's deal order (with burns);
  /// the other cards fill the remaining slots in index order.
  static func deckWith(seatCount: Int, button: Int, holes: [Int: [Card]], board: [Card] = []) -> [Card] {
    var slots = [Card?](repeating: nil, count: 52)
    let order = (1...seatCount).map { (button + $0) % seatCount }
    for (position, seat) in order.enumerated() {
      guard let pair = holes[seat] else { continue }
      slots[position] = pair[0]
      slots[seatCount + position] = pair[1]
    }
    let base = 2 * seatCount
    let boardSlots = [base + 1, base + 2, base + 3, base + 5, base + 7]
    for (cardIndex, slot) in zip(board.indices, boardSlots) { slots[slot] = board[cardIndex] }
    let used = Set(slots.compactMap { $0 }.map(\.index))
    var rest = Card.all.filter { !used.contains($0.index) }.makeIterator()
    return slots.map { $0 ?? rest.next()! }
  }

  /// The host log of a hand where `actions` are applied in turn from a fixed deck.
  static func scriptedLog(
    seatCount: Int = 6, button: Int = 0, stacks: Int = 10_000, deck: [Card], actions: [Action]
  ) throws -> EventLog {
    let config = AIScript.table(seats: seatCount)
    let seatStacks = (0..<seatCount).map { SeatStack(seat: $0, stack: stacks) }
    var step = try HandReducer.start(config: config, button: button, stacks: seatStacks, deck: deck)
    var steps = [step]
    for action in actions {
      step = try HandReducer.apply(action, to: step.state)
      steps.append(step)
    }
    return EventLog(handID: HandID(1), steps: steps)
  }

  static func withBoard(_ context: DecisionContext, _ board: [Card]) -> DecisionContext {
    DecisionContext(
      config: context.config, seat: context.seat, holeCards: context.holeCards, board: board,
      street: context.street, button: context.button, smallBlindSeat: context.smallBlindSeat,
      bigBlindSeat: context.bigBlindSeat, seats: context.seats, pot: context.pot, history: context.history,
      legal: context.legal)
  }
}
