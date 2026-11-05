import Curriculum
import PokerCore
import TableKit

/// A spot as the table shows it: the hero's view of the prefix, with the revealed seats' cards turned up.
struct LessonSnapshot {
  let seats: [TableSeatInfo]
  let snapshot: TableSnapshot
  let overlay: LessonController.TableOverlay

  init(instance: SpotInstance, characters: CharacterCatalog?) {
    let seats = (0..<instance.config.seatCount).map { seat -> TableSeatInfo in
      if seat == instance.heroSeat {
        return TableSeatInfo(seat: seat, name: "You", characterID: "you", styleHint: nil, isHero: true)
      }
      let character = instance.seatCharacters[seat]
      return TableSeatInfo(
        seat: seat, name: instance.seatNames[seat] ?? "Seat \(seat + 1)", characterID: character,
        styleHint: character.flatMap { characters?.style($0) }, isHero: false)
    }
    // The cues of the model are ignored: the scene shows the final position without animation.
    var table = TableModel(config: instance.config, seats: seats, heroSeat: instance.heroSeat)
    for event in instance.log.filtered(for: .seat(instance.heroSeat)) { _ = table.apply(event) }
    var snapshot = table.snapshot
    for seat in instance.reveal where snapshot.seats.indices.contains(seat) && snapshot.seats[seat].hasCards {
      if let cards = instance.holeCards[seat] { snapshot.seats[seat].holeCards = cards }
    }
    self.seats = seats
    self.snapshot = snapshot
    overlay = Self.overlay(for: snapshot, instance: instance)
  }

  /// "POT 150 (+50)" and the villain's "Vexa · bets 50" or "checks".
  static func overlay(for snapshot: TableSnapshot, instance: SpotInstance) -> LessonController.TableOverlay {
    let maxBet = snapshot.seats.map(\.committed).max() ?? 0
    let potText = maxBet > 0 ? "POT \(snapshot.potTotal) (+\(maxBet))" : "POT \(snapshot.potTotal)"
    var tag: String?
    var tagSeat: Int?
    let villains = instance.villainSeats.filter { snapshot.seats.indices.contains($0) }
    func name(_ seat: Int) -> String { instance.seatNames[seat] ?? snapshot.seats[seat].info.name }
    if let bettor = villains.max(by: { snapshot.seats[$0].committed < snapshot.seats[$1].committed }) {
      let committed = snapshot.seats[bettor].committed
      let threshold = instance.street == .preflop ? snapshot.bigBlind : 0
      if committed > threshold {
        tag = "\(name(bettor)) · \(instance.street == .preflop ? "raises to" : "bets") \(committed)"
        tagSeat = bettor
      } else if let check = villains.first(where: { snapshot.seats[$0].lastAction == "Check" }) {
        tag = "\(name(check)) · checks"
        tagSeat = check
      }
    }
    return LessonController.TableOverlay(
      villainTag: tag, villainSeat: tagSeat, heroSeat: instance.heroSeat, seatCount: instance.config.seatCount,
      potText: potText)
  }
}
