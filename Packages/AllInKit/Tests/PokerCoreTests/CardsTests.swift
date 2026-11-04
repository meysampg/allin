import Testing

@testable import PokerCore

@Suite struct CardsTests {
  @Test func encodingRoundTripsForAll52() throws {
    var seen = Set<UInt8>()
    for r in Rank.allCases {
      for s in Suit.allCases {
        let c = Card(rank: r, suit: s)
        #expect(c.index == r.rawValue * 4 + s.rawValue)
        #expect(c.rank == r && c.suit == s)
        #expect(Card(index: c.index) == c)
        #expect(try Card(c.description) == c)
        seen.insert(c.index)
      }
    }
    #expect(seen.count == 52 && Card.all.count == 52)
  }

  @Test func parseAndFormat() throws {
    #expect(try Card("As") == Card(rank: .ace, suit: .spades))
    #expect(try Card("td") == Card(rank: .ten, suit: .diamonds))
    #expect(try Card("2C").description == "2c")
    let list = try Card.parseList("AsKh Td")
    #expect(Card.format(list) == "AsKhTd")
    #expect(try Card.parseList("").isEmpty)
  }

  @Test func parseErrors() {
    #expect(throws: CardParseError.invalidLength("A")) { try Card("A") }
    #expect(throws: CardParseError.invalidLength("Asx")) { try Card("Asx") }
    #expect(throws: CardParseError.invalidRank("1")) { try Card("1s") }
    #expect(throws: CardParseError.invalidSuit("x")) { try Card("Ax") }
    #expect(throws: CardParseError.invalidLength("AsK")) { try Card.parseList("AsK") }
    #expect(throws: CardParseError.duplicateCard("As")) { try Card.parseList("AsKhAs") }
    #expect(Card(validating: 52) == nil && Card(validating: -1) == nil)
  }

  @Test func cardSetOperations() throws {
    var s = CardSet()
    #expect(s.isEmpty)
    let a = try Card("As"), k = try Card("Kh")
    let r1 = s.insert(a)
    #expect(r1)
    let r2 = s.insert(a)
    #expect(!r2)
    let r3 = s.insert(k)
    #expect(r3)
    #expect(s.count == 2 && s.contains(a) && s.contains(k))
    let r4 = s.remove(a)
    #expect(r4)
    let r5 = s.remove(a)
    #expect(!r5)
    #expect(!s.contains(a))

    let x = CardSet(try Card.parseList("AsKhQd"))
    let y = CardSet(try Card.parseList("KhQd2c"))
    #expect(x.union(y).count == 4)
    #expect(x.intersection(y) == CardSet(try Card.parseList("KhQd")))
    #expect(x.subtracting(y) == CardSet([a]))
    #expect(!x.isDisjoint(with: y))
    #expect(x.isSubset(of: x.union(y)))
    #expect(CardSet.full.count == 52)
    #expect(x.complement.count == 49)
    #expect(x.union(x.complement) == .full)
    #expect(x.cards(of: .spades) == CardSet([a]))
    #expect(Array(x).map(\.index) == x.map(\.index).sorted())
    #expect(CardSet(bits: ~0).count == 52)
  }

  @Test func dealNoDuplicates() throws {
    var rng = SeededRNG(seed: 1)
    var deck = Deck()
    deck.shuffle(using: &rng)
    var set = CardSet()
    while let c = deck.deal() {
      let isNew = set.insert(c)
      #expect(isNew)
    }
    #expect(set == .full && deck.isEmpty)
    #expect(deck.deal() == nil)
  }

  @Test func dealMany() {
    var deck = Deck()
    #expect(deck.deal(5)?.count == 5)
    #expect(deck.remaining == 47)
    #expect(deck.deal(48) == nil)
    #expect(deck.remaining == 47)
  }

  @Test func removeKnownCards() throws {
    let known = CardSet(try Card.parseList("AsKh"))
    var deck = Deck(removing: known)
    #expect(deck.remaining == 50)
    #expect(deck.undealt.allSatisfy { !known.contains($0) })
    var d2 = Deck()
    _ = d2.deal(2)
    d2.remove(CardSet(try Card.parseList("As2c")))
    #expect(d2.remaining <= 50)
    #expect(!d2.undealt.contains(try Card("As")))
    _ = deck.deal()
  }

  @Test func shuffleDeterministicPerSeed() {
    var a = Deck(), b = Deck(), c = Deck()
    var ra = SeededRNG(seed: 42), rb = SeededRNG(seed: 42), rc = SeededRNG(seed: 43)
    a.shuffle(using: &ra)
    b.shuffle(using: &rb)
    c.shuffle(using: &rc)
    #expect(a == b)
    #expect(a.cards != c.cards)
    #expect(a.cards != Deck().cards)
    #expect(Set(a.cards).count == 52)
  }

  @Test func rngReproducibleWithKnownValues() {
    var r = SeededRNG(seed: 0)
    let first = (0..<4).map { _ in r.next() }
    var r2 = SeededRNG(seed: 0)
    #expect((0..<4).map { _ in r2.next() } == first)
    #expect(first == SeededRNGTests.expectedSeed0)
    var other = SeededRNG(seed: 1)
    #expect(other.next() != first[0])
  }
}

enum SeededRNGTests {
  // Computed with an independent Python implementation of SplitMix64-seeded xoshiro256**.
  static let expectedSeed0: [UInt64] = [
    0x99EC_5F36_CB75_F2B4, 0xBF6E_1F78_4956_452A, 0x1A5F_849D_4933_E6E0, 0x6AA5_94F1_262D_2D2C,
  ]
}
