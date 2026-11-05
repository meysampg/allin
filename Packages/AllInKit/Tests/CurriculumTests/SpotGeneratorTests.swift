import Foundation
import PokerAI
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SpotGeneratorTests {
  static let generator = GenerationTestSupport.generator

  /// Instance counts for the debug build: the plan asks for 1,000 (200 with consistency checks). Templates whose
  /// instances cost more than a few milliseconds in debug run fewer; the printed timings show why.
  static let reducedCounts: [String: Int] = [
    "fx.board.what-beats-me": 400, "fx.outs.count": 300, "fx.rules.call-cost": 400, "fx.potodds.obvious": 30,
    "fx.potodds.flush-draw": 30,
    "fx.reading.quiet-one-bets": 6,
  ]

  static func count(for template: SpotTemplate) -> Int { reducedCounts[template.id] ?? 1_000 }

  @Test(arguments: GenerationTestSupport.allTemplates.map(\.id))
  func fixtureTemplateGenerates(id: String) throws {
    let template = GenerationTestSupport.template(id)
    let total = Self.count(for: template)
    let clock = ContinuousClock()
    var hashes = Set<String>()
    var attempts = 0
    let elapsed = try clock.measure {
      for k in 0..<total {
        let seed = UInt64(1_000 + k)
        let instance = try Self.generator.generate(template, seed: seed)
        attempts += instance.attempt + 1
        hashes.insert(instance.instanceHash)
        try Self.check(instance, template: template)
      }
    }
    print("SPOTGEN \(id): \(total) instances, \(attempts) attempts, \(hashes.count) unique, \(elapsed)")
    #expect(Double(hashes.count) >= 0.99 * Double(total))
  }

  static func check(_ instance: SpotInstance, template: SpotTemplate) throws {
    let n = template.table.players
    let bb = template.table.blinds.big
    // Replaying the deck and the actions reproduces the state.
    let start = instance.start
    guard
      case .deckSetup(_, let deck)? = instance.log.events.first(where: {
        if case .deckSetup = $0.event { return true }
        return false
      })?.event
    else {
      Issue.record("no deck setup")
      return
    }
    var step = try HandReducer.start(
      config: start.config, button: start.button, stacks: start.seats.map { SeatStack(seat: $0.seat, stack: $0.stack) },
      deck: deck)
    for action in instance.actions {
      #expect(step.state.legalActions?.isLegal(action) == true)
      step = try HandReducer.apply(action, to: step.state)
    }
    #expect(step.state == instance.state)
    #expect(instance.state.seatToAct != nil)
    #expect(instance.street == template.board.street)
    #expect(instance.board.count == template.board.street.boardCount)
    #expect(Array(instance.fullBoard.prefix(instance.board.count)) == instance.board)
    #expect(instance.config.seatCount == n)

    switch template.line.stopAt {
    case .hero: #expect(instance.actor == instance.heroSeat)
    case .villain: #expect(instance.villainSeats.contains(instance.actor))
    case .any: break
    }
    // Predicates.
    #expect(template.board.matches(instance.board))
    let hero = instance.holeCards[instance.heroSeat]!
    #expect(template.hero.hand?.matches(hole: hero, board: instance.board) ?? true)
    for (index, villain) in template.villains.enumerated() {
      let cards = instance.holeCards[instance.villainSeats[index]]!
      #expect(villain.hand?.matches(hole: cards, board: instance.board) ?? true)
    }
    if let situation = template.situation { #expect(situation.matches(instance.actorContext)) }
    if let potBB = template.potBB { #expect(potBB.range.contains(Double(instance.state.pot) / Double(bb))) }
    // Positions and stacks.
    if let wanted = template.hero.position { #expect(wanted.contains(instance.positions[instance.heroSeat]!)) }
    for (index, villain) in template.villains.enumerated() {
      if let wanted = villain.position { #expect(wanted.contains(instance.positions[instance.villainSeats[index]]!)) }
    }
    for seat in instance.state.seats {
      let stackBB = Double(seat.startingStack) / Double(bb)
      #expect(template.table.stacksBB.range.contains(Int(stackBB)) && seat.startingStack % bb == 0)
    }
    // Names, characters, cards.
    #expect(instance.seatNames[instance.heroSeat] == "You")
    #expect(Set(instance.seatNames.values).count == n)
    #expect(Set(instance.holeCards.keys) == Set(0..<n))
    var seen = CardSet(instance.fullBoard)
    for cards in instance.holeCards.values {
      for card in cards {
        let fresh = seen.insert(card)
        #expect(fresh)
      }
    }
    #expect(instance.reveal.contains(instance.heroSeat))
    if template.reveal == .all { #expect(instance.reveal == Set(instance.villainSeats).union([instance.heroSeat])) }
    // Fixed cards (up to a suit permutation).
    if let fixed = template.fixed, !template.variation.contains(.suits) {
      if let cards = fixed.hero { #expect(hero == cards) }
      if let cards = fixed.board { #expect(Array(instance.board.prefix(cards.count)) == cards) }
    }
    if let fixed = template.fixed?.hero {
      #expect(hero.map(\.rank).sorted() == fixed.map(\.rank).sorted())
    }
  }
}
