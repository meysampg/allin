import Foundation
import PokerCore

/// One thing to show for an event. The animation queue plays the cues of an event in order.
public enum TableCue: Sendable, Hashable {
  case newHand(button: Int, seats: [Int])
  case postBlind(seat: Int, amount: Int)
  case dealHoles(order: [Int])
  case revealHero([Card])
  case actionRequested(seat: Int)
  case act(seat: Int, action: Action, isAllIn: Bool)
  case fold(seat: Int)
  case returnBet(seat: Int, amount: Int)
  case collectBets
  case dealBoard(Street, [Card])
  case showdown([Reveal])
  case award(PotAwardInfo)
  case handEnded(HandResult)
}
