import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct PredicateTests {
  static func cards(_ text: String) -> [Card] { GenerationTestSupport.cards(text) }

  // MARK: Board tags

  /// (tag, a board that has it, a board that does not).
  static let tagGoldens: [(TextureTag, String, String)] = [
    (.paired, "Ks Kd 7c", "Ks 8d 2c"),
    (.unpaired, "Ks 8d 2c", "Ks Kd 7c"),
    (.trips, "7s 7d 7c", "7s 7d 2c"),
    (.monotone, "Ah 8h 3h", "Ah 8h 3c"),
    (.twoTone, "Ah 8h 3c", "Ah 8d 3c"),
    (.rainbow, "Ah 8d 3c", "Ah 8h 3c"),
    (.flushPossible, "Ah 8h 3h", "Ah 8h 3c"),
    (.flushDrawPossible, "Ah 8h 3c", "Ah 8d 3c"),
    (.straightPossible, "9s 8d 7c", "Ks 8d 2c"),
    (.connected, "9s 8d 7c", "Ks 8d 2c"),
    (.dry, "Ks 7d 2c", "9h 8h 7c"),
    (.wet, "9h 8h 7c", "Ks 7d 2c"),
  ]

  @Test(arguments: tagGoldens.map(\.0))
  func textureTag(tag: TextureTag) {
    let (_, yes, no) = Self.tagGoldens.first { $0.0 == tag }!
    let positive = BoardPredicate(street: .flop, require: [tag])
    #expect(positive.matches(Self.cards(yes)), "\(tag) should match \(yes)")
    #expect(!positive.matches(Self.cards(no)), "\(tag) should not match \(no)")
    let negative = BoardPredicate(street: .flop, exclude: [tag])
    #expect(!negative.matches(Self.cards(yes)))
    #expect(negative.matches(Self.cards(no)))
  }

  @Test func everyTagHasAGolden() {
    #expect(Set(Self.tagGoldens.map(\.0)) == Set(TextureTag.allCases))
  }

  @Test func middleWetnessIsNeitherDryNorWet() {
    let board = Self.cards("Ah 8h 3c")
    #expect(!BoardPredicate(street: .flop, require: [.dry]).matches(board))
    #expect(!BoardPredicate(street: .flop, require: [.wet]).matches(board))
  }

  @Test func boardStreetAndHighCard() {
    let flop = Self.cards("Ks 7d 2c")
    #expect(BoardPredicate(street: .flop, highCard: [.king, .ace]).matches(flop))
    #expect(!BoardPredicate(street: .flop, highCard: [.ace]).matches(flop))
    #expect(!BoardPredicate(street: .turn).matches(flop))
    #expect(BoardPredicate(street: .turn).matches(Self.cards("Ks 7d 2c 9h")))
    #expect(BoardPredicate(street: .river).matches(Self.cards("Ks 7d 2c 9h 4s")))
    #expect(BoardPredicate(street: .preflop).matches([]))
    #expect(!BoardPredicate(street: .preflop, require: [.dry]).matches([]))
  }

  // MARK: Made hands

  /// (name, board, hole) goldens: the hand is exactly this made-hand name on this board.
  static let madeGoldens: [(MadeHandName, String, String)] = [
    (.noPair, "Ks 7d 5c", "Qh Jh"),
    (.underPair, "Ks 7d 5c", "3h 3d"),
    (.bottomPair, "Ks 7d 5c", "5h Jh"),
    (.middlePair, "Ks 7d 5c", "7h Jh"),
    (.topPairGoodKicker, "Ks 7d 5c", "Kh Jh"),
    (.topPairWeakKicker, "Ks 7d 5c", "Kh 3h"),
    (.overpair, "Ks 7d 5c", "Ah Ad"),
    (.twoPair, "Ks 7d 5c", "Kh 7h"),
    (.set, "Ks 7d 5c", "Kh Kd"),
    (.trips, "Ks Kd 5c", "Kh Jh"),
    (.fullHouse, "Ks Kd 5c", "Kh 5h"),
    (.quads, "Ks Kd 5c", "Kh Kc"),
    (.straight, "9s 8d 7c 2h 3d", "Th Jh"),
    (.flush, "Ah 8h 3h 2c 9d", "Kh 5h"),
  ]

  @Test(arguments: madeGoldens.map(\.0))
  func madeHand(name: MadeHandName) {
    let (_, boardText, holeText) = Self.madeGoldens.first { $0.0 == name }!
    let board = Self.cards(boardText)
    let hole = Self.cards(holeText)
    #expect(HandPredicate(madeHand: [name]).matches(hole: hole, board: board), "\(name) \(holeText) on \(boardText)")
    let others = MadeHandName.allCases.filter { $0 != name && !$0.classes.contains(where: name.classes.contains) }
    #expect(!HandPredicate(madeHand: others).matches(hole: hole, board: board))
  }

  @Test func everyMadeNameHasAGolden() {
    #expect(Set(Self.madeGoldens.map(\.0)) == Set(MadeHandName.allCases.filter { $0 != .topPair }))
  }

  @Test func topPairCoversBothKickers() {
    let board = Self.cards("Ks 7d 5c")
    let predicate = HandPredicate(madeHand: [.topPair])
    #expect(predicate.matches(hole: Self.cards("Kh Jh"), board: board))
    #expect(predicate.matches(hole: Self.cards("Kh 3h"), board: board))
    #expect(!predicate.matches(hole: Self.cards("7h Jh"), board: board))
  }

  // MARK: Buckets, draws, outs, categories

  @Test func buckets() {
    let board = Self.cards("Ks 7d 5c")
    #expect(HandPredicate(bucket: [.air]).matches(hole: Self.cards("Qh Jh"), board: board))
    #expect(HandPredicate(bucket: [.strong]).matches(hole: Self.cards("Ah Ad"), board: board))
    #expect(HandPredicate(bucket: [.medium]).matches(hole: Self.cards("Kh Jh"), board: board))
    #expect(HandPredicate(bucket: [.weakMade]).matches(hole: Self.cards("5h Jh"), board: board))
    #expect(HandPredicate(bucket: [.draw]).matches(hole: Self.cards("6h 8h"), board: board))
    #expect(!HandPredicate(bucket: [.air, .strong]).matches(hole: Self.cards("Kh Jh"), board: board))
    #expect(HandPredicate(bucket: [.nutted]).matches(hole: Self.cards("Ah Kh"), board: Self.cards("Qh Jh Th 2c 3d")))
  }

  /// (draw name, board, hole).
  static let drawGoldens: [(DrawName, String, String)] = [
    (.flushDraw, "Ah 8h 3c", "Qh 2h"),
    (.nutFlushDraw, "Ah 8h 3c", "Kh 2h"),
    (.openEnded, "Ks 7d 5c", "6h 8h"),
    (.gutshot, "Ks 7d 5c", "8h 4h"),
    (.combo, "9h 8h 2c", "7h 6h"),
    (.backdoorFlush, "Ah 8h 3c", "Kh Qd"),
    (.anyDraw, "Ks 7d 5c", "6h 8h"),
    (.none, "Ks 7d 5c", "Qh Jh"),
  ]

  @Test(arguments: drawGoldens.map(\.0))
  func draw(name: DrawName) {
    let (_, boardText, holeText) = Self.drawGoldens.first { $0.0 == name }!
    #expect(
      HandPredicate(draws: [name]).matches(hole: Self.cards(holeText), board: Self.cards(boardText)),
      "\(name) \(holeText) on \(boardText)")
  }

  @Test func drawsNegativeAndRiver() {
    let flop = Self.cards("Ks 7d 5c")
    #expect(!HandPredicate(draws: [.flushDraw]).matches(hole: Self.cards("6h 8h"), board: flop))
    #expect(!HandPredicate(draws: [.none]).matches(hole: Self.cards("6h 8h"), board: flop))
    #expect(!HandPredicate(draws: [.anyDraw]).matches(hole: Self.cards("Qh Jh"), board: flop))
    // There are no draws on the river.
    #expect(HandPredicate(draws: [.none]).matches(hole: Self.cards("6h 8h"), board: Self.cards("Ks 7d 5c 2h 9s")))
  }

  @Test func outs() {
    let board = Self.cards("Ks 7d 5c")
    let hole = Self.cards("6h 8h")
    let count = HandFeatures(hole: hole, board: board).draws.outs
    #expect(count >= 8)
    #expect(HandPredicate(outs: IntRangeSpec(lo: count, hi: count)).matches(hole: hole, board: board))
    #expect(!HandPredicate(outs: IntRangeSpec(lo: 0, hi: count - 1)).matches(hole: hole, board: board))
  }

  @Test func categories() {
    let board = Self.cards("Ks 7d 5c 2h 9s")
    #expect(HandPredicate(categories: [.pair]).matches(hole: Self.cards("Kh Jh"), board: board))
    #expect(HandPredicate(categories: [.twoPair]).matches(hole: Self.cards("Kh 7h"), board: board))
    #expect(HandPredicate(categories: [.trips]).matches(hole: Self.cards("Kh Kd"), board: board))
    #expect(HandPredicate(categories: [.highCard]).matches(hole: Self.cards("Qh Jh"), board: board))
    #expect(!HandPredicate(categories: [.pair, .flush]).matches(hole: Self.cards("Qh Jh"), board: board))
    #expect(HandPredicate(categories: [.flush]).matches(hole: Self.cards("Ah 3h"), board: Self.cards("Kh 7h 5c 2h 9s")))
    #expect(
      HandPredicate(categories: [.straightFlush]).matches(
        hole: Self.cards("9h 8h"), board: Self.cards("7h 6h 5h 2c Ad")))
    #expect(HandPredicate(categories: [.quads]).matches(hole: Self.cards("Kh Kd"), board: Self.cards("Ks Kc 5c 2h 9s")))
    #expect(
      HandPredicate(categories: [.fullHouse]).matches(hole: Self.cards("Kh Kd"), board: Self.cards("Ks 5c 5d 2h 9s")))
    #expect(
      HandPredicate(categories: [.straight]).matches(hole: Self.cards("Th Jh"), board: Self.cards("9s 8d 7c 2h 3d")))
  }

  // MARK: Hole-only keys

  @Test func rangePocketPairSuited() throws {
    let aces = HandPredicate(range: try RangeSpec(text: "AA"))
    #expect(aces.matches(hole: Self.cards("Ah Ad"), board: []))
    #expect(!aces.matches(hole: Self.cards("Kh Kd"), board: []))
    #expect(aces.matches(hole: Self.cards("Ah Ad"), board: Self.cards("Ks 7d 5c")))
    #expect(HandPredicate(pocketPair: true).matches(hole: Self.cards("3h 3d"), board: []))
    #expect(!HandPredicate(pocketPair: true).matches(hole: Self.cards("3h 4d"), board: []))
    #expect(HandPredicate(pocketPair: false).matches(hole: Self.cards("3h 4d"), board: []))
    #expect(HandPredicate(suited: true).matches(hole: Self.cards("3h 4h"), board: []))
    #expect(!HandPredicate(suited: true).matches(hole: Self.cards("3h 4d"), board: []))
    #expect(HandPredicate(suited: false).matches(hole: Self.cards("3h 4d"), board: []))
    // Board-dependent keys do not apply before the flop.
    #expect(HandPredicate(madeHand: [.set], draws: [.flushDraw]).matches(hole: Self.cards("3h 4d"), board: []))
    #expect(HandPredicate().matches(hole: Self.cards("3h 4d"), board: Self.cards("Ks 7d 5c")))
    #expect(!HandPredicate().matches(hole: Self.cards("3h"), board: []))
  }

  // MARK: Situation

  @Test func situation() throws {
    let instance = try GenerationTestSupport.generator.generate(
      GenerationTestSupport.template("fx.rules.call-cost"), seed: 3)
    let context = instance.actorContext
    #expect(context.legal.toCall > 0)
    #expect(SituationPredicate(facingBet: true).matches(context))
    #expect(!SituationPredicate(facingBet: false).matches(context))
    let features = SpotFeatures(context)
    #expect(SituationPredicate(heroInPosition: features.isInPosition).matches(context))
    #expect(!SituationPredicate(heroInPosition: !features.isInPosition).matches(context))
    #expect(SituationPredicate(spr: DoubleRangeSpec(lo: 0, hi: 1_000)).matches(context))
    #expect(!SituationPredicate(spr: DoubleRangeSpec(lo: features.spr + 1, hi: features.spr + 2)).matches(context))
  }
}
