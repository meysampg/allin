import Foundation
import PokerCore
import Testing

@testable import Curriculum

@Suite struct ContentModelDecodingTests {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private func message<T: Decodable>(_ type: T.Type, _ json: String) -> String {
    do {
      _ = try decode(type, json)
      return ""
    } catch let error as DecodingError {
      return ContentDecoding.translate(error, file: "x.json").message
    } catch { return "\(error)" }
  }

  @Test func blindsSugar() throws {
    #expect(try decode(Blinds.self, "\"1/2\"") == Blinds(small: 1, big: 2))
    #expect(try decode(Blinds.self, "\"1/2/0\"") == Blinds(small: 1, big: 2))
    #expect(try decode(Blinds.self, "\"5/10/1\"").description == "5/10/1")
    #expect(message(Blinds.self, "\"x\"").contains("bad blinds"))
  }

  @Test func rangeSpecs() throws {
    #expect(try decode(IntRangeSpec.self, "7") == IntRangeSpec(lo: 7, hi: 7))
    #expect(try decode(IntRangeSpec.self, "[1,9]") == IntRangeSpec(lo: 1, hi: 9))
    #expect(try decode(DoubleRangeSpec.self, "0.5") == DoubleRangeSpec(lo: 0.5, hi: 0.5))
    #expect(message(IntRangeSpec.self, "[5,1]").contains("lo <= hi"))
    #expect(try decode(RangeSpec.self, "\"22+, A2s+\"").range.totalWeight > 0)
    #expect(message(RangeSpec.self, "\"zz\"").hasPrefix("bad range"))
  }

  @Test func lineTokens() throws {
    let hero = try LineToken(parsing: "hero:call")
    #expect(hero.role == .hero && hero.act == .call)
    #expect(try LineToken(parsing: "bet:0.5-0.75").act == .bet(DoubleRangeSpec(lo: 0.5, hi: 0.75)))
    #expect(try LineToken(parsing: "villain:open:2.5").act == .open(2.5))
    #expect(try LineToken(parsing: "raise:3").description == "raise:3")
    #expect(try decode(LineToken.self, #"{"role":"hero","act":"fold"}"#) == LineToken(role: .hero, act: .fold))
    #expect(message(LineToken.self, "\"bet:x\"") == "bad line token 'bet:x' (expected bet:<fraction>)")
    #expect(message(LineToken.self, "\"zap\"").contains("bad line token 'zap'"))
    #expect(message(LineToken.self, "\"raise:1\"").contains("raise"))
  }

  @Test func lineSpecSugar() throws {
    #expect(try decode(LineSpec.self, "\"checkThrough\"") == .checkThrough)
    #expect(try decode(LineSpec.self, "{}") == .checkThrough)
    let line = try decode(LineSpec.self, #"{"flop":["hero:check","villain:bet:0.5"],"stopAt":"any"}"#)
    #expect(line.streets[.flop]?.count == 2 && line.stopAt == .any && line.consistent)
    let again = try JSONDecoder().decode(LineSpec.self, from: JSONEncoder().encode(line))
    #expect(again == line)
    #expect(message(LineSpec.self, "\"x\"").contains("expected checkThrough"))
  }

  @Test func villainAndExplainerSugar() throws {
    let one = try decode(VillainSpec.self, #"{"character":"bram","position":"BTN"}"#)
    let many = try decode(VillainSpec.self, #"{"characters":["bram"],"position":["BTN"]}"#)
    #expect(one == many)
    #expect(try decode(ExplainerRef.self, "\"potSlices\"") == ExplainerRef(explainer: .potSlices))
    let object = try decode(ExplainerRef.self, #"{"explainer":"whoCallsMe","bind":{"mode":"callers"}}"#)
    #expect(object.bind["mode"] == "callers")
    #expect(message(ExplainerRef.self, "\"nope\"").contains("unknown value 'nope' (expected bettingRoundsTimeline|"))
  }

  @Test func boardAndFixedCards() throws {
    let board = try decode(BoardPredicate.self, #"{"street":"flop","highCard":["A","K"]}"#)
    #expect(board.highCard == [.ace, .king] && board.require.isEmpty)
    #expect(message(BoardPredicate.self, #"{"street":"flop","highCard":["Z"]}"#).contains("unknown rank 'Z'"))
    #expect(
      message(BoardPredicate.self, #"{"street":"flup"}"#).hasPrefix("unknown value 'flup' (expected preflop|flop"))
    let fixed = try decode(FixedCards.self, #"{"hero":"AhKh","board":"Ks9h4h","villains":["QsQd"]}"#)
    #expect(fixed.hero?.count == 2 && fixed.board?.count == 3 && fixed.villains?.first?.count == 2)
    let again = try JSONDecoder().decode(FixedCards.self, from: JSONEncoder().encode(fixed))
    #expect(again == fixed)
    #expect(message(FixedCards.self, #"{"hero":"Zz"}"#).contains("bad cards"))
  }

  @Test func lessonStepsAreTagged() throws {
    let step = try decode(LessonStep.self, #"{"kind":"apply","spot":"a.b","count":3}"#)
    #expect(step == .apply(ApplyStep(spot: "a.b", count: 3, freshSeeds: true)))
    #expect(step.spotID == "a.b" && step.kind == .apply)
    let again = try JSONDecoder().decode(LessonStep.self, from: JSONEncoder().encode(step))
    #expect(again == step)
    #expect(message(LessonStep.self, #"{"kind":"apply","spot":"a.b","count":11}"#).contains("1...10"))
    #expect(message(LessonStep.self, #"{"kind":"dance"}"#).contains("unknown value 'dance'"))
    #expect(message(LessonStep.self, #"{"kind":"hook"}"#) == "missing key 'spot'")
  }

  @Test func decodeErrorMessages() {
    #expect(message(Drill.self, #"{"schemaVersion":1,"id":"a","title":"t","spots":"x","reps":1}"#) == "expected Array")
    #expect(
      message(RealmVenue.self, #"{"id":"a","name":"n","icon":"hut","teaches":"","status":"open"}"#)
        .contains("unknown value 'hut' (expected village|townHall|castle|cave)"))
    #expect(message(VenueNode.self, #"{"id":"a","kind":"lesson"}"#).contains("needs 'lesson'"))
  }

  @Test func templateDefaultsAndVillainSugar() throws {
    let template = CurriculumTestSupport.fixture.template("fx.value.river-bet-or-check")!
    #expect(template.villains.count == 1 && template.villains[0].characters == ["bram"])
    #expect(template.line == .checkThrough && template.reveal == .hero && template.quality.maxRetries == 4)
    let encoded = try JSONEncoder().encode(template)
    #expect(try JSONDecoder().decode(SpotTemplate.self, from: encoded) == template)
    #expect(CurriculumTestSupport.fixture.template("fx.ranks.pick-winner")!.reveal == .all)
  }

  @Test func everyFixtureFileRoundTrips() throws {
    for lesson in CurriculumTestSupport.fixture.lessons.values {
      #expect(try JSONDecoder().decode(Lesson.self, from: JSONEncoder().encode(lesson)) == lesson)
    }
    for template in CurriculumTestSupport.fixture.templates.values {
      #expect(try JSONDecoder().decode(SpotTemplate.self, from: JSONEncoder().encode(template)) == template)
    }
  }

  @Test func seatPositions() {
    #expect(SeatPositions.names(count: 6) == [.btn, .sb, .bb, .utg, .hj, .co])
    #expect(SeatPositions.names(count: 2) == [.btn, .bb])
    #expect(SeatPositions.seat(of: .bb, button: 4, seatCount: 6) == 0)
    #expect(SeatPositions.seat(of: .lj, button: 0, seatCount: 6) == nil)
  }
}
