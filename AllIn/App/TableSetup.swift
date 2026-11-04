import PokerCore
import PokerHost

struct TableSetup: Hashable, Sendable {
  enum Format: String, CaseIterable, Sendable {
    case cash6Max, fullRing, headsUp, sitAndGo, tournament

    var isPlayable: Bool { self == .cash6Max || self == .headsUp }

    var seatCount: Int {
      switch self {
      case .cash6Max: 6
      case .fullRing: 9
      case .headsUp: 2
      case .sitAndGo: 6
      case .tournament: 9
      }
    }

    var title: String {
      switch self {
      case .cash6Max: "Cash Game 6-max"
      case .fullRing: "Full Ring"
      case .headsUp: "Heads-Up"
      case .sitAndGo: "Sit & Go"
      case .tournament: "Tournament"
      }
    }

    var subtitle: String {
      switch self {
      case .cash6Max: "Six seats, steady blinds"
      case .fullRing: "Nine seats, slower action"
      case .headsUp: "One rival, all duel"
      case .sitAndGo: "Six players, rising blinds"
      case .tournament: "Nine players, a long climb"
      }
    }

    var lockedNote: String? { isPlayable ? nil : "Opens in a later update" }
  }

  enum CoachMode: String, CaseIterable, Sendable { case questions, review, off }
  enum HUDMode: String, CaseIterable, Sendable { case off, basic, full }

  var format: Format = .cash6Max
  var opponentIDs: [String]
  var smallBlind = 1
  var bigBlind = 2
  var buyIn = 200
  var coach: CoachMode = .questions
  var hud: HUDMode = .basic
  var speed: GameSpeed = .normal
  var tableStrength: Double = 0.5
  var seed: UInt64

  var heroSeat: Int { 0 }
  var seatCount: Int { format.seatCount }

  static let lobbyRoster = ["grumli", "zib", "vexa", "mott", "oryn"]
  static let fillPool = ["grumli", "zib", "vexa", "mott", "oryn", "bram", "patron"]

  static func demo(seed: UInt64) -> TableSetup {
    TableSetup(opponentIDs: lobbyRoster, seed: seed)
  }

  /// Takes `selected` in order (truncated to the seats available), then fills the rest from `fillPool`.
  /// With `randomMix` the fill is a seeded shuffle; otherwise it is in pool order. Deterministic either way.
  static func resolveOpponents(format: Format, selected: [String], randomMix: Bool, seed: UInt64) -> [String] {
    let needed = format.seatCount - 1
    var result = Array(selected.prefix(needed))
    var rest = fillPool.filter { !result.contains($0) }
    if randomMix {
      var rng = SeededRNG(seed: seed)
      rest.shuffle(using: &rng)
    }
    var fillPoolCycle = rest
    // The pool holds 7 bots; larger tables repeat from the pool start.
    while fillPoolCycle.count < needed { fillPoolCycle += fillPool }
    result += fillPoolCycle.prefix(needed - result.count)
    return result
  }
}
