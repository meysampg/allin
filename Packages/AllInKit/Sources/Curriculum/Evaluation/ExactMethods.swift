import Foundation
import PokerCore
import PokerEquity

/// Methods whose answer follows from the rules: showdown, best five, nuts, pot, legal sizes, next to act.
enum ExactMethods {
  // MARK: Showdown

  static func showdownWinner(_ input: EvalInput) throws -> Draft {
    let instance = input.instance
    let seats = instance.state.liveSeats.sorted()
    guard seats.count >= 2 else { throw SpotEvaluationError.invalid("a showdown needs two players") }
    let board = instance.fullBoard
    var values: [(seat: Int, value: HandValue, cards: [Card])] = []
    for seat in seats {
      let hole = instance.holeCards[seat] ?? []
      values.append((seat, HandEvaluator.evaluate(hole: hole, board: board), hole + board))
    }
    let ranked = values.sorted { $0.value > $1.value }
    let best = ranked[0].value
    let winners = ranked.filter { $0.value == best }.map(\.seat)
    var options = seats.map { AnswerOption(id: "seat:\($0)", label: input.name($0)) }
    options.append(AnswerOption(id: "split", label: "Split"))
    let correct: String
    let answerClass: String
    let winnerName: String
    let answerText: String
    let explanation: String
    if winners.count > 1 {
      correct = "split"
      answerClass = "split"
      winnerName = "Nobody (split pot)"
      answerText = "it is a split pot"
      explanation = "Both players make \(HandDescription.describe(best))."
    } else {
      let second = ranked[1]
      correct = "seat:\(winners[0])"
      winnerName = input.name(winners[0])
      answerText = winners[0] == instance.heroSeat ? "You win" : "\(winnerName) wins"
      explanation = "\(HandDescription.describe(best)) beats \(HandDescription.describe(second.value))"
      if best.category != second.value.category {
        answerClass = "category"
      } else if pairedRanks(ranked[0].cards) == pairedRanks(second.cards),
        [.pair, .twoPair, .threeOfAKind, .fourOfAKind, .fullHouse].contains(best.category)
      {
        answerClass = "kicker"
      } else {
        answerClass = "rank"
      }
    }
    var draft = Draft(correct: .option(correct), answerClass: answerClass)
    draft.options = options
    draft.bindings["winner"] = winnerName
    draft.bindings["winningHand"] = HandDescription.describe(best)
    draft.answerText = answerText
    draft.explanation = explanation
    return draft
  }

  /// The ranks that appear more than once in the best five of `cards`, strongest group first.
  static func pairedRanks(_ cards: [Card]) -> [Rank] {
    var counts: [Rank: Int] = [:]
    for card in HandEvaluator.bestFive(cards) { counts[card.rank, default: 0] += 1 }
    return counts.filter { $0.value >= 2 }
      .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }.map(\.key)
  }

  // MARK: Best five

  static func bestFive(_ input: EvalInput) throws -> Draft {
    let all = input.heroCards + input.board
    guard all.count >= 5 else { throw SpotEvaluationError.invalid("bestFive needs five cards") }
    let value = HandEvaluator.evaluate(all)
    let five = HandEvaluator.bestFive(all)
    let boardPlays = input.board.count == 5 && HandEvaluator.evaluate(input.board) == value
    var draft = Draft(
      correct: .cards(five),
      answerClass: boardPlays ? "boardPlays" : HandCategoryName(value.category).rawValue)
    draft.pick = input.template.question.pick
    draft.bindings["bestHand"] = HandDescription.describe(value)
    draft.answerText = "your best five make \(HandDescription.describe(value))"
    draft.explanation =
      boardPlays
      ? "The board plays: \(TextBinder.pretty(five)) is \(HandDescription.describe(value))."
      : "\(TextBinder.pretty(five)) is \(HandDescription.describe(value))."
    return draft
  }

  // MARK: Nuts

  static func nuts(_ input: EvalInput) throws -> Draft {
    guard (3...5).contains(input.board.count) else { throw SpotEvaluationError.invalid("nuts needs a flop or later") }
    let nuts = BoardAnalyzer.nuts(board: input.board)
    let category = HandCategoryName(nuts.value.category)
    let description = HandDescription.describe(nuts.value)
    let example = nuts.combos.first?.cards ?? []
    var draft: Draft
    if input.template.question.type == .pickHandClass {
      let listed = (input.template.question.options ?? []).compactMap { HandCategoryName(rawValue: $0) }
      var names = listed.isEmpty ? HandCategoryName.allCases : listed
      if !names.contains(category) { names.append(category) }
      draft = Draft(correct: .option(category.rawValue), answerClass: category.rawValue)
      draft.options = names.map { AnswerOption(id: $0.rawValue, label: HandNaming.categoryTitle($0)) }
      draft.answerText = "the nuts here is a \(nuts.value.category.name.lowercased())"
    } else {
      draft = Draft(correct: .cards(example), answerClass: category.rawValue)
      draft.pick = input.template.question.pick ?? 2
      draft.answerText = "the nuts here is \(description)"
    }
    draft.bindings["nuts"] = description
    draft.explanation = "\(description), for example \(TextBinder.pretty(example))."
    return draft
  }

  // MARK: Pot

  static func potCount(_ input: EvalInput) throws -> Draft {
    let pot = input.instance.state.pot
    var draft = Draft(correct: .number(pot), answerClass: input.instance.street.rawValue)
    draft.tolerance = input.template.question.tolerance ?? 0
    draft.bindings["answer"] = String(pot)
    draft.answerText = "the pot is \(pot)"
    draft.explanation = "Blinds and every bet so far add up to \(pot) chips."
    return draft
  }

  // MARK: Legal sizes

  static func legalSizes(_ input: EvalInput) throws -> Draft {
    guard let ask = input.template.evaluation.ask else { throw SpotEvaluationError.invalid("legalSizes needs 'ask'") }
    let legal = input.instance.actorContext.legal
    switch ask {
    case .callCost:
      var draft = Draft(correct: .number(legal.callAmount), answerClass: "callCost")
      draft.tolerance = input.template.question.tolerance ?? 0
      draft.bindings["answer"] = String(legal.callAmount)
      draft.answerText = "calling costs \(legal.callAmount)"
      draft.explanation =
        "You match the biggest bet (\(legal.currentBet)) minus what you already put in (\(legal.committed))."
      return draft
    case .minRaise:
      guard let minTo = legal.minRaiseTo, let allInTo = legal.allInTo else {
        throw SpotEvaluationError.invalid("no raise is possible here")
      }
      let current = legal.currentBet
      let candidates = [
        minTo, current * 2, current + input.bigBlind, minTo + (minTo - current), allInTo,
      ]
      let sizes = Set(candidates.filter { $0 > current && $0 <= allInTo }).sorted()
      let verb = legal.raiseKind == .bet ? "Bet" : "Raise to"
      var draft = Draft(correct: .option("size:\(minTo)"), answerClass: "minRaise")
      draft.options = sizes.map { AnswerOption(id: "size:\($0)", label: "\(verb) \($0)") }
      draft.bindings["answer"] = String(minTo)
      draft.answerText = "the smallest raise is to \(minTo)"
      draft.explanation = "A raise must add at least the last raise: to \(minTo)."
      return draft
    case .actions:
      var set: Set<String> = ["fold"]
      var order: [(String, String)] = [("fold", "Fold")]
      if legal.canCheck {
        set.insert("check")
        order.append(("check", "Check"))
      } else {
        order.append(("check", "Check"))
      }
      if legal.canCall { set.insert("call") }
      order.append(("call", "Call"))
      if legal.raiseKind == .bet { set.insert("bet") }
      order.append(("bet", "Bet"))
      if legal.raiseKind == .raise { set.insert("raise") }
      order.append(("raise", "Raise"))
      if legal.canAllIn { set.insert("allin") }
      order.append(("allin", "All-in"))
      var draft = Draft(correct: .options(set), answerClass: set.sorted().joined(separator: "+"))
      draft.options = order.map { AnswerOption(id: $0.0, label: $0.1) }
      let names = order.filter { set.contains($0.0) }.map { $0.1.lowercased() }
      draft.bindings["answer"] = names.joined(separator: ", ")
      draft.answerText = "you may \(names.joined(separator: ", "))"
      draft.explanation = "Legal here: \(names.joined(separator: ", "))."
      return draft
    }
  }

  // MARK: Next to act

  static func nextToAct(_ input: EvalInput) throws -> Draft {
    let instance = input.instance
    let seats = instance.state.seats.filter { $0.status == .active }.map(\.seat).sorted()
    let actor = instance.actor
    let acted = instance.history.contains { $0.street == instance.street }
    var draft = Draft(
      correct: .option("seat:\(actor)"), answerClass: "\(instance.street.rawValue)-\(acted ? "next" : "first")")
    draft.options = seats.map { AnswerOption(id: "seat:\($0)", label: input.name($0)) }
    draft.bindings["answer"] = input.name(actor)
    draft.answerText = actor == instance.heroSeat ? "you act next" : "\(input.name(actor)) acts next"
    draft.explanation = "Action moves clockwise: \(input.name(actor)) acts next."
    return draft
  }
}
