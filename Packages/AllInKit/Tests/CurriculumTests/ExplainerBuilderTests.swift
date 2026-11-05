import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

enum ExplainTestSupport {
  static let catalog = CurriculumTestSupport.catalog

  struct Built {
    let template: SpotTemplate
    let instance: SpotInstance
    let ranges: [Int: HandRange]
  }

  static func built(_ id: String, seed: UInt64 = 7) async throws -> Built {
    let template = GenerationTestSupport.template(id)
    let instance = try GenerationTestSupport.generator.generate(template, seed: seed)
    let ranges = try await SpotRanges.villainRanges(instance, characters: catalog)
    return Built(template: template, instance: instance, ranges: ranges)
  }

  static func build(_ ref: ExplainerRef, _ b: Built) async throws -> ExplainerData {
    try await ExplainerBuilder.build(
      ref, instance: b.instance, template: b.template, characters: catalog, villainRanges: b.ranges)
  }
}

@Suite struct ExplainerBuilderTests {
  @Test func everyKindBuildsForAMatchingFixtureTemplate() async throws {
    var covered: Set<ExplainerKind> = []
    for template in GenerationTestSupport.allTemplates where template.board.street >= .flop && !template.explain.isEmpty
    {
      let b = try await ExplainTestSupport.built(template.id)
      for ref in template.explain {
        let data = try await ExplainTestSupport.build(ref, b)
        #expect(data.kind == ref.explainer)
        covered.insert(ref.explainer)
      }
    }
    // Kinds no fixture template references are built against a flop spot.
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    for kind in ExplainerKind.allCases where !covered.contains(kind) {
      let data = try await ExplainTestSupport.build(ExplainerRef(explainer: kind), b)
      #expect(data.kind == kind)
    }
  }

  @Test func timelineGroupsActionsByStreet() async throws {
    let b = try await ExplainTestSupport.built("fx.reading.quiet-one-bets")
    let data = try await ExplainTestSupport.build(ExplainerRef(explainer: .bettingRoundsTimeline), b)
    guard case .bettingRoundsTimeline(let t) = data else { Issue.record("wrong kind"); return }
    #expect(t.streets.map(\.name) == ["Preflop", "Flop", "Turn", "River"])
    #expect(t.current == 3)
    #expect(t.streets[3].board.count == 5)
    #expect(t.streets[0].board.isEmpty)
    let river = t.streets[3].actions
    #expect(river.first == "You: check")
    #expect(river.last?.hasPrefix("\(b.instance.seatNames[b.instance.villainSeats[0]]!): bet ") == true)
  }

  @Test func potCounterTotalsThePot() async throws {
    for id in ["fx.reading.quiet-one-bets", "fx.potodds.flush-draw", "fx.value.river-bet-or-check"] {
      let b = try await ExplainTestSupport.built(id)
      let data = try await ExplainTestSupport.build(ExplainerRef(explainer: .potCounter), b)
      guard case .potCounter(let p) = data else { Issue.record("wrong kind"); return }
      #expect(p.entries.first?.label == "Blinds")
      #expect(p.entries.map(\.amount).reduce(0, +) == p.total)
      #expect(p.total == b.instance.state.pot)
    }
  }

  @Test func potSlicesNumbersEqualTheContext() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let context = try #require(b.instance.heroContext)
    let data = try await ExplainTestSupport.build(ExplainerRef(explainer: .potSlices), b)
    guard case .potSlices(let s) = data else { Issue.record("wrong kind"); return }
    #expect(s.pot == context.pot)
    #expect(s.call == context.legal.toCall)
    // Not facing a bet: the call is a bet of the bound size.
    let free = try await ExplainTestSupport.built("fx.value.river-bet-or-check")
    let freeContext = try #require(free.instance.heroContext)
    #expect(freeContext.legal.toCall == 0)
    let ref = ExplainerRef(explainer: .potSlices)
    guard case .potSlices(let f) = try await ExplainTestSupport.build(ref, free) else { return }
    #expect(f.call == max(1, Int((0.5 * Double(freeContext.pot)).rounded())))
  }

  @Test func ladderHighlightsHeroAndRevealedVillain() async throws {
    let b = try await ExplainTestSupport.built("fx.ranks.pick-winner")
    let data = try await ExplainTestSupport.build(ExplainerRef(explainer: .handRankLadder), b)
    guard case .handRankLadder(let l) = data else { Issue.record("wrong kind"); return }
    #expect(l.highlights.values.contains { $0.contains("You") })
    #expect(l.highlights.values.contains { $0.contains(b.instance.seatNames[b.instance.villainSeats[0]]!) })
    let heroOnly = ExplainerRef(explainer: .handRankLadder, bind: ["highlight": "hero"])
    guard case .handRankLadder(let h) = try await ExplainTestSupport.build(heroOnly, b) else { return }
    #expect(h.highlights.count == 1)
  }

  @Test func bestFiveUsesTheBoundHand() async throws {
    let b = try await ExplainTestSupport.built("fx.ranks.best-five")
    for hand in ["hero", "villain", "winner"] {
      let ref = ExplainerRef(explainer: .bestFiveHighlight, bind: ["hand": hand])
      guard case .bestFiveHighlight(let d) = try await ExplainTestSupport.build(ref, b) else { return }
      #expect(d.best.count == 5)
      #expect(Set(d.cards).isSuperset(of: Set(d.best)))
      #expect(d.cards.count == 2 + b.instance.board.count)
    }
  }

  @Test func nutsScanFlagsMatchTheTexture() async throws {
    let b = try await ExplainTestSupport.built("fx.board.find-nuts")
    let data = try await ExplainTestSupport.build(ExplainerRef(explainer: .boardNutsScan), b)
    guard case .boardNutsScan(let n) = data else { Issue.record("wrong kind"); return }
    let texture = BoardAnalyzer.texture(b.instance.board)
    #expect(n.board == b.instance.board)
    #expect(n.flushPossible == texture.flushPossible)
    #expect(n.straightPossible == texture.straightPossible)
    #expect(n.fullHousePossible == (texture.isPaired || texture.hasTrips))
    #expect(n.nutCards.count == 2)
    #expect(!n.nuts.isEmpty)
  }

  @Test func outsGlowCountsUnseenCards() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    guard case .outsGlow(let o) = try await ExplainTestSupport.build(ExplainerRef(explainer: .outsGlow), b) else {
      return
    }
    #expect(o.unseen == 52 - 2 - b.instance.board.count)
    #expect(o.exactEquity != nil)
    #expect((0.0...1.0).contains(o.exactEquity ?? -1))
  }

  @Test func whoCallsMeCallersSumToTheRange() async throws {
    let b = try await ExplainTestSupport.built("fx.value.river-bet-or-check")
    let ref = ExplainerRef(explainer: .whoCallsMe, bind: ["mode": "callers", "size": "bet:0.5"])
    guard case .whoCallsMe(let w) = try await ExplainTestSupport.build(ref, b) else { return }
    #expect(w.mode == .callers)
    #expect(abs(w.worseCalls + w.betterCalls + w.folds - 1) < 1e-9)
    #expect(w.cells.count == 13 && w.cells.allSatisfy { $0.count == 13 })
    #expect(w.betLabel?.hasPrefix("You bet") == true)
    #expect(w.cells.joined().contains { $0 != .none })
  }

  @Test func whoCallsMeBettorsForTheQuietOneBetsTemplate() async throws {
    let b = try await ExplainTestSupport.built("fx.reading.quiet-one-bets")
    guard case .whoCallsMe(let w) = try await ExplainTestSupport.build(ExplainerRef(explainer: .whoCallsMe), b) else {
      return
    }
    #expect(w.mode == .bettors)
    #expect(w.folds == 0)
    #expect(abs(w.worseCalls + w.betterCalls - 1) < 1e-9)
    #expect(w.betLabel?.contains("bet") == true)
    let villain = b.instance.villainSeats[0]
    let hero = b.instance.holeCards[b.instance.heroSeat]!
    let range = b.ranges[villain]!
    // The split matches the tracked range.
    let heroValue = HandEvaluator.evaluate(hole: hero, board: b.instance.board)
    var better = 0.0
    var total = 0.0
    for combo in range.nonZeroCombos {
      total += Double(range[combo])
      if HandEvaluator.evaluate(hole: combo.cards, board: b.instance.board) > heroValue {
        better += Double(range[combo])
      }
    }
    #expect(abs(w.betterCalls - better / total) < 1e-6)
  }

  @Test func deterministic() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw", seed: 21)
    for kind in ExplainerKind.allCases {
      let first = try await ExplainTestSupport.build(ExplainerRef(explainer: kind), b)
      let second = try await ExplainTestSupport.build(ExplainerRef(explainer: kind), b)
      #expect(first == second)
    }
  }
}
