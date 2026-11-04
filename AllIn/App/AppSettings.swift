import PokerHost
import TableKit

struct AppSettings: Hashable, Sendable, Codable {
  var speed: GameSpeed = .normal
  var reduceMotion = false
  var fourColorDeck = false
  var sound = SoundSettings()
}
