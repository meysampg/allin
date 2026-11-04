import PokerCore
import Testing

@testable import PokerEquity

@Suite struct RangeTextTests {
  @Test func goldenCounts() throws {
    #expect(try HandRange(parsing: "22+").nonZeroCombos.count == 78)
    #expect(try HandRange(parsing: "A2s+").nonZeroCombos.count == 48)
    #expect(try HandRange(parsing: "KTo+").nonZeroCombos.count == 36)
    #expect(try HandRange(parsing: "AK").nonZeroCombos.count == 16)
    #expect(try HandRange(parsing: "AhKh").nonZeroCombos.count == 1)
    #expect(try HandRange(parsing: "77-99").nonZeroCombos.count == 18)
    #expect(try HandRange(parsing: "A5s-A2s").nonZeroCombos.count == 16)
    #expect(try HandRange(parsing: "  ").nonZeroCombos.isEmpty)
  }

  @Test func weights() throws {
    let r = try HandRange(parsing: "76s:0.5")
    #expect(r.weight(of: try HandClass("76s")) == 0.5)
    #expect(r.nonZeroCombos.count == 4)
    let r2 = try HandRange(parsing: "22+:0.25 AhKh")
    #expect(r2[try Combo("AhKh")] == 1)
    #expect(r2[try Combo("2c2d")] == 0.25)
  }

  @Test func separatorsAndOverwrite() throws {
    let a = try HandRange(parsing: "AA,KK QQ")
    #expect(a.totalWeight == 18)
    let b = try HandRange(parsing: "22+, 33:0")
    #expect(b.weight(of: try HandClass("33")) == 0)
    #expect(b.weight(of: try HandClass("22")) == 1)
  }

  @Test func plusForms() throws {
    let r = try HandRange(parsing: "KTo+")
    for text in ["KTo", "KJo", "KQo"] { #expect(r.weight(of: try HandClass(text)) == 1) }
    #expect(r.weight(of: try HandClass("K9o")) == 0)
    #expect(r.weight(of: try HandClass("KTs")) == 0)
    #expect(try HandRange(parsing: "QQ+").nonZeroCombos.count == 18)
  }

  @Test func invalidTokens() {
    #expect(throws: RangeParseError.invalidToken("ZZ")) { try HandRange(parsing: "ZZ") }
    #expect(throws: RangeParseError.invalidToken("AAs")) { try HandRange(parsing: "AAs") }
    #expect(throws: RangeParseError.invalidToken("AhAh")) { try HandRange(parsing: "AhAh") }
    #expect(throws: RangeParseError.invalidToken("A")) { try HandRange(parsing: "A") }
    #expect(throws: RangeParseError.invalidWeight("AA:2")) { try HandRange(parsing: "AA:2") }
    #expect(throws: RangeParseError.invalidWeight("AA:x")) { try HandRange(parsing: "AA:x") }
    #expect(throws: RangeParseError.invalidSpan("AKs-QJs")) { try HandRange(parsing: "AKs-QJs") }
    #expect(throws: RangeParseError.invalidSpan("77-A5s")) { try HandRange(parsing: "77-A5s") }
    #expect(throws: RangeParseError.invalidSpan("A5s-A2o")) { try HandRange(parsing: "A5s-A2o") }
  }

  @Test func formatterGolden() throws {
    #expect(try HandRange(parsing: "22+").text == "22+")
    #expect(try HandRange(parsing: "AA").text == "AA")
    #expect(try HandRange(parsing: "99-77").text == "77-99")
    #expect(try HandRange(parsing: "A2s+").text == "A2s+")
    #expect(try HandRange(parsing: "KQs KQo").text == "KQ")
    #expect(try HandRange(parsing: "76s:0.5").text == "76s:0.5")
    #expect(try HandRange(parsing: "AhKh").text == "AhKh")
    #expect(HandRange.empty.text == "")
  }

  @Test func roundTripRandomClassRanges() throws {
    var rng = SeededRNG(seed: 42)
    for _ in 0..<200 {
      var r = HandRange()
      for c in HandClass.all where Int.random(in: 0..<4, using: &rng) == 0 {
        let k = Int.random(in: 1...1000, using: &rng)
        let w = k == 1000 ? 1 : Float("0.\(String(repeating: "0", count: 3 - String(k).count))\(k)")!
        r.setClassForTests(c, w)
      }
      let parsed = try HandRange(parsing: r.text)
      #expect(parsed == r)
    }
  }

  @Test func roundTripWithPartialClasses() throws {
    var r = try HandRange(parsing: "AKs, QQ")
    r[try Combo("2c2d")] = 0.5
    r[try Combo("AhKd")] = 0.75
    #expect(try HandRange(parsing: r.text) == r)
  }

  @Test func topRangeRoundTrips() throws {
    let r = HandRange.top(0.2)
    let back = try HandRange(parsing: r.text)
    for k in 0..<1326 { #expect(abs(back.weights[k] - r.weights[k]) <= 0.0005) }
  }
}

extension HandRange {
  fileprivate mutating func setClassForTests(_ c: HandClass, _ w: Float) {
    for combo in c.combos { self[combo] = w }
  }
}
