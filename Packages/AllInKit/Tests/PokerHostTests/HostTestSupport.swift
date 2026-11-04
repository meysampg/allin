import PokerCore

@testable import PokerHost

enum HostFixture {
  static func config(seats: Int = 6, small: Int = 1, big: Int = 2) -> TableConfig {
    try! TableConfig(seatCount: seats, smallBlind: small, bigBlind: big)
  }

  /// The unshuffled deck in index order: a fixed, known deal.
  static var fixedDeck: [Card] { Array(Deck().undealt) }

  static func stacks(_ seats: [Int], chips: Int = 200) -> [SeatStack] {
    seats.map { SeatStack(seat: $0, stack: chips) }
  }

  static func setup(
    id: UInt64 = 1, button: Int = 0, seats: [Int], chips: Int = 200, deal: HandDeal? = nil
  ) -> HandSetup {
    HandSetup(
      handID: HandID(id), button: button, stacks: stacks(seats, chips: chips), deal: deal ?? .deck(fixedDeck))
  }

  /// Total chips a hand started with.
  static func total(_ setup: HandSetup) -> Int { setup.stacks.reduce(0) { $0 + $1.stack } }

  /// The actions of a log, in order.
  static func actions(_ log: EventLog) -> [Action] {
    log.events.compactMap { if case .actionTaken(let t) = $0.event { t.action } else { nil } }
  }
}

import Synchronization

/// Collects events from a `@Sendable` callback.
final class EventBox: Sendable {
  private let storage = Mutex<[LoggedEvent]>([])
  func append(_ event: LoggedEvent) { storage.withLock { $0.append(event) } }
  var events: [LoggedEvent] { storage.withLock { $0 } }
}

/// A seat that never answers in time.
struct SleepingSeat: Seat {
  let id: SeatID
  func observe(_ event: LoggedEvent) async {}
  func decide(_ request: DecisionRequest) async -> Action {
    try? await Task.sleep(for: .seconds(10))
    return .raise(to: 10)
  }
}
