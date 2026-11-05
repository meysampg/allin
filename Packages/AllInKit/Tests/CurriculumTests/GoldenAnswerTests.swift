import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

/// Hand-built spots with answers worked out by hand.
@Suite struct GoldenAnswerTests {
  typealias S = EvaluationTestSupport

  static func cards(_ text: String) -> [Card] { S.cards(text) }

  static func input(_ spot: (template: SpotTemplate, instance: SpotInstance)) -> EvalInput {
    EvalInput(instance: spot.instance, template: spot.template, characters: S.catalog, budget: .test)
  }

  // MARK: Showdown

  static func showdown(hero: String, villain: String, board: String) -> (SpotSolution, SpotInstance) {
    let spot = S.fixedSpot(
      method: .showdownWinner, question: QuestionSpec(type: .pickWinner), street: .river, hero: hero, board: board,
      villains: [villain])
    return (try! S.solve(spot), spot.instance)
  }

  @Test func showdownSplitOnABoardStraight() {
    let (solution, _) = Self.showdown(hero: "AhKd", villain: "QcJd", board: "2c3d4h5s6c")
    #expect(solution.correct == .option("split"))
    #expect(solution.answerClass == "split")
    #expect(solution.bindings["winner"] == "Nobody (split pot)")
    #expect(solution.bindings["winningHand"] == "Straight, Six high")
    #expect(solution.options.map(\.id).last == "split")
  }

  @Test func showdownDecidedByAKicker() {
    let (solution, instance) = Self.showdown(hero: "KsQd", villain: "KcJd", board: "Kh9d5c3s2h")
    #expect(solution.correct == .option("seat:\(instance.heroSeat)"))
    #expect(solution.answerClass == "kicker")
    #expect(solution.bindings["winner"] == "You")
    #expect(solution.bindings["winningHand"] == "Pair of Kings")
    #expect(solution.options.first { $0.id == "seat:\(instance.heroSeat)" }?.label == "You")
    let wrong = SpotEvaluator.grade(.option("split"), solution: solution)
    #expect(wrong.grade == .leak && wrong.verdictTitle == "✗ Not quite: You win")
  }

  @Test func showdownDecidedByCategoryAndByRank() {
    let (category, _) = Self.showdown(hero: "AhAd", villain: "KcQd", board: "2c7d9h4sJc")
    #expect(category.answerClass == "category")
    #expect(category.explanation == "Pair of Aces beats King high")
    let (rank, instance) = Self.showdown(hero: "AhAd", villain: "KcKd", board: "2c7d9h4s3c")
    #expect(rank.answerClass == "rank")
    #expect(rank.correct == .option("seat:\(instance.heroSeat)"))
  }

  @Test func showdownNamesTheVillainWhenHeLoses() {
    let (solution, instance) = Self.showdown(hero: "2h3d", villain: "AcAd", board: "7c8d9hJsKc")
    let villain = instance.villainSeats[0]
    #expect(solution.correct == .option("seat:\(villain)"))
    let wrong = SpotEvaluator.grade(.option("seat:\(instance.heroSeat)"), solution: solution)
    let name = instance.seatNames[villain]!
    #expect(wrong.verdictTitle == "✗ Not quite: \(name) wins")
    #expect(wrong.verdictDetail == "Pair of Aces beats King high")
  }

  // MARK: Best five

  @Test func bestFiveWithTheBoardPlaying() {
    let spot = S.fixedSpot(
      method: .bestFive, question: QuestionSpec(type: .pickCards, pick: 5), street: .river, hero: "2c3d",
      board: "AsKsQsJsTs", villains: ["9h8h"])
    let solution = try! S.solve(spot)
    #expect(solution.answerClass == "boardPlays")
    #expect(solution.bindings["bestHand"] == "Royal flush")
    #expect(solution.pick == 5)
    #expect(Set(cardsOf(solution.correct)) == Set(Self.cards("AsKsQsJsTs")))
    let good = SpotEvaluator.grade(.cards(Self.cards("TsJsQsKsAs")), solution: solution)
    #expect(good.grade == .good)
    let usesHero = SpotEvaluator.grade(.cards(Self.cards("2cJsQsKsAs")), solution: solution)
    #expect(usesHero.grade == .leak)
    let notInHand = SpotEvaluator.grade(.cards(Self.cards("2sJsQsKsAs")), solution: solution)
    #expect(notInHand.grade == .leak)
    let tooFew = SpotEvaluator.grade(.cards(Self.cards("JsQsKsAs")), solution: solution)
    #expect(tooFew.grade == .leak)
  }

  @Test func bestFiveIsTheCategoryNameAndAnyEquivalentFiveIsGood() {
    let spot = S.fixedSpot(
      method: .bestFive, question: QuestionSpec(type: .pickCards, pick: 5), street: .river, hero: "AhAd",
      board: "AcKc2d7s9h", villains: ["QsJs"])
    let solution = try! S.solve(spot)
    #expect(solution.answerClass == "trips")
    #expect(Set(cardsOf(solution.correct)) == Set(Self.cards("AhAdAcKc9h")))
    #expect(SpotEvaluator.grade(.cards(Self.cards("AhAdAcKc7s")), solution: solution).grade == .leak)
    #expect(SpotEvaluator.grade(.cards(Self.cards("Kc9hAcAdAh")), solution: solution).grade == .good)
  }

  // MARK: Nuts

  @Test func nutsOnAMonotoneBoard() {
    let spot = S.fixedSpot(
      method: .nuts, question: QuestionSpec(type: .pickCards, pick: 2), street: .flop, hero: "2c3d",
      board: "2s7sJs", villains: ["QcJd"])
    let solution = try! S.solve(spot)
    #expect(solution.answerClass == "flush")
    #expect(solution.bindings["nuts"] == "Flush, Ace high")
    #expect(Set(cardsOf(solution.correct)) == Set(Self.cards("AsKs")))
    #expect(SpotEvaluator.grade(.cards(Self.cards("KsAs")), solution: solution).grade == .good)
    #expect(SpotEvaluator.grade(.cards(Self.cards("AsQs")), solution: solution).grade == .leak)
    #expect(SpotEvaluator.grade(.cards(Self.cards("As2s")), solution: solution).grade == .leak)
  }

  @Test func nutsHandClassOnAStraightFlushBoard() {
    let spot = S.fixedSpot(
      method: .nuts,
      question: QuestionSpec(type: .pickHandClass, options: ["pair", "flush", "straightFlush"]), street: .turn,
      hero: "2c3d", board: "2s7s9sJs", villains: ["QcJd"])
    let solution = try! S.solve(spot)
    #expect(solution.correct == .option("straightFlush"))
    #expect(solution.options.map(\.id) == ["pair", "flush", "straightFlush"])
    #expect(solution.options.last?.label == "Straight Flush")
    #expect(solution.answerClass == "straightFlush")
    #expect(SpotEvaluator.grade(.option("flush"), solution: solution).grade == .leak)
  }

  // MARK: Counts

  @Test func eightOutsForAnOpenEndedStraightDraw() {
    let numberSpot = S.fixedSpot(
      method: .outs, question: QuestionSpec(type: .number), street: .flop, hero: "9c8d", board: "7h6s2c",
      villains: ["QcJd"])
    let number = try! S.solve(numberSpot)
    #expect(number.correct == .number(8))
    #expect(number.tolerance == 1)
    #expect(number.answerClass == "few")
    #expect(number.bindings["outsCount"] == "8")
    let cardsSpot = S.fixedSpot(
      method: .outs, question: QuestionSpec(type: .pickCards), street: .flop, hero: "9c8d", board: "7h6s2c",
      villains: ["QcJd"])
    let picked = try! S.solve(cardsSpot)
    let outs = cardsOf(picked.correct)
    #expect(Set(outs.map(\.rank)) == [.five, .ten])
    #expect(outs.count == 8)
    #expect(picked.pick == nil)
    #expect(SpotEvaluator.grade(.cards(outs.reversed()), solution: picked).grade == .good)
  }

  @Test func handsThatBeatMeOnAPairedBoard() {
    let hero = "AhKd"
    let board = "QsQc7d"
    let numberSpot = S.fixedSpot(
      method: .beatsMeCount, question: QuestionSpec(type: .number), street: .flop, hero: hero, board: board,
      villains: ["2c3d"])
    let solution = try! S.solve(numberSpot)
    // Brute force over every pair of unseen cards.
    let heroCards = Self.cards(hero)
    let boardCards = Self.cards(board)
    let heroValue = HandEvaluator.evaluate(hole: heroCards, board: boardCards)
    var expected = 0
    for combo in Combo.all where combo.mask.isDisjoint(with: CardSet(heroCards + boardCards)) {
      if HandEvaluator.evaluate(hole: combo.cards, board: boardCards) > heroValue { expected += 1 }
    }
    #expect(solution.correct == .number(expected))
    #expect(expected > 0)
    #expect(solution.tolerance == max(1, Int((0.2 * Double(expected)).rounded())))
    #expect(solution.bindings["beatsMeCount"] == String(expected))

    let choiceSpot = S.fixedSpot(
      method: .beatsMeCount, question: QuestionSpec(type: .choice, options: ["none", "few", "many"]),
      street: .flop, hero: hero, board: board, villains: ["2c3d"])
    let choice = try! S.solve(choiceSpot)
    let bucket = expected == 0 ? "none" : (expected <= 20 ? "few" : "many")
    #expect(choice.correct == .option(bucket))
    #expect(choice.answerClass == bucket)
    #expect(choice.options.map(\.id) == ["none", "few", "many"])
  }

  @Test func theNutsHaveNothingBeatingThem() {
    let spot = S.fixedSpot(
      method: .beatsMeCount, question: QuestionSpec(type: .choice, options: ["none", "few", "many"]),
      street: .flop, hero: "AhAd", board: "AcAs7d", villains: ["2c3d"])
    // Quad aces: nothing beats them.
    let solution = try! S.solve(spot)
    #expect(solution.correct == .option("none"))
  }

  // MARK: Chips and rules

  @Test func potAfterAScriptedLine() {
    let spot = S.fixedSpot(
      method: .potCount, question: QuestionSpec(type: .number, tolerance: 0), street: .flop, hero: "AhQh",
      board: "Ks9d4c", villains: ["7c2d"], line: S.facingFlopBet, heroPosition: .bb, villainPosition: .btn)
    let solution = try! S.solve(spot)
    // Blinds 1/2: open to 5, call, then a bet of half the 10-chip pot.
    #expect(solution.correct == .number(15))
    #expect(spot.instance.state.pot == 15)
    #expect(solution.answerClass == "flop")
    #expect(solution.tolerance == 0)
    #expect(SpotEvaluator.grade(.number(15), solution: solution).grade == .good)
    #expect(SpotEvaluator.grade(.number(14), solution: solution).grade == .leak)
  }

  static func facingBet(ask: LegalAsk, type: QuestionType) -> (template: SpotTemplate, instance: SpotInstance) {
    S.fixedSpot(
      method: .legalSizes, question: QuestionSpec(type: type), street: .flop, hero: "AhQh", board: "Ks9d4c",
      villains: ["7c2d"], ask: ask, line: S.facingFlopBet, heroPosition: .bb, villainPosition: .btn)
  }

  @Test func callCostMinRaiseAndLegalActions() {
    let cost = try! S.solve(Self.facingBet(ask: .callCost, type: .number))
    #expect(cost.correct == .number(5))
    #expect(cost.answerClass == "callCost")

    let spot = Self.facingBet(ask: .minRaise, type: .sizeChoice)
    let minRaise = try! S.solve(spot)
    // Facing a 5 bet: the smallest raise is to 10; decoys are bet + big blind, one raise more, and the whole stack.
    let stack = spot.instance.actorContext.legal.allInTo!
    #expect(minRaise.correct == .option("size:10"))
    #expect(minRaise.options.map(\.id) == ["size:7", "size:10", "size:15", "size:\(stack)"])
    #expect(minRaise.options.map(\.label).prefix(3) == ["Raise to 7", "Raise to 10", "Raise to 15"])
    #expect(minRaise.answerClass == "minRaise")
    #expect(SpotEvaluator.grade(.option("size:7"), solution: minRaise).grade == .leak)

    let actions = try! S.solve(Self.facingBet(ask: .actions, type: .choice))
    #expect(actions.correct == .options(["fold", "call", "raise", "allin"]))
    #expect(actions.answerClass == "allin+call+fold+raise")
    #expect(actions.options.map(\.id) == ["fold", "check", "call", "bet", "raise", "allin"])
    #expect(SpotEvaluator.grade(.options(["fold", "call", "raise", "allin"]), solution: actions).grade == .good)
    #expect(SpotEvaluator.grade(.options(["fold", "call", "raise"]), solution: actions).grade == .leak)

    let open = S.fixedSpot(
      method: .legalSizes, question: QuestionSpec(type: .choice), street: .flop, hero: "AhQh", board: "Ks9d4c",
      villains: ["7c2d"], ask: .actions)
    let unopened = try! S.solve(open)
    #expect(unopened.correct == .options(["fold", "check", "bet", "allin"]))
    #expect(unopened.answerClass == "allin+bet+check+fold")
  }

  @Test func nextToActAfterFolds() throws {
    let template = GenerationTestSupport.template("fx.rules.next-to-act")
    var sawFold = false
    var classes = Set<String>()
    for seed in 0..<30 {
      let instance = try S.generator.generate(template, seed: UInt64(seed))
      let solution = try S.evaluator.evaluateSerial(instance, template: template)
      let folded = Set(instance.state.seats.filter { $0.status == .folded }.map(\.seat))
      sawFold = sawFold || !folded.isEmpty
      for seat in folded { #expect(!solution.options.map(\.id).contains("seat:\(seat)")) }
      let acted = instance.history.contains { $0.street == instance.street }
      #expect(solution.answerClass == "flop-\(acted ? "next" : "first")")
      classes.insert(solution.answerClass)
      #expect(solution.correct == .option("seat:\(instance.actor)"))
      #expect(solution.bindings["answer"] == instance.seatNames[instance.actor])
    }
    #expect(sawFold)
    print("NEXTTOACT classes \(classes.sorted())")
  }

  // MARK: Expected value

  @Test func callFormula() {
    // Equity 0.35, pot 150, call 50: 0.35 * 200 - 50 = +20 chips.
    #expect(abs(ClosedFormEV.call(equity: 0.35, pot: 150, toCall: 50) - 20) < 1e-9)
  }

  static let callOrFold = QuestionSpec(type: .action, options: ["fold", "call"])

  @Test func closedFormCallOnTheRiverMatchesTheManualFormula() throws {
    let base = S.template("fx.potodds.obvious")
    let template = S.variant(
      base, evaluation: EvaluationSpec(method: .closedFormEV, vsRange: "AA, KK, QQ"), question: Self.callOrFold,
      fixed: FixedCards(hero: Self.cards("AdKd"), board: Self.cards("Ks8d3c2h9s")),
      line: S.line(#"{"preflop":["villain:open:2.5","hero:call"],"river":["hero:check","villain:bet:0.5-0.75"]}"#),
      board: BoardPredicate(street: .river))
    let instance = try S.generator.generate(template, seed: 9)
    let solution = try S.evaluator.evaluateSerial(instance, template: template)
    let context = try #require(instance.heroContext)
    // AA has 3 live combos (the king of diamonds blocks nothing, the ace of diamonds is ours), KK has the two
    // kings of clubs and hearts... the equity is worked out by hand below.
    let live = HandRange(weights: HandRange.full.weights).removing(CardSet(context.holeCards + context.board))
    let range = try HandRange(parsing: "AA, KK, QQ").removing(CardSet(context.holeCards + context.board))
    _ = live
    let exact = EquityCalculator.exact(hero: context.holeCards, vs: range, board: context.board)
    let expectedChips = ClosedFormEV.call(equity: exact.equity, pot: context.pot, toCall: context.legal.callAmount)
    let call = try #require(solution.evs?.candidate(for: .call))
    #expect(abs(call.evBB - expectedChips / Double(instance.config.bigBlind)) < 1e-9)
    #expect(call.method == .closedForm && call.standardError == 0)
    #expect(solution.evs?.candidate(for: .fold)?.evBB == 0)
    // Pairs of queens lose to a king-high flush... here: hero beats QQ only.
    #expect(abs(exact.equity - 0.6) < 1e-9)
    #expect(solution.bindings["equity"] == "60%")
    let odds = Double(context.legal.callAmount) / Double(context.pot + context.legal.callAmount)
    #expect(solution.bindings["priceNeeded"] == TextBinder.percent(odds))
    #expect(solution.answerClass == "call")
  }

  @Test func closedFormBetValueFromFoldProbability() throws {
    let base = S.template("fx.potodds.obvious")
    let template = S.variant(
      base, evaluation: EvaluationSpec(method: .closedFormEV, vsRange: "AA, KK, QQ"),
      question: QuestionSpec(type: .action, options: ["fold", "call", "raise:3"]),
      fixed: FixedCards(hero: Self.cards("AdKd"), board: Self.cards("Ks8d3c2h9s")),
      line: S.line(#"{"preflop":["villain:open:2.5","hero:call"],"river":["hero:check","villain:bet:0.5-0.75"]}"#),
      board: BoardPredicate(street: .river))
    let instance = try S.generator.generate(template, seed: 9)
    let input = EvalInput(instance: instance, template: template, characters: S.catalog, budget: .test)
    let context = try #require(instance.heroContext)
    let villain = instance.villainSeats[0]
    let range = try HandRange(parsing: "AA, KK, QQ").removing(CardSet(context.holeCards + context.board))
    let raise = try #require(EVOptions.resolve(["raise:3"], context: context).first).action
    func value(_ strategy: any StrategyProvider) throws -> Double {
      try ClosedFormMethod.value(
        of: raise, input: input, context: context, villain: villain, strategy: strategy, range: range, equity: 0.6,
        samples: 100, seed: 1)
    }
    // Everyone folds: the pot is ours. Everyone calls: the equity formula with the extra chips.
    #expect(try abs(value(S.AlwaysFold()) - Double(context.pot)) < 1e-9)
    let step = try HandReducer.apply(raise, to: instance.state)
    let added = step.records.compactMap { record -> Int? in
      if case .actionApplied(let a, _) = record { return a.chipsAdded }
      return nil
    }[0]
    let reply = try #require(
      DecisionContext.make(
        from: step.state, for: villain, history: instance.history + EVOptions.entry(of: step.records, street: .river)))
    let eq = EquityCalculator.exact(hero: context.holeCards, vs: range, board: context.board).equity
    let expected = ClosedFormEV.bet(
      foldEquity: 0, equityWhenCalled: eq, pot: context.pot, bet: added, call: reply.legal.callAmount)
    #expect(try abs(value(S.AlwaysCall()) - expected) < 1e-9)
  }

  @Test func pushFoldAgainstAnAlwaysCallStrategyIsTheEquityFormula() throws {
    let template = S.template("fx.push.sb-shove")
    let instance = try S.generator.generate(template, seed: 31)
    let input = EvalInput(instance: instance, template: template, characters: S.catalog, budget: .test)
    let context = try #require(instance.heroContext)
    let villain = instance.villainSeats[0]
    let dead = CardSet(context.holeCards)
    let range = HandRange.full.removing(dead)
    let draft = try PushFoldMethod.solve(input, ranges: [villain: range], strategy: S.AlwaysCall())
    let allIn = try #require(draft.evs?.candidate(for: .allIn))

    let view = try #require(context.view(of: villain))
    let x = min(context.legal.stack, view.stack + view.committedThisStreet - context.legal.committed)
    let finalPot = context.pot + 2 * x + context.legal.committed - view.committedThisStreet
    var weight = 0.0
    var equity = 0.0
    for combo in range.nonZeroCombos {
      weight += 1
      equity += EquityCalculator.preflop(context.holeCards, combo.cards).equity
    }
    let expected = (equity / weight * Double(finalPot) - Double(x)) / Double(instance.config.bigBlind)
    #expect(abs(allIn.evBB - expected) < 1e-6)
    #expect(draft.evs?.candidate(for: .fold)?.evBB == 0)
    print("PUSHFOLD \(Card.format(context.holeCards)) shove \(allIn.evBB) bb, eq \(equity / weight)")

    let folds = try PushFoldMethod.solve(input, ranges: [villain: range], strategy: S.AlwaysFold())
    let steal = try #require(folds.evs?.candidate(for: .allIn))
    #expect(abs(steal.evBB - Double(context.pot) / Double(instance.config.bigBlind)) < 1e-9)
    #expect(folds.answerClass == "allin")
  }

  // MARK: Ranges

  @Test func rangeMatchScores() throws {
    let template = S.template("fx.ranges.paint-open")
    let instance = try S.generator.generate(template, seed: 5)
    let solution = try S.evaluator.evaluateSerial(instance, template: template)
    guard case .range(let target) = solution.correct else {
      Issue.record("a range")
      return
    }
    #expect(solution.answerClass == "CO")
    #expect(target.totalWeight > 0 && target.totalWeight < HandRange.full.totalWeight)
    let identical = SpotEvaluator.grade(.range(target), solution: solution)
    #expect(identical.grade == .good && abs(identical.quality - 1) < 1e-9)
    // The complement of the classes the target touches shares nothing with it.
    var opposite = [HandClass: Float]()
    for handClass in HandClass.all { opposite[handClass] = target.weight(of: handClass) > 0 ? 0 : 1 }
    let disjoint = SpotEvaluator.grade(.range(HandRange(classWeights: opposite)), solution: solution)
    #expect(disjoint.grade == .leak && disjoint.quality == 0)
    #expect(disjoint.verdictTitle.hasPrefix("✗ Not quite"))
    // A range that adds the same amount again as extra hands scores in between.
    var wider = [HandClass: Float]()
    for handClass in HandClass.all { wider[handClass] = max(target.weight(of: handClass), 0.2) }
    let partial = SpotEvaluator.grade(.range(HandRange(classWeights: wider)), solution: solution)
    #expect(partial.quality > 0 && partial.quality < 1)
    // Painting nothing at all is not close.
    #expect(SpotEvaluator.grade(.range(.empty), solution: solution).grade == .leak)
  }

  @Test func rangeMatchAgainstARangeText() throws {
    let base = S.template("fx.ranges.paint-open")
    let template = S.variant(
      base, evaluation: EvaluationSpec(method: .rangeMatch, target: "77+, AJs+, AQo+"))
    let instance = try S.generator.generate(template, seed: 6)
    let solution = try S.evaluator.evaluateSerial(instance, template: template)
    guard case .range(let target) = solution.correct else {
      Issue.record("a range")
      return
    }
    let text = try HandRange(parsing: "77+, AJs+, AQo+")
    for handClass in HandClass.all { #expect(target.weight(of: handClass) == text.weight(of: handClass)) }
    #expect(SpotEvaluator.grade(.range(text), solution: solution).grade == .good)
  }
}

private func cardsOf(_ response: SpotResponse) -> [Card] {
  guard case .cards(let cards) = response else { return [] }
  return cards
}
