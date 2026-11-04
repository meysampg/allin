import PokerCore
import Testing

@testable import PokerEquity

private func cards(_ text: String) -> [Card] { try! Card.parseList(text) }

private struct MadeCase: Sendable, CustomTestStringConvertible {
  let hole: String
  let board: String
  let made: MadeHandClass
  let bucket: StrengthBucket
  var testDescription: String { "\(hole) on \(board): \(made)" }
}

private let madeCases: [MadeCase] = [
  MadeCase(hole: "Ah9c", board: "Kd7s2c", made: .noPair, bucket: .air),
  MadeCase(hole: "3h3c", board: "Kd9s7c", made: .underPair, bucket: .weakMade),
  MadeCase(hole: "6h2c", board: "Kd9s6d", made: .bottomPair, bucket: .weakMade),
  MadeCase(hole: "9h2c", board: "Kd9s6d", made: .middlePair, bucket: .weakMade),
  MadeCase(hole: "Kh3c", board: "Kd9s6d", made: .topPairWeakKicker, bucket: .medium),
  MadeCase(hole: "KhQc", board: "Kd9s6d", made: .topPairGoodKicker, bucket: .medium),
  MadeCase(hole: "QhQc", board: "9d7s2c", made: .overpair, bucket: .strong),
  MadeCase(hole: "Kh9c", board: "Kd9s6d", made: .twoPair, bucket: .strong),
  MadeCase(hole: "Kh3c", board: "KdKs6d", made: .trips, bucket: .strong),
  MadeCase(hole: "9h9c", board: "Kd9s6d", made: .set, bucket: .strong),
  MadeCase(hole: "Th9c", board: "8d7s6c", made: .straight, bucket: .nutted),
  MadeCase(hole: "9c5s", board: "8d7d6d", made: .straight, bucket: .strong),
  MadeCase(hole: "Ah5h", board: "Kh9h2h", made: .flush, bucket: .nutted),
  MadeCase(hole: "9h9c", board: "Kd9sKc", made: .fullHouse, bucket: .nutted),
  MadeCase(hole: "9h9c", board: "9d9sKc", made: .quadsPlus, bucket: .nutted),
  // The board plays: hero's 3 is not even a kicker.
  MadeCase(hole: "2c3d", board: "AsAdKcKh5s", made: .noPair, bucket: .air),
]

@Suite struct HandFeaturesMadeTests {
  @Test(arguments: madeCases)
  fileprivate func madeAndBucket(_ c: MadeCase) {
    let f = HandFeatures(hole: cards(c.hole), board: cards(c.board))
    #expect(f.made == c.made)
    #expect(f.bucket == c.bucket)
    #expect(f.value == HandEvaluator.evaluate(hole: cards(c.hole), board: cards(c.board)))
  }

  @Test func everyMadeClassIsCovered() {
    #expect(Set(madeCases.map(\.made)) == Set(MadeHandClass.allCases))
  }

  @Test func madeClassOrdering() {
    #expect(MadeHandClass.noPair < .overpair)
    #expect(MadeHandClass.set < .straight)
    #expect(MadeHandClass.fullHouse < .quadsPlus)
  }

  @Test func overcards() {
    #expect(HandFeatures(hole: cards("AhKc"), board: cards("Qd7s2c")).overcards == 2)
    #expect(HandFeatures(hole: cards("AhJc"), board: cards("Kd7s2c")).overcards == 1)
    #expect(HandFeatures(hole: cards("3hJc"), board: cards("Kd7s2c")).overcards == 0)
  }

  @Test func textureIsAttached() {
    let f = HandFeatures(hole: cards("AhKc"), board: cards("JhTh9c"))
    #expect(f.texture == BoardAnalyzer.texture(cards("JhTh9c")))
  }
}

@Suite struct HandFeaturesDrawTests {
  @Test func openEnded() {
    let f = HandFeatures(hole: cards("9h8c"), board: cards("Td7s2c"))
    #expect(f.draws.openEnded && !f.draws.gutshot && !f.draws.flushDraw)
    #expect(f.draws.outs == 8)
    #expect(f.bucket == .draw)
    #expect(!f.draws.isCombo)
  }

  @Test func gutshot() {
    let f = HandFeatures(hole: cards("9h8c"), board: cards("Js7d2c"))
    #expect(f.draws.gutshot && !f.draws.openEnded)
    #expect(f.draws.outs == 4)
    #expect(f.bucket == .air)
  }

  @Test func doubleGutterCountsAsOpenEnded() {
    let f = HandFeatures(hole: cards("9h3c"), board: cards("7d6s5c"))
    #expect(f.draws.openEnded && !f.draws.gutshot)
    #expect(f.draws.outs == 8)
  }

  @Test func nutFlushDraw() {
    let f = HandFeatures(hole: cards("Ah5h"), board: cards("Kh9h2c"))
    #expect(f.draws.flushDraw && f.draws.nutFlushDraw)
    #expect(f.draws.outs == 9)
    #expect(f.bucket == .draw)
  }

  @Test func weakFlushDraw() {
    let f = HandFeatures(hole: cards("Qh5h"), board: cards("Kh9h2c"))
    #expect(f.draws.flushDraw && !f.draws.nutFlushDraw)
  }

  @Test func nutFlushDrawWhenAceIsOnBoard() {
    let f = HandFeatures(hole: cards("Kh5h"), board: cards("Ah9h2c"))
    #expect(f.draws.nutFlushDraw)
  }

  @Test func comboDraw() {
    let f = HandFeatures(hole: cards("9h8h"), board: cards("Th7h2c"))
    #expect(f.draws.flushDraw && f.draws.openEnded && f.draws.isCombo)
    #expect(f.draws.outs == 15)
  }

  @Test func backdoorFlush() {
    let f = HandFeatures(hole: cards("Ah5h"), board: cards("Kh9c2d"))
    #expect(f.draws.backdoorFlush && !f.draws.flushDraw)
    #expect(f.draws.outs == 0)
  }

  @Test func backdoorStraight() {
    let f = HandFeatures(hole: cards("Th9c"), board: cards("7d2sKc"))
    #expect(f.draws.backdoorStraight && !f.draws.openEnded && !f.draws.gutshot)
    #expect(!f.draws.backdoorFlush)
  }

  @Test func noBackdoorOnTheTurnOrRiver() {
    let turn = HandFeatures(hole: cards("Th9c"), board: cards("7d2sKcQh"))
    #expect(!turn.draws.backdoorStraight)
    let river = HandFeatures(hole: cards("Ah5h"), board: cards("Kh9c2d8h4s"))
    #expect(river.draws == DrawInfo())
  }

  @Test func flushDrawPlusOvercardsHasNineFlushOuts() {
    let f = HandFeatures(hole: cards("AhKh"), board: cards("7h4h2c"))
    #expect(f.draws.outs == 9)
    #expect(f.overcards == 2)
  }

  @Test func madeStraightHasNoStraightDraw() {
    let f = HandFeatures(hole: cards("Th9c"), board: cards("8d7s6c"))
    #expect(!f.draws.openEnded && !f.draws.gutshot)
  }
}
