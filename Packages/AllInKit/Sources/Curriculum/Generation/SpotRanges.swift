import Foundation
import PokerAI
import PokerCore
import PokerEquity

/// Villain range tracking for generated spots.
public enum SpotRanges {
  /// Villain strategies: the catalog strategy for the seat's character, else `BaselineStrategy()`.
  public static func strategies(
    _ instance: SpotInstance, characters: CharacterCatalog
  ) -> [Int: any StrategyProvider] {
    var result: [Int: any StrategyProvider] = [:]
    let baseline = BaselineStrategy()
    for seat in instance.state.seats.map(\.seat) where seat != instance.heroSeat {
      result[seat] = instance.seatCharacters[seat].flatMap { characters.strategy($0) } ?? baseline
    }
    return result
  }

  /// `DecisionPoints.extract(instance.log)` fed to a `RangeTracker` (observer: the hero) for the villains that
  /// have a character. Villains without a character keep `HandRange.full` minus the hero's cards and the board.
  public static func villainRanges(
    _ instance: SpotInstance, characters: CharacterCatalog, options: RangeTrackerOptions = .standard
  ) async throws -> [Int: HandRange] {
    let points = try DecisionPoints.extract(from: instance.log)
    let strategies = strategies(instance, characters: characters)
    let heroCards = instance.holeCards[instance.heroSeat] ?? []
    let tracked = instance.villainSeats.filter { instance.seatCharacters[$0] != nil }
    var tracker = RangeTracker(
      seats: tracked, observer: instance.heroSeat, observerCards: heroCards,
      strategies: strategies.filter { tracked.contains($0.key) }, options: options)
    await tracker.observe(points)
    let dead = CardSet(heroCards + instance.board)
    var result: [Int: HandRange] = [:]
    for seat in instance.villainSeats {
      result[seat] =
        tracked.contains(seat) ? ((tracker.range(of: seat) ?? .full).removing(dead)) : HandRange.full.removing(dead)
    }
    return result
  }
}
