import Observation
import PokerHost

@MainActor @Observable
final class LobbyModel {
  var format: TableSetup.Format = .cash6Max
  var selected: [String] = TableSetup.lobbyRoster
  var randomMix = false
  var strength = 0.5
  var coach: TableSetup.CoachMode = .questions
  var hud: TableSetup.HUDMode = .basic
  var speed: GameSpeed

  init(speed: GameSpeed = .normal) {
    self.speed = speed
  }

  /// Heads-up shows only the first picked rival.
  var visibleSelection: [String] {
    format == .headsUp ? Array(selected.prefix(1)) : selected
  }

  func isSelected(_ id: String) -> Bool {
    !randomMix && visibleSelection.contains(id)
  }

  func selectFormat(_ new: TableSetup.Format) {
    guard new.isPlayable else { return }
    format = new
  }

  func toggleOpponent(_ id: String) {
    randomMix = false
    if format == .headsUp {
      selected = isSelectedIgnoringMix(id) ? [] : [id]
      return
    }
    if let index = selected.firstIndex(of: id) {
      selected.remove(at: index)
    } else {
      selected.append(id)
    }
  }

  func toggleRandomMix() {
    randomMix.toggle()
  }

  func makeSetup(seed: UInt64) -> TableSetup {
    var setup = TableSetup(
      opponentIDs: TableSetup.resolveOpponents(
        format: format, selected: randomMix ? [] : visibleSelection, randomMix: randomMix, seed: seed),
      seed: seed)
    setup.format = format
    setup.smallBlind = 1
    setup.bigBlind = 2
    setup.buyIn = 200
    setup.coach = coach
    setup.hud = hud
    setup.speed = speed
    setup.tableStrength = strength
    return setup
  }

  private func isSelectedIgnoringMix(_ id: String) -> Bool { visibleSelection.contains(id) }
}
