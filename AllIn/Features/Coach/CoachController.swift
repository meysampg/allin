import Observation
import PokerAI
import PokerCore
import PokerEquity

/// Reads an opponent's range for the coach panel. The Bayesian update runs off the main actor.
@MainActor @Observable
final class CoachController {
  enum RangeState: Equatable {
    case hidden
    case loading(name: String)
    case shown(CoachRange)
    case failed(String)
  }

  private(set) var rangeState: RangeState = .hidden
  let heroSeat: Int
  var hintLevel: CoachHintLevel

  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = 0

  init(heroSeat: Int, hintLevel: CoachHintLevel) {
    self.heroSeat = heroSeat
    self.hintLevel = hintLevel
  }

  /// Off-main: extract the decision points of the hand so far, track every seat but the hero, return `seat`'s range.
  /// A newer request cancels the older one.
  func showRange(
    seat: Int, name: String, hostEvents: [LoggedEvent], strategies: [Int: any StrategyProvider], heroCards: [Card]
  ) {
    task?.cancel()
    generation += 1
    let id = generation
    rangeState = .loading(name: name)
    let hero = heroSeat
    task = Task { [weak self] in
      let outcome = await Task.detached(priority: .userInitiated) {
        await Self.compute(
          seat: seat, name: name, hero: hero, events: hostEvents, strategies: strategies, heroCards: heroCards)
      }.value
      guard let self, !Task.isCancelled, id == generation else { return }
      switch outcome {
      case .success(let range): rangeState = .shown(range)
      case .failure(let message): rangeState = .failed(message)
      }
    }
  }

  /// Shows the loading state straight away, before the host events are ready.
  func markLoading(name: String) {
    rangeState = .loading(name: name)
  }

  func hideRange() {
    task?.cancel()
    task = nil
    generation += 1
    rangeState = .hidden
  }

  func reset() {
    hideRange()
  }

  private enum Outcome: Sendable {
    case success(CoachRange)
    case failure(String)
  }

  nonisolated private static func compute(
    seat: Int, name: String, hero: Int, events: [LoggedEvent], strategies: [Int: any StrategyProvider],
    heroCards: [Card]
  ) async -> Outcome {
    guard let start = DecisionPoints.start(of: events) else { return .failure("No hand to read yet.") }
    let points: [DecisionPoint]
    do {
      points = try DecisionPoints.extract(from: events)
    } catch {
      return .failure("I could not replay this hand.")
    }
    let seats = start.seats.map(\.seat).filter { $0 != hero }
    var tracker = RangeTracker(seats: seats, observer: hero, observerCards: heroCards, strategies: strategies)
    await tracker.observe(points)
    guard let range = tracker.range(of: seat) else { return .failure("I have no read on \(name).") }
    var dead = CardSet(heroCards)
    for case .streetDealt(_, let cards) in events.map(\.event) { dead = dead.union(CardSet(cards)) }
    return .success(
      CoachRange(
        seat: seat, name: name, range: range, dead: dead, actionsRead: tracker.actionsObserved[seat] ?? 0,
        inconsistent: tracker.inconsistentSeats.contains(seat)))
  }
}
