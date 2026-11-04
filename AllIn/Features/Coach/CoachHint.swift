import Foundation
import PokerCore
import PokerEquity

/// How much of the coach's thinking prompts the table shows.
enum CoachHintLevel: String, Sendable {
  /// All three questions.
  case full
  /// Question 1 only.
  case light
  /// No box.
  case off
}

enum CoachHintPolicy {
  /// M4 stub: the questions mode shows everything, any other mode shows nothing. M6.7 adds the skill meters.
  static func level(for setup: TableSetup) -> CoachHintLevel {
    setup.coach == .questions ? .full : .off
  }
}

/// A finished read of one opponent, ready to draw.
struct CoachRange: Equatable {
  let seat: Int
  let name: String
  let range: HandRange
  let dead: CardSet
  let actionsRead: Int
  let inconsistent: Bool
}
