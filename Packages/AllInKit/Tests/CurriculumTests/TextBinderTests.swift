import PokerCore
import Testing

@testable import Curriculum

@Suite struct TextBinderTests {
  @Test func placeholdersInOrderOfAppearance() throws {
    #expect(
      try TextBinder.placeholders(in: "{villain} bets {bet}; {villain} again, {pot}") == ["villain", "bet", "pot"])
    #expect(try TextBinder.placeholders(in: "no placeholders").isEmpty)
  }

  @Test func doubledBracesAreLiteral() throws {
    #expect(try TextBinder.placeholders(in: "{{pot}} is {pot}") == ["pot"])
    let bound = try TextBinder.bind("Write {{pot}} as {pot}}} ok", TextBindings(["pot": "150"]))
    #expect(bound == "Write {pot} as 150} ok")
  }

  @Test func bindsEveryPlaceholder() throws {
    let bindings = TextBindings(["villain": "Bram", "bet": "30"])
    #expect(try TextBinder.bind("{villain} bets {bet}. {bet}!", bindings) == "Bram bets 30. 30!")
  }

  @Test func unresolvedAndUnterminated() {
    #expect(throws: TextBindError.unresolved("missing")) { try TextBinder.bind("a {missing}", TextBindings()) }
    #expect(throws: TextBindError.unterminated(2)) { try TextBinder.bind("a {pot", TextBindings(["pot": "1"])) }
    #expect(throws: TextBindError.unresolved("")) { try TextBinder.bind("{}", TextBindings()) }
  }

  @Test func bindingsMerge() {
    var a = TextBindings(["x": "1", "y": "2"])
    a["z"] = "3"
    let merged = a.merging(TextBindings(["y": "9"]))
    #expect(merged["x"] == "1" && merged["y"] == "9" && merged["z"] == "3")
  }

  @Test func formatting() {
    #expect(TextBinder.pretty(EvaluationTestSupport.cards("Ah7h")) == "A♥ 7♥")
    #expect(TextBinder.pretty(EvaluationTestSupport.cards("Tc9d2s")) == "T♣ 9♦ 2♠")
    #expect(TextBinder.pretty([]) == "")
    #expect(TextBinder.percent(0.2) == "20%")
    #expect(TextBinder.percent(0.345) == "35%")
    #expect(TextBinder.bb(1.84, signed: true) == "+1.8 bb")
    #expect(TextBinder.bb(2, signed: true) == "+2 bb")
    #expect(TextBinder.bb(-2.3, signed: true) == "−2.3 bb")
    #expect(TextBinder.bb(6.5, signed: false) == "6.5 bb")
    #expect(TextBinder.bb(0, signed: true) == "0 bb")
  }

  @Test func commonKeysPresentForAnInstance() throws {
    let template = EvaluationTestSupport.template("fx.potodds.obvious")
    let instance = try EvaluationTestSupport.generator.generate(template, seed: 3)
    let bindings = TextBinder.bindings(for: instance, characters: EvaluationTestSupport.catalog)
    #expect(Set(bindings.values.keys) == TextBinder.commonKeys)
    #expect(bindings["hero"] == "You")
    #expect(bindings["villain"] == "Vexa" || bindings["villain"]?.isEmpty == false)
    #expect(bindings["street"] == "flop")
    #expect(bindings["position"] == "BB")
    #expect(bindings["villainPosition"] == "BTN")
    #expect(bindings["bigBlind"] == "10")
    #expect(bindings["heroHand"] == "A♥ Q♥" || bindings["heroHand"]?.contains("♥") == true)
    #expect(bindings["board"]?.split(separator: " ").count == 3)
    let pot = try #require(Int(bindings["pot"]!))
    let bet = try #require(Int(bindings["bet"]!))
    let toCall = try #require(Int(bindings["toCall"]!))
    #expect(Int(bindings["potIfCall"]!) == pot + toCall)
    #expect(Int(bindings["potBeforeBet"]!) == pot - bet)
    #expect(toCall == bet)
  }

  @Test func methodKeys() {
    for method in EvaluationMethod.allCases {
      #expect(TextBinder.commonKeys.isSubset(of: TextBinder.keys(for: method)))
    }
    #expect(
      TextBinder.keys(for: .closedFormEV).isSuperset(of: ["priceNeeded", "equity", "evGain", "bestAction", "answer"]))
    #expect(TextBinder.keys(for: .showdownWinner).isSuperset(of: ["winner", "winningHand"]))
    #expect(TextBinder.keys(for: .outs).isSuperset(of: ["outs", "outsCount"]))
  }

  @Test func handNames() {
    #expect(HandNaming.heroHandName(hole: EvaluationTestSupport.cards("Ah7h"), board: []) == "Ace-Seven suited")
    #expect(HandNaming.heroHandName(hole: EvaluationTestSupport.cards("Ah7d"), board: []) == "Ace-Seven offsuit")
    #expect(HandNaming.heroHandName(hole: EvaluationTestSupport.cards("QhQd"), board: []) == "Pocket Queens")
    let topPair = HandNaming.heroHandName(
      hole: EvaluationTestSupport.cards("AhKd"), board: EvaluationTestSupport.cards("As7c2d"))
    #expect(topPair == "top pair, good kicker")
    let draw = HandNaming.heroHandName(
      hole: EvaluationTestSupport.cards("Ah9h"), board: EvaluationTestSupport.cards("Kh7h2d"))
    #expect(draw.hasSuffix("a flush draw") || draw.hasSuffix("the nut flush draw"))
    #expect(draw.hasPrefix("no pair and"))
  }
}
