import Testing

@testable import PokerCore

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }
private func fast(_ text: String) -> HandValue { HandEvaluator.evaluate(cards(text)) }

@Suite struct EvaluatorGoldenTests {
  @Test func categoryForEveryCategory() {
    let golden: [(String, HandCategory)] = [
      ("AsKsQsJsTs", .straightFlush),
      ("9h8h7h6h5h2c3d", .straightFlush),
      ("KcKdKhKs2c", .fourOfAKind),
      ("KcKdKhQsQc", .fullHouse),
      ("As9s7s4s2s", .flush),
      ("9c8d7h6s5c", .straight),
      ("QcQdQh9s2c", .threeOfAKind),
      ("KcKd9h9s2c", .twoPair),
      ("KcKd9h7s2c", .pair),
      ("AcKd9h7s2c", .highCard),
    ]
    for (text, category) in golden {
      #expect(fast(text).category == category, "\(text)")
      #expect(NaiveEvaluator.evaluate(cards(text)).category == category, "\(text)")
    }
  }

  @Test func extremesOfTheScale() {
    #expect(fast("AsKsQsJsTs").rawValue == 1)
    #expect(fast("7c5d4h3s2c").rawValue == 7462)
    #expect(fast("AsKsQsJsTs").strength == 7462)
    #expect(fast("7c5d4h3s2c").strength == 1)
  }

  @Test func wheelStraight() {
    let wheel = fast("Ac2d3h4s5c")
    #expect(wheel.category == .straight)
    #expect(wheel < fast("2c3d4h5s6c"))  // six-high beats the wheel
    #expect(wheel > fast("AcKdQhJs9c"))  // beats any non-straight ace-high
    #expect(wheel > fast("AcAdAhKsQc"))  // beats trips
    // The ace is not high in the wheel, and K-Q-J-T-A is not a wrap-around.
    #expect(fast("QcKdAh2s3c").category == .highCard)
  }

  @Test func steelWheel() {
    let steel = fast("Ah2h3h4h5h")
    #expect(steel.category == .straightFlush)
    #expect(steel < fast("2h3h4h5h6h"))
    #expect(steel > fast("KcKdKhKsAc"))  // beats quads
    #expect(steel < fast("AsKsQsJsTs"))
    // Seven cards: the wheel flush hides inside a pair and a higher non-flush straight.
    #expect(fast("Ah2h3h4h5h6c6d").rawValue == fast("Ah2h3h4h5h").rawValue)
  }

  @Test func kickerOrdering() {
    #expect(fast("AcAdKh7s2c") > fast("AcAdQh7s2c"))
    #expect(fast("AcAdKh7s2c") == fast("AhAsKd7c2d"))
    #expect(fast("AcAdKh7s3c") > fast("AcAdKh7s2c"))
    #expect(fast("KcKd9h9s3c") > fast("KcKd9h9s2c"))
    #expect(fast("KcKd9h9sAc") > fast("KcKd9h9sQc"))
    #expect(fast("KcKd8h8sAc") < fast("KcKd9h9s2c"))  // second pair beats the kicker
    #expect(fast("AcKdQhJs9c") > fast("AcKdQhJs8c"))
    #expect(fast("KcKdKh2s3c") > fast("QcQdQhAsKc"))
    #expect(fast("AcAdAh4s3c") > fast("AcAdAh2s3c"))
  }

  @Test func fullHouseOrdering() {
    #expect(fast("KcKdKh2s2c") > fast("QcQdQhAsAc"))  // trips rank dominates
    #expect(fast("KcKdKh3s3c") > fast("KcKdKh2s2h"))  // then the pair
    #expect(fast("3c3d3h2s2c") > fast("2c2d2hAsAh"))
    #expect(fast("AcAdAhKsKc") > fast("KcKdKhAsAh"))
    // Two sets of trips in seven cards: the higher trips lead, the lower trips supply the pair.
    #expect(fast("KcKdKh9s9c9d2c") == fast("KcKdKh9s9c"))
    #expect(fast("KcKdKhQsQc2d2c") == fast("KcKdKhQsQc"))  // pair of queens beats pair of twos
  }

  @Test func flushVersusStraightAndOthers() {
    #expect(fast("2s4s6s8sTs") > fast("AcKdQhJsTc"))  // flush beats the best straight
    #expect(fast("2s4s6s8sTs") < fast("KcKdKhQsQc"))  // full house beats flush
    #expect(fast("As9s7s4s2s") > fast("Ks9s7s4s2s"))
    // Seven cards holding both a flush and a higher straight: flush plays, straight flush if connected.
    #expect(fast("2s4s6s8sTsJhQd").category == .flush)
    #expect(fast("9s8s7s6s2s5h4h").category == .flush)
    #expect(fast("9s8s7s6s5s5h4h").category == .straightFlush)
    // Five suited cards from six cards of a suit: the best five suited cards play.
    #expect(fast("As9s7s4s2s3s") == fast("As9s7s4s3s"))
  }

  @Test func boardPlaysTies() {
    let board = cards("AsKsQsJsTs")
    let a = HandEvaluator.evaluate(hole: cards("2c3d"), board: board)
    let b = HandEvaluator.evaluate(hole: cards("9h8h"), board: board)
    #expect(a == b)
    #expect(a.rawValue == 1)
    // Board straight on the table: broadway plays against a lower pocket pair.
    let board2 = cards("9c8d7h6s5c")
    #expect(
      HandEvaluator.evaluate(hole: cards("2c2d"), board: board2)
        == HandEvaluator.evaluate(hole: cards("3c4d"), board: board2))
    #expect(
      HandEvaluator.evaluate(hole: cards("Tc2d"), board: board2)
        > HandEvaluator.evaluate(hole: cards("3c4d"), board: board2))
  }

  @Test func fiveSixAndSevenCardsAgree() {
    #expect(fast("AcAdKh7s5c") == fast("AcAdKh7s5c2d"))
    #expect(fast("AcAdKh7s5c") == fast("AcAdKh7s5c2d3h"))
    #expect(HandEvaluator.evaluate(CardSet(cards("AcAdKh7s2c"))) == fast("2cAcAd7sKh"))
  }

  @Test func categoryNames() {
    #expect(HandCategory.twoPair.name == "Two pair")
    #expect(HandCategory.twoPair.title == "Two Pair")
    #expect(HandCategory.threeOfAKind.title == "Three of a Kind")
    #expect(HandCategory.allCases.count == 9)
    #expect(HandCategory.straightFlush > HandCategory.fourOfAKind)
  }
}

@Suite struct EvaluatorClassesTests {
  @Test func exactly7462ClassesInCategoryBands() {
    let classes = HandClasses.shared
    #expect(classes.scores.count == 7462)
    #expect(Set(classes.scores).count == 7462)
    var counts: [HandCategory: Int] = [:]
    for i in 1...7462 { counts[HandValue(rawValue: UInt16(i)).category, default: 0] += 1 }
    #expect(counts[.straightFlush] == 10)
    #expect(counts[.fourOfAKind] == 156)
    #expect(counts[.fullHouse] == 156)
    #expect(counts[.flush] == 1277)
    #expect(counts[.straight] == 10)
    #expect(counts[.threeOfAKind] == 858)
    #expect(counts[.twoPair] == 858)
    #expect(counts[.pair] == 2860)
    #expect(counts[.highCard] == 1277)
    // The category implied by the rank agrees with the naive score's category.
    for i in 0..<7462 {
      #expect(Int(classes.scores[i] >> 20) == Int(HandValue(rawValue: UInt16(i + 1)).category.rawValue))
    }
  }

  @Test func tablesAreSmallAndFast() {
    #expect(HandEvaluator.tableByteCount < 400_000)
  }
}

@Suite struct EvaluatorAgreementTests {
  @Test func fastAgreesWithNaiveOn100kRandomSevenCardHands() {
    var rng = SeededRNG(seed: 20_261_104)
    var deck = Card.all
    for _ in 0..<100_000 {
      for i in 0..<7 {
        let j = Int.random(in: i..<52, using: &rng)
        deck.swapAt(i, j)
      }
      let hand = Array(deck[0..<7])
      let f = HandEvaluator.evaluate(hand)
      let n = NaiveEvaluator.evaluate(hand)
      if f != n {
        Issue.record("mismatch on \(Card.format(hand)): fast \(f.rawValue) naive \(n.rawValue)")
        return
      }
    }
  }

  @Test func fastAgreesWithNaiveOnRandomFiveAndSixCardHands() {
    var rng = SeededRNG(seed: 99)
    var deck = Card.all
    for size in [5, 6] {
      for _ in 0..<20_000 {
        for i in 0..<size { deck.swapAt(i, Int.random(in: i..<52, using: &rng)) }
        let hand = Array(deck[0..<size])
        #expect(HandEvaluator.evaluate(hand) == NaiveEvaluator.evaluate(hand), "\(Card.format(hand))")
      }
    }
  }

  @Test func rankOnlyHandsWithoutFlushesAndWithManyPairs() {
    // Stress paired boards: many pairs/trips/quads, which random deals rarely hit.
    var rng = SeededRNG(seed: 5)
    for _ in 0..<20_000 {
      let ranks = (0..<7).map { _ in Int.random(in: 0..<4, using: &rng) + Int.random(in: 0..<2, using: &rng) * 8 }
      var used = CardSet()
      var hand: [Card] = []
      for r in ranks {
        let suits = (0..<4).map { Card(index: UInt8(r * 4 + $0)) }.filter { !used.contains($0) }
        guard let c = suits.randomElement(using: &rng) else { continue }
        used.insert(c)
        hand.append(c)
      }
      guard hand.count >= 5 else { continue }
      #expect(HandEvaluator.evaluate(hand) == NaiveEvaluator.evaluate(hand), "\(Card.format(hand))")
    }
  }

  @Test func orderingMatchesNaiveScoresAcrossHands() {
    var rng = SeededRNG(seed: 3)
    var deck = Card.all
    for _ in 0..<5_000 {
      for i in 0..<14 { deck.swapAt(i, Int.random(in: i..<52, using: &rng)) }
      let a = Array(deck[0..<7])
      let b = Array(deck[7..<14])
      let sa = NaiveEvaluator.bestScore(a)
      let sb = NaiveEvaluator.bestScore(b)
      let fa = HandEvaluator.evaluate(a)
      let fb = HandEvaluator.evaluate(b)
      #expect((sa < sb) == (fa < fb) && (sa == sb) == (fa == fb))
    }
  }
}

@Suite struct EvaluatorBestFiveTests {
  private func check(_ text: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let hand = cards(text)
    #expect(Card.format(HandEvaluator.bestFive(hand)) == expected, sourceLocation: sourceLocation)
    #expect(Card.format(NaiveEvaluator.bestFive(hand)) == expected, sourceLocation: sourceLocation)
  }

  @Test func pairAndKickers() {
    check("AcAd9h7s2c3d4h", "AcAd9h7s4h")  // pair of aces, then 9, 7, 4
  }

  @Test func twoPairPicksTopTwoAndBestKicker() {
    check("KcKd9h9s5c5dAh", "KcKd9h9sAh")
  }

  @Test func tripsAndQuads() {
    check("QcQdQhAs2c7d9h", "QcQdQhAs9h")
    check("7c7d7h7s2cAdKh", "7c7d7h7sAd")
  }

  @Test func fullHouseFromTwoTrips() {
    check("KcKdKh9s9c9d2c", "KcKdKh9c9s")
  }

  @Test func straightsHighToLowAndWheelAceLast() {
    check("9c8d7h6s5c2d2h", "9c8d7h6s5c")
    check("Ac2d3h4s5c9d9h", "5c4s3h2dAc")
    check("Ac2d3h4s5c6d9h", "6d5c4s3h2d")  // six-high straight beats the wheel
  }

  @Test func flushUsesBestFiveSuitedCards() {
    check("As9s7s4s2s3s5h", "As9s7s4s3s")
  }

  @Test func straightFlushNotThePlainStraight() {
    check("9s8s7s6s5s5h4h", "9s8s7s6s5s")
    check("Ah2h3h4h5h6c6d", "5h4h3h2hAh")
  }

  @Test func boardPlays() {
    check("AsKsQsJsTs2c3d", "AsKsQsJsTs")
  }

  @Test func fiveCardsReturnsAllFive() {
    check("2c9d4h7sKc", "Kc9d7s4h2c")
  }

  @Test func highCardChoosesTopFive() {
    check("2c9d4h7sKcJdAh", "AhKcJd9d7s")
  }
}

@Suite struct EvaluatorDescriptionTests {
  private func text(_ s: String) -> String { HandDescription.describe(cards: cards(s)) }

  @Test func descriptions() {
    #expect(text("KcKd9h9s2c3d4h") == "Two pair, Kings and Nines")
    #expect(text("AcKd9h7s2c") == "Ace high")
    #expect(text("AcAd9h7s2c") == "Pair of Aces")
    #expect(text("6c6d9h7s2c") == "Pair of Sixes")
    #expect(text("QcQdQh7s2c") == "Three of a kind, Queens")
    #expect(text("9c8d7h6s5c") == "Straight, Nine high")
    #expect(text("Ac2d3h4s5c") == "Straight, Five high")
    #expect(text("As9s7s4s2s") == "Flush, Ace high")
    #expect(text("KcKdKhQsQc") == "Full house, Kings full of Queens")
    #expect(text("3c3d3h2s2c") == "Full house, Threes full of Twos")
    #expect(text("7c7d7h7s2c") == "Four of a kind, Sevens")
    #expect(text("9h8h7h6h5h") == "Straight flush, Nine high")
    #expect(text("AsKsQsJsTs") == "Royal flush")
    #expect(text("Ah2h3h4h5h") == "Straight flush, Five high")
    #expect(fast("KcKd9h9s2c").description == "Two pair, Kings and Nines")
  }

  @Test func everyClassHasAUniqueNonEmptyDescriptionPerCategoryTiebreak() {
    var seen = Set<String>()
    var duplicates = 0
    for i in 1...7462 {
      let d = HandDescription.describe(HandValue(rawValue: UInt16(i)))
      #expect(!d.isEmpty)
      // Flush and high-card texts only name the top card, so they repeat by design.
      if !seen.insert(d).inserted { duplicates += 1 }
    }
    #expect(seen.count > 300)
    #expect(duplicates > 0)
  }
}
