import Foundation
import Testing

@testable import PokerCore
@testable import PokerEquity

private let preflopTableLoaded = PreflopEquityTable.shared != nil

private func preflopRandomPair(_ rng: inout SeededRNG) -> ([Card], [Card]) {
  let deck = Card.all.shuffled(using: &rng)
  return ([deck[0], deck[1]], [deck[2], deck[3]])
}

/// Relabels suits with permutation number `p` (0..<24) of the four suits.
private func preflopRelabel(_ cards: [Card], _ perm: [Int]) -> [Card] {
  cards.map { Card(rank: $0.rank, suit: Suit(rawValue: UInt8(perm[Int($0.suit.rawValue)]))!) }
}

private func preflopAllPermutations() -> [[Int]] {
  var out: [[Int]] = []
  for a in 0..<4 {
    for b in 0..<4 where b != a {
      for c in 0..<4 where c != a && c != b { out.append([a, b, c, 6 - a - b - c]) }
    }
  }
  return out
}

@Suite("Preflop table") struct PreflopTableTests {
  @Test(.enabled(if: preflopTableLoaded))
  func loadsWithPlausibleEntryCount() throws {
    let table = try #require(PreflopEquityTable.shared)
    #expect((40_000...60_000).contains(table.entryCount))
  }

  @Test(.enabled(if: preflopTableLoaded))
  func swappedHandsSumToOne() throws {
    let table = try #require(PreflopEquityTable.shared)
    var rng = SeededRNG(seed: 26)
    for _ in 0..<200 {
      let (a, b) = preflopRandomPair(&rng)
      let ab = try #require(table.equity(a, b))
      let ba = try #require(table.equity(b, a))
      #expect(abs(ab.equity + ba.equity - 1) <= 2.0 / 65535)
      #expect(ab.isExact)
    }
  }

  @Test(.enabled(if: preflopTableLoaded))
  func suitRelabelingsAgree() throws {
    let table = try #require(PreflopEquityTable.shared)
    var rng = SeededRNG(seed: 27)
    for _ in 0..<5 {
      let (a, b) = preflopRandomPair(&rng)
      let base = try #require(table.equity(a, b))
      for perm in preflopAllPermutations() {
        let other = try #require(table.equity(preflopRelabel(a, perm), preflopRelabel(b, perm)))
        #expect(other.equity == base.equity)
        #expect(other.tie == base.tie)
      }
    }
  }

  @Test(.enabled(if: preflopTableLoaded))
  func knownMatchupsAreSensible() throws {
    let table = try #require(PreflopEquityTable.shared)
    let aces = try #require(table.equity(try Card.parseList("AhAd"), try Card.parseList("KsKc")))
    #expect(abs(aces.equity - 0.8195) < 0.015, "aces equity \(aces.equity)")
    let coinFlip = try #require(table.equity(try Card.parseList("AsKs"), try Card.parseList("QhQd")))
    #expect(abs(coinFlip.equity - 0.46) < 0.02)
  }

  @Test(.enabled(if: preflopTableLoaded))
  func overlappingCardsReturnNil() throws {
    let table = try #require(PreflopEquityTable.shared)
    #expect(table.equity(try Card.parseList("AhKd"), try Card.parseList("AhQc")) == nil)
    #expect(table.equity([Card(index: 0), Card(index: 0)], try Card.parseList("QcJc")) == nil)
  }

  @Test func canonicalKeyIsInvariantUnderRelabelingAndSwap() {
    var rng = SeededRNG(seed: 28)
    for _ in 0..<50 {
      let (a, b) = preflopRandomPair(&rng)
      let base = PreflopEquityTable.canonicalKey(a, b)
      let swapped = PreflopEquityTable.canonicalKey(b, a)
      #expect(swapped.key == base.key)
      if CardSet(a).bits != CardSet(b).bits { #expect(swapped.flipped != base.flipped || base.key == swapped.key) }
      for perm in preflopAllPermutations() {
        let key = PreflopEquityTable.canonicalKey(preflopRelabel(a, perm), preflopRelabel(b, perm))
        #expect(key.key == base.key)
      }
    }
  }

  @Test func initRejectsBadMagicAndTruncatedData() throws {
    let good = PreflopEquityTable.makeFile(keys: [1, 2], equityQ: [100, 200], tieQ: [1, 2])
    let table = try PreflopEquityTable(data: good)
    #expect(table.entryCount == 2)
    var badMagic = good
    badMagic[0] = 0x58
    #expect(throws: PreflopEquityTable.LoadError.badMagic) { try PreflopEquityTable(data: badMagic) }
    #expect(throws: PreflopEquityTable.LoadError.truncated) { try PreflopEquityTable(data: good.dropLast(3)) }
    #expect(throws: PreflopEquityTable.LoadError.truncated) { try PreflopEquityTable(data: Data([1, 2, 3])) }
    var badVersion = good
    badVersion[4] = 9
    #expect(throws: PreflopEquityTable.LoadError.unsupportedVersion(9)) { try PreflopEquityTable(data: badVersion) }
    let unsorted = PreflopEquityTable.makeFile(keys: [5, 3], equityQ: [1, 2], tieQ: [0, 0])
    #expect(throws: PreflopEquityTable.LoadError.invalid) { try PreflopEquityTable(data: unsorted) }
  }
}
