import Foundation
import PokerCore
import PokerEquity

/// Text for `allin-tool content preview`: deterministic for a template, seed and count.
public enum ContentPreviewFormatter {
  /// Generates `count` spots (seeds `StableSeed.mix(seed, i)`) with the serial evaluator and formats each one.
  public static func render(
    library: ContentLibrary, templateID: String, count: Int, seed: UInt64, budget: EvaluationBudget = .validation
  ) throws -> [String] {
    guard let template = library.template(templateID) else { throw SpotFactoryError.unknownTemplate(templateID) }
    let generator = SpotGenerator(characters: library.characters)
    let evaluator = SpotEvaluator(characters: library.characters, budget: budget)
    var lines: [String] = []
    for index in 0..<count {
      let mixed = StableSeed.mix(seed, UInt64(index))
      do {
        let instance = try generator.generate(template, seed: mixed)
        let solution = try evaluator.evaluateSerial(instance, template: template)
        let prompt = try TextBinder.bind(template.prompt, solution.bindings)
        let spot = EvaluatedSpot(template: template, instance: instance, solution: solution, prompt: prompt)
        lines += format(spot, index: index)
      } catch {
        lines.append("#\(index)  seed \(mixed)  error: \(error)")
      }
      if index < count - 1 { lines.append("") }
    }
    return lines
  }

  /// One spot as lines: header, table, cards, line, prompt, answer and (EV methods) the EV list.
  public static func format(_ spot: EvaluatedSpot, index: Int) -> [String] {
    let instance = spot.instance
    let solution = spot.solution
    var lines = ["#\(index)  seed \(instance.seed)  hash \(instance.instanceHash)  \(spot.template.id)"]
    lines.append("  table:  " + tableLine(instance))
    lines.append("  cards:  " + cardsLine(solution))
    lines.append("  line:   " + lineText(instance))
    lines.append("  prompt: " + spot.prompt)
    lines.append("  answer: " + answerText(solution))
    if let evs = solution.evs {
      let list = evs.candidates.map { "\($0.label) \(String(format: "%+.2f", $0.evBB))" }.joined(separator: " | ")
      let gap = solution.gapBB.map { "  gap \(String(format: "%.2f", $0)) bb" } ?? ""
      lines.append("  EV bb:  " + list + gap)
      let options = solution.options.compactMap { option in
        option.evBB.map { "\(option.id) \(String(format: "%+.2f", $0))" }
      }
      if !options.isEmpty { lines.append("  options: " + options.joined(separator: " | ")) }
    }
    return lines
  }

  /// `2p 1/2 · BTN You 182 · BB Bram 96 · pot 24`: players, blinds, each involved seat with its starting stack, pot.
  public static func tableLine(_ instance: SpotInstance) -> String {
    let stacks = Dictionary(uniqueKeysWithValues: instance.start.seats.map { ($0.seat, $0.stack) })
    let seats = ([instance.heroSeat] + instance.villainSeats.filter { $0 != instance.heroSeat }).sorted()
    var parts = ["\(instance.config.seatCount)p \(instance.config.smallBlind)/\(instance.config.bigBlind)"]
    for seat in seats {
      let position = instance.positions[seat]?.rawValue ?? "?"
      let name = instance.seatNames[seat] ?? "Seat \(seat + 1)"
      parts.append("\(position) \(name) \(stacks[seat] ?? 0)")
    }
    parts.append("pot \(instance.state.pot)")
    return parts.joined(separator: " · ")
  }

  static func cardsLine(_ solution: SpotSolution) -> String {
    let board = solution.boardCards.isEmpty ? "(preflop)" : TextBinder.pretty(solution.boardCards)
    let hero = TextBinder.pretty(solution.heroCards)
    let name = solution.bindings["heroHandName"] ?? ""
    return "board \(board) · hero \(hero)" + (name.isEmpty ? "" : " (\(name))")
  }

  /// `pre: BTN call, BB check | flop: BB check, BTN check`.
  public static func lineText(_ instance: SpotInstance) -> String {
    var order: [Street] = []
    var byStreet: [Street: [String]] = [:]
    for entry in instance.history {
      if byStreet[entry.street] == nil { order.append(entry.street) }
      let position = instance.positions[entry.seat]?.rawValue ?? "S\(entry.seat + 1)"
      byStreet[entry.street, default: []].append("\(position) \(actionWords(entry.action))")
    }
    guard !order.isEmpty else { return "(no actions)" }
    return order.map { street in
      (street == .preflop ? "pre" : street.rawValue) + ": " + (byStreet[street] ?? []).joined(separator: ", ")
    }.joined(separator: " | ")
  }

  private static func actionWords(_ action: Action) -> String {
    switch action {
    case .fold: "fold"
    case .check: "check"
    case .call: "call"
    case .bet(let to): "bet \(to)"
    case .raise(let to): "raise \(to)"
    case .allIn: "all-in"
    }
  }

  /// `bet:0.5 (#bet)`, the chosen cards, a number or a range, then the short statement of the answer.
  public static func answerText(_ solution: SpotSolution) -> String {
    let value: String
    switch solution.correct {
    case .option(let id): value = "\(id) (#\(solution.answerClass))"
    case .options(let ids): value = ids.sorted().joined(separator: ", ") + " (#\(solution.answerClass))"
    case .cards(let cards): value = TextBinder.pretty(cards) + " (#\(solution.answerClass))"
    case .number(let n): value = "\(n) (#\(solution.answerClass))"
    case .range: value = "range (#\(solution.answerClass))"
    }
    return solution.answerText.isEmpty ? value : "\(value)  \(solution.answerText)"
  }
}
