import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct SpotRangesTests {
  static let catalog = CurriculumTestSupport.catalog

  @Test func trackedRangeAfterAnOpenIsTighterThanFull() async throws {
    let template = GenerationTestSupport.template("fx.potodds.obvious")
    let instance = try GenerationTestSupport.generator.generate(template, seed: 11)
    let villain = try #require(instance.villainSeats.first)
    let ranges = try await SpotRanges.villainRanges(instance, characters: Self.catalog)
    let range = try #require(ranges[villain])
    let dead = CardSet(instance.holeCards[instance.heroSeat]! + instance.board)
    let full = HandRange.full.removing(dead).totalWeight
    print("SPOTRANGES vexa weight \(range.totalWeight) of \(full)")
    #expect(range.totalWeight > 0)
    #expect(range.totalWeight < 0.9 * full)
    // Cards the hero holds are never in the villain's range.
    for card in instance.holeCards[instance.heroSeat]! {
      #expect(range.nonZeroCombos.allSatisfy { !$0.cards.contains(card) })
    }
  }

  @Test func deterministic() async throws {
    let template = GenerationTestSupport.template("fx.potodds.obvious")
    let instance = try GenerationTestSupport.generator.generate(template, seed: 12)
    let first = try await SpotRanges.villainRanges(instance, characters: Self.catalog)
    let second = try await SpotRanges.villainRanges(instance, characters: Self.catalog)
    #expect(first == second)
  }

  @Test func villainWithoutCharacterKeepsFullRange() async throws {
    let template = GenerationTestSupport.template("fx.ranks.best-five")
    let instance = try GenerationTestSupport.generator.generate(template, seed: 5)
    let ranges = try await SpotRanges.villainRanges(instance, characters: Self.catalog)
    let dead = CardSet(instance.holeCards[instance.heroSeat]! + instance.board)
    #expect(ranges.count == instance.villainSeats.count)
    for seat in instance.villainSeats { #expect(ranges[seat] == HandRange.full.removing(dead)) }
  }

  @Test func strategiesCoverEverySeatButTheHero() throws {
    let template = GenerationTestSupport.template("fx.potodds.obvious")
    let instance = try GenerationTestSupport.generator.generate(template, seed: 13)
    let strategies = SpotRanges.strategies(instance, characters: Self.catalog)
    #expect(Set(strategies.keys) == Set(instance.state.seats.map(\.seat)).subtracting([instance.heroSeat]))
  }
}
