import Foundation
import Testing

@testable import Curriculum

@Suite struct DecisionTypeKeyTests {
  @Test func rawValueRoundTrip() {
    let k = DecisionTypeKey(templateID: "pre.open", answerClass: "raise")
    #expect(k.rawValue == "pre.open#raise")
    #expect(DecisionTypeKey(rawValue: k.rawValue) == k)
    #expect(k.description == k.rawValue)
  }

  @Test func splitsAtLastHash() {
    let k = DecisionTypeKey(rawValue: "a#b#c")
    #expect(k?.templateID == "a#b")
    #expect(k?.answerClass == "c")
    #expect(DecisionTypeKey(rawValue: "nohash") == nil)
  }

  @Test func codable() throws {
    let k = DecisionTypeKey(templateID: "t", answerClass: "fold")
    let data = try JSONEncoder().encode(k)
    #expect(try JSONDecoder().decode(DecisionTypeKey.self, from: data) == k)
  }
}
