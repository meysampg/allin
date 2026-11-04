import PokerCore
import Testing

@testable import PokerEquity

@Suite struct ComboAndClassTests {
  @Test func comboBijection() {
    #expect(Combo.all.count == 1326)
    #expect(Set(Combo.all.map(\.index)).count == 1326)
    var masks = Set<UInt64>()
    for combo in Combo.all {
      #expect(Combo(index: combo.index) == combo)
      #expect(Combo(combo.high, combo.low) == combo)
      #expect(Combo(combo.low, combo.high) == combo)
      #expect(combo.high.index > combo.low.index)
      #expect(combo.mask.count == 2)
      masks.insert(combo.mask.bits)
    }
    #expect(masks.count == 1326)
  }

  @Test func comboIndexFormula() {
    let combo = Combo(Card(index: 7), Card(index: 3))
    #expect(combo.index == 7 * 6 / 2 + 3)
  }

  @Test func comboTextRoundTrip() throws {
    for combo in Combo.all.prefix(200) { #expect(try Combo(combo.description) == combo) }
    #expect(try Combo("KhAh") == Combo("AhKh"))
    #expect(throws: (any Error).self) { try Combo("AhAh") }
    #expect(throws: (any Error).self) { try Combo("Ah") }
  }

  @Test func comboClassMapping() throws {
    #expect(try Combo("AhKh").handClass == HandClass("AKs"))
    #expect(try Combo("AhKd").handClass == HandClass("AKo"))
    #expect(try Combo("7s7d").handClass == HandClass("77"))
  }

  @Test func classCounts() {
    #expect(HandClass.all.count == 169)
    #expect(Set(HandClass.all).count == 169)
    var total = 0
    for c in HandClass.all {
      let expected = c.isPair ? 6 : (c.suited ? 4 : 12)
      #expect(c.comboCount == expected)
      #expect(c.combos.count == expected)
      #expect(c.combos.allSatisfy { $0.handClass == c })
      total += c.combos.count
    }
    #expect(total == 1326)
  }

  @Test func gridRoundTrip() throws {
    for (i, c) in HandClass.all.enumerated() {
      #expect(c.gridIndex == i)
      #expect(HandClass(gridRow: c.gridRow, gridColumn: c.gridColumn) == c)
      #expect(try HandClass(c.description) == c)
    }
    let aks = try HandClass("AKs")
    #expect(aks.gridRow == 0 && aks.gridColumn == 1)
    let ako = try HandClass("AKo")
    #expect(ako.gridRow == 1 && ako.gridColumn == 0)
    #expect(HandClass(gridRow: 12, gridColumn: 12).description == "22")
  }

  @Test func classValidation() {
    #expect(HandClass(high: .ace, low: .ace, suited: true) == nil)
    #expect(HandClass(high: .two, low: .ace, suited: false) == nil)
    #expect(throws: RangeParseError.self) { try HandClass("AK") }
    #expect(throws: RangeParseError.self) { try HandClass("QQs") }
    #expect(throws: RangeParseError.self) { try HandClass("Zs") }
  }
}

@Suite struct HandRangeOpsTests {
  @Test func emptyAndFull() {
    #expect(HandRange.empty.totalWeight == 0)
    #expect(HandRange.full.totalWeight == 1326)
    #expect(HandRange.empty.nonZeroCombos.isEmpty)
    #expect(HandRange.full.nonZeroCombos.count == 1326)
  }

  @Test func clampingAndSubscript() throws {
    var r = HandRange(weights: [Float](repeating: 2, count: 1326))
    #expect(r.weights.allSatisfy { $0 == 1 })
    let combo = try Combo("AhKh")
    r[combo] = -3
    #expect(r[combo] == 0)
    r[combo] = 0.25
    #expect(r[combo] == 0.25)
  }

  @Test func classWeightsAndGrid() throws {
    let r = HandRange(classWeights: [try HandClass("AKs"): 0.5, try HandClass("QQ"): 1])
    #expect(r.weight(of: try HandClass("AKs")) == 0.5)
    #expect(r.totalWeight == 6 + 2)
    let g = r.grid
    #expect(g[0][1] == 0.5)
    #expect(g[2][2] == 1)
    #expect(HandRange(grid: g) == r)
  }

  @Test func removingDeadCards() throws {
    let dead = CardSet(try Card.parseList("AhKd"))
    let r = HandRange.full.removing(dead)
    #expect(r.totalWeight == 1326 - 51 - 51 + 1)
    #expect(r[try Combo("AhKd")] == 0)
    #expect(r[try Combo("AhKs")] == 0)
    #expect(r[try Combo("AsKs")] == 1)
  }

  @Test func scaleAndMultiply() throws {
    let a = try HandRange(parsing: "AA, KK:0.5")
    #expect(a.scaled(by: 0.5).totalWeight == 3 + 1.5)
    let b = try HandRange(parsing: "KK, QQ")
    #expect(a.multiplied(by: b).totalWeight == 3)
  }

  @Test func blending() throws {
    let a = try HandRange(parsing: "AA")
    let b = try HandRange(parsing: "KK")
    #expect(a.blended(with: b, t: 0) == a)
    #expect(a.blended(with: b, t: 1) == b)
    let mid = a.blended(with: b, t: 0.5)
    #expect(abs(mid.totalWeight - 6) < 1e-5)
    #expect(abs(Double(mid.weight(of: try HandClass("AA"))) - 0.5) < 1e-6)
  }

  @Test func topFraction() {
    #expect(abs(HandRange.top(0.1).totalWeight - 132.6) < 0.01)
    #expect(HandRange.top(0).totalWeight == 0)
    #expect(HandRange.top(1).totalWeight == 1326)
    var previous = HandRange.top(0)
    for i in 1...40 {
      let next = HandRange.top(Double(i) / 40)
      for k in 0..<1326 { #expect(next.weights[k] >= previous.weights[k]) }
      previous = next
    }
  }

  @Test func bandAdditivity() {
    let a = HandRange.band(from: 0.05, to: 0.2)
    let b = HandRange.band(from: 0.2, to: 0.4)
    let whole = HandRange.band(from: 0.05, to: 0.4)
    for k in 0..<1326 { #expect(abs(a.weights[k] + b.weights[k] - whole.weights[k]) < 1e-5) }
    #expect(abs(whole.totalWeight - 0.35 * 1326) < 0.01)
    #expect(HandRange.band(from: 0.5, to: 0.2).totalWeight == 0)
  }
}

@Suite struct PreflopOrderingTests {
  @Test func permutationWithAcesFirst() {
    let o = PreflopOrdering.standard
    #expect(Set(o.classes).count == 169)
    #expect(o.classes.first?.description == "AA")
    #expect(o.rank(of: o.classes[10]) == 10)
  }

  @Test func shape() throws {
    let o = PreflopOrdering.standard
    #expect(o.rank(of: try HandClass("AKs")) < 8)
    #expect(o.rank(of: try HandClass("32o")) >= 166)
    for hi in 1..<13 {
      for lo in 0..<hi {
        let h = Rank(rawValue: UInt8(hi))!
        let l = Rank(rawValue: UInt8(lo))!
        let s = HandClass(high: h, low: l, suited: true)!
        let off = HandClass(high: h, low: l, suited: false)!
        #expect(o.rank(of: s) < o.rank(of: off))
      }
    }
    let pairRanks = (0..<13).reversed().map {
      o.rank(of: HandClass(high: Rank(rawValue: UInt8($0))!, low: Rank(rawValue: UInt8($0))!, suited: false)!)
    }
    #expect(pairRanks == pairRanks.sorted())
    #expect(Set(pairRanks).count == 13)
  }

  @Test func percentiles() throws {
    let o = PreflopOrdering.standard
    let aa = o.percentile(of: try HandClass("AA"))
    #expect(abs(aa - 0.0023) < 0.0001)
    #expect(o.percentile(of: try Combo("AhAd")) == aa)
    var last = 0.0
    for c in o.classes {
      let p = o.percentile(of: c)
      #expect(p > last && p < 1)
      last = p
    }
  }

  @Test func perturbation() {
    let o = PreflopOrdering.standard
    #expect(o.perturbed(seed: 1, amount: 0) == o)
    let p = o.perturbed(seed: 7, amount: 0.8)
    #expect(p == o.perturbed(seed: 7, amount: 0.8))
    #expect(p != o)
    #expect(Set(p.classes).count == 169)
    #expect(p.classes[0].description == "AA" && p.classes[1].description == "KK")
    #expect(o.perturbed(seed: 8, amount: 0.8) != p)
  }
}
