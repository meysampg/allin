import PokerCore

/// Seat numbers are table positions, `0..<config.seatCount`.
public typealias SeatID = Int

/// One participant of a hand: a bot, a script or a human behind a UI.
public protocol Seat: Sendable {
  var id: SeatID { get }
  /// Events already filtered for this seat (Viewer.seat(id)), in seq order.
  func observe(_ event: LoggedEvent) async
  /// The host validates the answer.
  func decide(_ request: DecisionRequest) async -> Action
}
