import Foundation
import PokerCore
import PokerEquity
import Testing

@testable import PokerAI

@Suite("RangeTracker")
struct RangeTrackerTests {
  private static let allSeats = [0, 1, 2, 3, 4, 5]

  /// UTG (seat 3) is first to act preflop in the 6-max script with the button on seat 0.
  private static func openContext() -> DecisionContext { AIScript.context(actions: []) }
  private static func facingRaise() -> DecisionContext { AIScript.context(actions: [.raise(to: 300)]) }

  private static func name(_ combo: Combo) -> String { combo.handClass.description }

  private static func nonZeroClasses(_ range: HandRange) -> Set<String> {
    Set(range.nonZeroCombos.map { name($0) })
  }

  private static func tracker(
    observer: Int? = nil, cards: [Card] = [], strategies: [Int: any StrategyProvider] = [:],
    options: RangeTrackerOptions = .standard
  ) -> RangeTracker {
    RangeTracker(
      seats: allSeats.filter { $0 != observer }, observer: observer, observerCards: cards,
      strategies: strategies, options: options)
  }

  @Test func raiseOnlyWithPremiumsLeavesPremiums() {
    let strategy = TableStrategy { context in
      let hole = Combo(context.holeCards[0], context.holeCards[1]).handClass.description
      let premium = ["AA", "KK"].contains(hole)
      guard premium, let range = context.legal.raiseRange else { return [(.fold, 1)] }
      return [(.raise(to: max(300, range.lowerBound)), 1)]
    }
    let observerCards = AITestSupport.cards("As Ks")
    var tracker = Self.tracker(observer: 0, cards: observerCards, strategies: [3: strategy])
    tracker.observe(Self.openContext(), action: .raise(to: 300))
    let range = tracker.range(of: 3)!
    #expect(Self.nonZeroClasses(range) == ["AA", "KK"])
    let expected = Set(["AA", "KK"].flatMap { try! HandClass($0).combos }).filter {
      $0.mask.isDisjoint(with: CardSet(observerCards))
    }
    #expect(Set(range.nonZeroCombos) == expected)
    #expect(tracker.inconsistentSeats.isEmpty)
    #expect(tracker.actionsObserved[3] == 1)
  }

  @Test func likelihoodRatioIsKept() {
    let strategy = TableStrategy { context in
      switch Combo(context.holeCards[0], context.holeCards[1]).handClass.description {
      case "QQ": return [(.call, 0.5), (.fold, 0.5)]
      case "JJ": return [(.call, 1)]
      default: return [(.fold, 1)]
      }
    }
    var tracker = Self.tracker(strategies: [4: strategy])
    tracker.observe(Self.facingRaise(), action: .call)
    let range = tracker.range(of: 4)!
    #expect(range[try! Combo("JhJs")] == 1)
    #expect(range[try! Combo("QhQs")] == 0.5)
    #expect(Self.nonZeroClasses(range) == ["QQ", "JJ"])
  }

  @Test func observerAndBoardCardsAreRemoved() {
    let flop = AITestSupport.cards("Ks 7d 2c")
    let hero = AITestSupport.cards("As Qh")
    let checkAll = TableStrategy { _ in [(.check, 1)] }
    var tracker = Self.tracker(observer: 0, cards: hero, strategies: [1: checkAll])
    // The SB acts first on the flop after a limped pot.
    let context = Self.withFlop(flop)
    tracker.observe(context, action: .check)
    let range = tracker.range(of: context.seat)!
    let dead = CardSet(hero + flop)
    #expect(range.nonZeroCombos.allSatisfy { $0.mask.isDisjoint(with: dead) })
    #expect(!range.nonZeroCombos.isEmpty)
    #expect(range[try! Combo("AsAh")] == 0)
  }

  private static func withFlop(_ flop: [Card]) -> DecisionContext {
    let base = AIScript.context(actions: [.fold, .fold, .fold, .call, .call, .check])
    precondition(base.street == .flop)
    return RangeScript.withBoard(base, flop)
  }

  @Test func zeroLikelihoodKeepsPrior() {
    let alwaysFold = TableStrategy { _ in [(.fold, 1)] }
    var tracker = Self.tracker(strategies: [3: alwaysFold])
    let before = tracker.range(of: 3)!
    tracker.observe(Self.openContext(), action: .raise(to: 300))
    #expect(tracker.range(of: 3) == before)
    #expect(tracker.inconsistentSeats == [3])
  }

  @Test func classFallbackWhenExactActionIsImpossible() {
    // Only a 400 raise is ever played; the observed 300 raise matches by class.
    let strategy = TableStrategy { context in
      let hole = Combo(context.holeCards[0], context.holeCards[1]).handClass.description
      return hole == "AA" ? [(.raise(to: 400), 1)] : [(.fold, 1)]
    }
    var tracker = Self.tracker(strategies: [3: strategy])
    tracker.observe(Self.openContext(), action: .raise(to: 300))
    #expect(Self.nonZeroClasses(tracker.range(of: 3)!) == ["AA"])
    #expect(tracker.inconsistentSeats.isEmpty)
  }

  /// A scripted preflop open and a flop bet, as decision points.
  private static func openAndBetPoints() throws -> [DecisionPoint] {
    let deck = RangeScript.deckWith(
      seatCount: 6, button: 0, holes: [0: AITestSupport.cards("As Ks")],
      board: AITestSupport.cards("Qh 7d 2c"))
    let actions: [Action] = [.raise(to: 300), .fold, .fold, .fold, .fold, .call, .check, .bet(to: 300)]
    return try DecisionPoints.extract(from: RangeScript.scriptedLog(deck: deck, actions: actions))
  }

  private static func vexaAndGrumli() throws -> (vexa: any StrategyProvider, grumli: any StrategyProvider) {
    let roster = try BotRoster.load()
    return (
      try #require(roster.first { $0.id == "vexa" }).strategy,
      try #require(roster.first { $0.id == "grumli" }).strategy
    )
  }

  /// Synchronous on purpose: inside an async test the call would otherwise bind to the async overload.
  private static func observeSerially(_ tracker: inout RangeTracker, _ points: [DecisionPoint]) {
    for point in points { tracker.observe(point.context, action: point.action) }
  }

  @Test func asyncEqualsSerial() async throws {
    let (vexa, grumli) = try Self.vexaAndGrumli()
    let points = try Self.openAndBetPoints()
    #expect(points.count == 8)
    let strategies: [Int: any StrategyProvider] = [2: grumli, 3: vexa]
    let hero = AITestSupport.cards("As Ks")

    var serial = Self.tracker(observer: 0, cards: hero, strategies: strategies)
    Self.observeSerially(&serial, points.filter { [2, 3].contains($0.context.seat) })
    var parallel = Self.tracker(observer: 0, cards: hero, strategies: strategies)
    await parallel.observe(points)
    var oneChunk = Self.tracker(
      observer: 0, cards: hero, strategies: strategies,
      options: RangeTrackerOptions(chunks: 1))
    await oneChunk.observe(points)

    #expect(serial.range(of: 3) == parallel.range(of: 3))
    #expect(serial.range(of: 2) == parallel.range(of: 2))
    #expect(serial.range(of: 3) == oneChunk.range(of: 3))
    #expect(serial.actionsObserved == parallel.actionsObserved.filter { [2, 3].contains($0.key) })
    #expect(serial.inconsistentSeats == parallel.inconsistentSeats)
    #expect(serial.range(of: 3)!.totalWeight > 0)
  }

  @Test func rockOpenIsTight() throws {
    let (vexa, _) = try Self.vexaAndGrumli()
    var tracker = Self.tracker(strategies: [3: vexa])
    tracker.observe(Self.openContext(), action: .raise(to: 300))
    let range = tracker.range(of: 3)!
    #expect(tracker.inconsistentSeats.isEmpty)
    #expect(range.totalWeight < 0.3 * 1326)
    #expect(range.weight(of: try HandClass("AA")) >= 0.9)
  }

  @Test func stationCallIsWide() throws {
    let (vexa, grumli) = try Self.vexaAndGrumli()
    var rock = Self.tracker(strategies: [4: vexa])
    var station = Self.tracker(strategies: [4: grumli])
    rock.observe(Self.facingRaise(), action: .call)
    station.observe(Self.facingRaise(), action: .call)
    #expect(station.range(of: 4)!.totalWeight > rock.range(of: 4)!.totalWeight)
  }

  @Test func deterministic() throws {
    let (vexa, grumli) = try Self.vexaAndGrumli()
    let strategies: [Int: any StrategyProvider] = [3: vexa, 4: grumli]
    var a = Self.tracker(strategies: strategies)
    var b = Self.tracker(strategies: strategies)
    a.observe(Self.openContext(), action: .raise(to: 300))
    a.observe(Self.facingRaise(), action: .call)
    b.observe(Self.openContext(), action: .raise(to: 300))
    b.observe(Self.facingRaise(), action: .call)
    #expect(a.ranges == b.ranges)
  }

  @Test func postflopUpdateTiming() throws {
    let (_, grumli) = try Self.vexaAndGrumli()
    let flop = AITestSupport.cards("Ks 7d 2c")
    let context = Self.withFlop(flop)
    var tracker = Self.tracker(strategies: [context.seat: grumli])
    let clock = ContinuousClock()
    let elapsed = clock.measure { tracker.observe(context, action: .check) }
    print("postflopUpdateTiming flop update (Grumli): \(elapsed)")
    var preflop = Self.tracker(strategies: [3: grumli])
    let pre = clock.measure { preflop.observe(Self.openContext(), action: .raise(to: 300)) }
    print("postflopUpdateTiming preflop update (Grumli): \(pre)")
    #expect(elapsed < .seconds(120))
  }
}
