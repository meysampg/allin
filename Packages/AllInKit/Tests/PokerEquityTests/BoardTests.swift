import PokerCore
import Testing

@testable import PokerEquity

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

@Suite struct BoardTextureTests {
  @Test func dryRainbowKing() {
    let t = BoardAnalyzer.texture(cards("Kd7s2c"))
    #expect(t.cardCount == 3)
    #expect(t.isRainbow && !t.isTwoTone && !t.isMonotone)
    #expect(!t.isPaired && !t.hasTrips)
    #expect(!t.flushPossible && !t.flushDrawPossible && !t.straightPossible)
    #expect(t.connectedness == 1)
    #expect(t.highRank == .king)
    #expect(t.wetness == 0)
  }

  @Test func connectedTwoTone() {
    let t = BoardAnalyzer.texture(cards("JhTh9c"))
    #expect(t.isTwoTone && !t.isRainbow)
    #expect(t.flushDrawPossible && !t.flushPossible)
    #expect(t.straightPossible)
    #expect(t.connectedness == 3)
    #expect(t.highRank == .jack)
    #expect(abs(t.wetness - 0.65) < 1e-9)
  }

  @Test func trips() {
    let t = BoardAnalyzer.texture(cards("8s8d8h"))
    #expect(t.isPaired && t.hasTrips)
    #expect(t.isRainbow)
    #expect(t.connectedness == 1)
    #expect(t.wetness == 0)
  }

  @Test func monotoneBroadway() {
    let t = BoardAnalyzer.texture(cards("AhKhQh"))
    #expect(t.isMonotone && t.flushPossible)
    #expect(!t.flushDrawPossible)
    #expect(t.straightPossible && t.connectedness == 3)
    #expect(abs(t.wetness - 0.8) < 1e-9)
  }

  @Test func wheelCountsAceLow() {
    let t = BoardAnalyzer.texture(cards("Ah2d3c"))
    #expect(t.connectedness == 3)
    #expect(t.straightPossible)
    let turn = BoardAnalyzer.texture(cards("Ah2d3c5s"))
    #expect(turn.connectedness == 4)
  }

  @Test func riverHasNoFlushDrawPossible() {
    let t = BoardAnalyzer.texture(cards("Ah2h3c5sKd"))
    #expect(!t.flushDrawPossible)
    #expect(t.cardCount == 5)
  }

  @Test func wetnessOrdering() {
    let dry = BoardAnalyzer.texture(cards("Kd7s2c")).wetness
    let wet = BoardAnalyzer.texture(cards("JhTh9c")).wetness
    let paired = BoardAnalyzer.texture(cards("KdKs2c")).wetness
    #expect(dry < wet)
    #expect(paired <= dry)
    #expect((0...1).contains(wet))
  }
}

@Suite struct BoardNutsTests {
  @Test func royalFlushNuts() {
    let nuts = BoardAnalyzer.nuts(board: cards("AhKhQh2c3d"))
    #expect(nuts.description == "Royal flush")
    #expect(nuts.combos == [try! Combo("JhTh")])
  }

  @Test func pairedBoardQuads() {
    let nuts = BoardAnalyzer.nuts(board: cards("9s9d9h2c3d"))
    #expect(nuts.value.category == .fourOfAKind)
    #expect(nuts.combos.count == 4)  // 9c with each ace
    #expect(nuts.description == "Four of a kind, Nines")
  }

  @Test func deadCardsAreExcluded() {
    let board = cards("AhKhQh2c3d")
    let nuts = BoardAnalyzer.nuts(board: board, dead: CardSet(cards("Jh")))
    #expect(nuts.value.category != .straightFlush)
    #expect(nuts.combos.allSatisfy { !$0.mask.contains(try! Card("Jh")) })
  }

  @Test func flopNuts() {
    let nuts = BoardAnalyzer.nuts(board: cards("Kd7s2c"))
    #expect(nuts.value.category == .fourOfAKind || nuts.value.category == .threeOfAKind)
    #expect(nuts.description == "Three of a kind, Kings")
  }
}

@Suite struct BeatingHandsTests {
  // Hero KhQd on Kc 9d 6s 2h 3h: straights 4-5 (16), sets (KK 1, 99 3, 66 3, 22 3, 33 3 = 13),
  // two pair (78), K with an ace (8), pocket aces (6).
  @Test func topPairRiver() {
    let groups = BoardAnalyzer.beatingHands(hole: cards("KhQd"), board: cards("Kc9d6s2h3h"))
    let all = groups.flatMap(\.combos)
    #expect(all.count == 121)
    #expect(Set(all).count == 121)
    #expect(groups[0].value.category == .straight)
    #expect(groups[0].combos.count == 16)
    #expect(groups[0].description == "Straight, Six high")
    for (a, b) in zip(groups, groups.dropFirst()) { #expect(a.value > b.value) }
    func count(_ c: HandCategory) -> Int { groups.filter { $0.value.category == c }.flatMap(\.combos).count }
    #expect(count(.threeOfAKind) == 13)
    #expect(count(.twoPair) == 78)
    #expect(count(.pair) == 14)
    // No combo contains a hero or board card.
    let blocked = CardSet(cards("KhQdKc9d6s2h3h"))
    #expect(all.allSatisfy { $0.mask.isDisjoint(with: blocked) })
  }

  @Test func nutsBeatenByNothing() {
    let board = cards("AhKhQh2c3d")
    #expect(BoardAnalyzer.beatingHands(hole: cards("JhTh"), board: board).isEmpty)
  }
}

@Suite struct BoardOutsTests {
  @Test func openEndedHasEightOuts() {
    let outs = BoardAnalyzer.outs(hole: cards("9h8c"), board: cards("Td7s2c"))
    #expect(outs.count == 8)
    #expect(Set(outs.map(\.rank)) == [.six, .jack])
  }

  @Test func flushDrawWithOvercards() {
    let outs = BoardAnalyzer.outs(hole: cards("AhKh"), board: cards("7h4h2c"))
    #expect(outs.count == 9)
    #expect(outs.allSatisfy { $0.suit == .hearts })
  }

  @Test func riverHasNoOuts() {
    #expect(BoardAnalyzer.outs(hole: cards("AhKh"), board: cards("7h4h2c9sTd")).isEmpty)
  }

  @Test func gutshotHasFourOuts() {
    #expect(BoardAnalyzer.outs(hole: cards("9h8c"), board: cards("Js7d2c")).count == 4)
  }
}

@Suite struct BoardStrengthTableTests {
  @Test func valuesAndDeadCombos() {
    let board = cards("Kd7s2c")
    let table = BoardStrengthTable(board: board)
    #expect(table.board == board)
    #expect(table.value(of: try! Combo("KdAh")) == nil)
    #expect(table.value(of: try! Combo("AhAd")) == HandEvaluator.evaluate(cards("AhAdKd7s2c")))
    #expect(table.strength(of: try! Combo("KdAh")) == 0)
  }

  @Test func strengthAgreesWithEvaluation() {
    let board = cards("Kd7s2c9h3d")
    let table = BoardStrengthTable(board: board)
    var rng = SeededRNG(seed: 42)
    let live = Combo.all.filter { table.value(of: $0) != nil }
    for _ in 0..<300 {
      let a = live[Int(rng.next() % UInt64(live.count))]
      let b = live[Int(rng.next() % UInt64(live.count))]
      let va = table.value(of: a)!
      let vb = table.value(of: b)!
      let sa = table.strength(of: a)
      let sb = table.strength(of: b)
      if va > vb { #expect(sa > sb) } else if va < vb { #expect(sa < sb) } else { #expect(sa == sb) }
    }
    let best = live.map { table.strength(of: $0) }.max()!
    let worst = live.map { table.strength(of: $0) }.min()!
    #expect(best <= 1 && worst >= 0)
    #expect(best > 0.99)
  }

  @Test func percentilesWithinRange() {
    let table = BoardStrengthTable(board: cards("Kd7s2c"))
    let range = try! HandRange(parsing: "AA, KK, 72s, 32o")
    let p = table.percentiles(in: range)
    #expect(p.count == 1326)
    #expect(p[try! Combo("KhKs").index] >= 0)
    #expect(p[try! Combo("KdKs").index] == -1)  // hits the board
    #expect(p[try! Combo("QhQs").index] == -1)  // zero weight
    // Quads-free flop: KK set is best, then AA, then the weaker hands.
    let kk = p[try! Combo("KhKs").index]
    let aa = p[try! Combo("AhAs").index]
    let low = p[try! Combo("3h2s").index]
    #expect(kk < aa && aa < low)
    #expect(kk >= 0 && low <= 1)
  }

  @Test func drawOutsFlags() {
    let table = BoardStrengthTable(board: cards("7h4h2c"))
    #expect(table.drawOuts(of: try! Combo("AhKh")) == 9)
    #expect(table.drawOuts(of: try! Combo("AsKs")) == 0)
    let straight = BoardStrengthTable(board: cards("Td7s2c"))
    #expect(straight.drawOuts(of: try! Combo("9h8c")) == 8)
    #expect(straight.drawOuts(of: try! Combo("Jh8c")) == 4)
    let river = BoardStrengthTable(board: cards("7h4h2c9sTd"))
    #expect(river.drawOuts(of: try! Combo("AhKh")) == 0)
  }

  @Test func buildSpeedIsReasonable() {
    // Debug-build sanity only: a few tables must build quickly. Release target is about 60 microseconds.
    let board = cards("Kd7s2c9h3d")
    for _ in 0..<20 { _ = BoardStrengthTable(board: board) }
  }
}
