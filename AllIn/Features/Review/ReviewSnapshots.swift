import PokerCore
import TableKit

/// Table positions for the review: the hero's view of the hand, with the villains' cards revealed.
struct ReviewSnapshots: Sendable {
  let config: TableConfig
  let seats: [TableSeatInfo]
  let heroSeat: Int
  /// What the hero saw, in order; sequence numbers are the host log's.
  let heroEvents: [LoggedEvent]
  /// Every seat's hole cards, from the host log.
  let revealed: [Int: [Card]]

  init?(log: EventLog, heroSeat: Int, seats: [TableSeatInfo]) {
    var config: TableConfig?
    var revealed: [Int: [Card]] = [:]
    for logged in log.events {
      switch logged.event {
      case .handStarted(let start): config = config ?? start.config
      case .holeCardsDealt(let seat, let cards): revealed[seat] = cards
      default: break
      }
    }
    guard let config else { return nil }
    self.config = config
    self.seats = seats
    self.heroSeat = heroSeat
    heroEvents = log.filtered(for: .seat(heroSeat))
    self.revealed = revealed
  }

  /// The table after the events up to and including `seq` (all of them when nil), villain cards revealed.
  func snapshot(at seq: Int? = nil) -> TableSnapshot {
    var model = TableModel(config: config, seats: seats, heroSeat: heroSeat)
    for event in heroEvents {
      if let seq, event.seq > seq { break }
      _ = model.apply(event)
    }
    var snapshot = model.snapshot
    for index in snapshot.seats.indices where snapshot.seats[index].hasCards {
      if let cards = revealed[index] { snapshot.seats[index].holeCards = cards }
    }
    return snapshot
  }

  /// The hero's events with `seq` in `range`.
  func events(in range: ClosedRange<Int>) -> [LoggedEvent] {
    heroEvents.filter { range.contains($0.seq) }
  }

  /// The sequence number of the event that opens `street`; nil for the preflop (the hand's start).
  func streetStart(_ street: Street) -> Int? {
    guard street != .preflop else { return nil }
    for event in heroEvents {
      if case .streetDealt(let dealt, _) = event.event, dealt == street { return event.seq }
    }
    return nil
  }

  var lastSeq: Int { heroEvents.last?.seq ?? 0 }
}
