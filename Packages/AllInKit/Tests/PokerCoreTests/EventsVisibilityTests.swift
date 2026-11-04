import Foundation
import Testing

@testable import PokerCore

@Suite struct EventsVisibilityTests {
  /// Cards that appear anywhere in an event's payload.
  private func cardsIn(_ event: GameEvent) -> Set<Card> {
    switch event {
    case .holeCardsDealt(_, let c), .streetDealt(_, let c): Set(c)
    case .deckSetup(_, let d): Set(d)
    case .burned(_, let c): [c]
    case .showdown(let r), .mucked(let r): Set(r.flatMap { $0.holeCards + $0.bestFive })
    case .handEnded(let r): Set(r.board)
    default: []
    }
  }

  private func jsonText(_ events: [LoggedEvent]) throws -> String {
    String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
  }

  @Test func seatViewNeverLeaksOthersOrHostData() throws {
    for seed in UInt64(1)...300 {
      let played = try EventsRandomHands.play(seed: seed)
      let shownHoles = Set(
        played.log.events.flatMap { e -> [(Int, Card)] in
          if case .showdown(let r) = e.event { return r.flatMap { x in x.holeCards.map { (x.seat, $0) } } }
          return []
        }.map(\.1))
      for seat in played.holeCards.keys {
        let view = played.log.filtered(for: .seat(seat))
        let own = Set(played.holeCards[seat]!)
        let others = Set(played.holeCards.filter { $0.key != seat }.values.flatMap { $0 })
        var sawShowdown = false
        for logged in view {
          switch logged.event {
          case .deckSetup, .burned, .mucked: Issue.record("host-only event leaked, seed \(seed)")
          case .showdown: sawShowdown = true
          default: break
          }
          if case .holeCardsDealt(let s, _) = logged.event { #expect(s == seat) }
          if !sawShowdown, case .holeCardsDealt = logged.event { continue }
          let leaked = cardsIn(logged.event).intersection(others).subtracting(own)
          if !sawShowdown || !(logged.event.isShowdownReveal) {
            // Before showdown (and outside the showdown reveal itself) no other seat's hole card may appear,
            // unless the card is also a board card of the same value (impossible: cards are unique).
            #expect(leaked.isEmpty, "seed \(seed) seat \(seat) leaked \(leaked)")
          } else {
            #expect(leaked.isSubset(of: shownHoles))
          }
        }
        // Own hole cards are delivered.
        #expect(view.contains { $0.event == .holeCardsDealt(seat: seat, cards: played.holeCards[seat]!) })
      }
    }
  }

  @Test func seatViewTextHasNoSeedOrDeck() throws {
    for seed in UInt64(1)...60 {
      let played = try EventsRandomHands.play(seed: seed)
      guard case .deckSetup(let s, let deck) = played.log.events[1].event else { throw ReplayError.incompleteLog }
      for viewer in [Viewer.seat(0), .seat(1), .spectator] {
        let view = played.log.filtered(for: viewer)
        #expect(!view.contains { $0.event.visibility == .hostOnly })
        let text = try jsonText(view)
        #expect(!text.contains("\"deckSetup\""))
        #expect(!text.contains("seed"))
        if let s { #expect(!text.contains(String(s)) || String(s).count < 4) }
        // The full deck order never appears as a contiguous run.
        #expect(!text.contains(deck.prefix(12).map { String($0.index) }.joined(separator: ",")))
      }
    }
  }

  @Test func spectatorSeesOnlyRevealedHoleCards() throws {
    for seed in UInt64(1)...300 {
      let played = try EventsRandomHands.play(seed: seed)
      let allHoles = Set(played.holeCards.values.flatMap { $0 })
      var revealed: Set<Card> = []
      for logged in played.log.filtered(for: .spectator) {
        if case .holeCardsDealt = logged.event { Issue.record("spectator saw a deal, seed \(seed)") }
        if case .showdown(let reveals) = logged.event { revealed.formUnion(reveals.flatMap(\.holeCards)) }
        // Hole cards may only appear after being revealed (the board can never contain a hole card).
        let seen = cardsIn(logged.event).intersection(allHoles)
        #expect(seen.isSubset(of: revealed), "seed \(seed)")
      }
      // Hole cards of seats that mucked or folded stay hidden from spectators.
      let hostMucked = played.log.events.flatMap { e -> [Card] in
        if case .mucked(let r) = e.event { return r.flatMap(\.holeCards) }
        return []
      }
      #expect(Set(hostMucked).isDisjoint(with: revealed))
    }
  }

  @Test func hostSeesEverythingAndMuckedHandsAreHostOnly() throws {
    var sawMuck = false
    for seed in UInt64(1)...300 {
      let played = try EventsRandomHands.play(seed: seed)
      #expect(played.log.filtered(for: .host) == played.log.events)
      sawMuck = sawMuck || played.log.events.contains { if case .mucked = $0.event { true } else { false } }
    }
    #expect(sawMuck, "no random hand produced a muck; widen the seeds")
  }

  @Test func filteredViewKeepsSequenceNumbers() throws {
    let played = try EventsRandomHands.play(seed: 5)
    let view = played.log.filtered(for: .spectator)
    #expect(view.map(\.seq) == view.map(\.seq).sorted())
    #expect(view.count < played.log.events.count)
  }
}

extension GameEvent {
  fileprivate var isShowdownReveal: Bool {
    if case .showdown = self { true } else { false }
  }
}
