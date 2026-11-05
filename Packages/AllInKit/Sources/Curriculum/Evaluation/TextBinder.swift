import Foundation
import PokerCore

/// Values for the `{name}` placeholders of content text.
public struct TextBindings: Sendable, Hashable {
  public var values: [String: String]

  public init(_ values: [String: String] = [:]) { self.values = values }

  public subscript(key: String) -> String? {
    get { values[key] }
    set { values[key] = newValue }
  }

  /// `other` wins on shared keys.
  public func merging(_ other: TextBindings) -> TextBindings {
    TextBindings(values.merging(other.values) { _, new in new })
  }
}

public enum TextBindError: Error, Sendable, Equatable, CustomStringConvertible {
  case unresolved(String)
  /// A `{` without its `}`; the character offset of the brace.
  case unterminated(Int)

  public var description: String {
    switch self {
    case .unresolved(let name): "unresolved placeholder '{\(name)}'"
    case .unterminated(let offset): "unterminated '{' at offset \(offset)"
    }
  }
}

/// `{name}` placeholders; `{{` and `}}` are literal braces.
public enum TextBinder {
  private enum Piece {
    case text(Character)
    case placeholder(String)
  }

  private static func parse(_ text: String) throws -> [Piece] {
    let characters = Array(text)
    var pieces: [Piece] = []
    var i = 0
    while i < characters.count {
      let c = characters[i]
      if c == "{" {
        if i + 1 < characters.count, characters[i + 1] == "{" {
          pieces.append(.text("{"))
          i += 2
          continue
        }
        guard let close = characters[(i + 1)...].firstIndex(of: "}") else { throw TextBindError.unterminated(i) }
        pieces.append(.placeholder(String(characters[(i + 1)..<close])))
        i = close + 1
      } else if c == "}", i + 1 < characters.count, characters[i + 1] == "}" {
        pieces.append(.text("}"))
        i += 2
      } else {
        pieces.append(.text(c))
        i += 1
      }
    }
    return pieces
  }

  /// Names in order of first appearance.
  public static func placeholders(in text: String) throws -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for piece in try parse(text) {
      if case .placeholder(let name) = piece, seen.insert(name).inserted { result.append(name) }
    }
    return result
  }

  public static func bind(_ text: String, _ bindings: TextBindings) throws -> String {
    var out = ""
    for piece in try parse(text) {
      switch piece {
      case .text(let c): out.append(c)
      case .placeholder(let name):
        guard let value = bindings[name] else { throw TextBindError.unresolved(name) }
        out += value
      }
    }
    return out
  }

  // MARK: Keys

  public static let commonKeys: Set<String> = [
    "villain", "villainStyle", "villainPosition", "hero", "heroHand", "heroHandName", "position", "board", "street",
    "pot", "potBB", "potBeforeBet", "bet", "toCall", "potIfCall", "stack", "bigBlind", "players", "actor",
  ]

  public static func keys(for method: EvaluationMethod) -> Set<String> {
    switch method {
    case .closedFormEV, .pushFold: commonKeys.union(["priceNeeded", "equity", "evGain", "bestAction", "answer"])
    case .policyEV: commonKeys.union(["evGain", "bestAction", "answer"])
    case .outs: commonKeys.union(["outs", "outsCount"])
    case .nuts: commonKeys.union(["nuts"])
    case .bestFive: commonKeys.union(["bestHand"])
    case .showdownWinner: commonKeys.union(["winner", "winningHand"])
    case .beatsMeCount: commonKeys.union(["beatsMeCount"])
    case .potCount, .legalSizes, .nextToAct, .rangeMatch: commonKeys.union(["answer"])
    }
  }

  /// The common keys of an instance. The villain is the first involved opponent.
  public static func bindings(for instance: SpotInstance, characters: CharacterCatalog) -> TextBindings {
    var b = TextBindings()
    let villainSeat = instance.villainSeats.first
    b["villain"] = villainSeat.flatMap { instance.seatNames[$0] } ?? ""
    b["villainStyle"] = villainSeat.flatMap { instance.seatCharacters[$0] }.flatMap { characters.style($0) } ?? ""
    b["villainPosition"] = villainSeat.flatMap { instance.positions[$0]?.rawValue } ?? ""
    b["hero"] = "You"
    let hole = instance.holeCards[instance.heroSeat] ?? []
    b["heroHand"] = pretty(hole)
    b["heroHandName"] = HandNaming.heroHandName(hole: hole, board: instance.board)
    b["position"] = instance.positions[instance.heroSeat]?.rawValue ?? ""
    b["board"] = pretty(instance.board)
    b["street"] = instance.street.rawValue
    let state = instance.state
    let context = instance.actorContext
    let bigBlind = instance.config.bigBlind
    b["pot"] = String(state.pot)
    b["potBB"] = number(Double(state.pot) / Double(max(bigBlind, 1)))
    let streetBets = context.seats.reduce(0) { $0 + $1.committedThisStreet }
    b["potBeforeBet"] = String(state.pot - streetBets)
    b["bet"] = String(context.legal.currentBet)
    b["toCall"] = String(context.legal.callAmount)
    b["potIfCall"] = String(state.pot + context.legal.callAmount)
    b["stack"] = String(state.seat(instance.heroSeat)?.stack ?? 0)
    b["bigBlind"] = String(bigBlind)
    b["players"] = String(state.liveSeats.count)
    b["actor"] = instance.seatNames[instance.actor] ?? "Seat \(instance.actor + 1)"
    return b
  }

  // MARK: Formatting

  private static let suitSymbols: [Character] = ["♣", "♦", "♥", "♠"]

  /// "A♥ 7♥".
  public static func pretty(_ cards: [Card]) -> String {
    cards.map { String($0.rank.symbol) + String(suitSymbols[Int($0.suit.rawValue)]) }.joined(separator: " ")
  }

  /// "20%".
  public static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

  /// "+1.8 bb", "−0.4 bb", "6.5 bb".
  public static func bb(_ x: Double, signed: Bool) -> String {
    let rounded = (x * 10).rounded() / 10
    let body = number(abs(rounded))
    if rounded > 0 { return (signed ? "+" : "") + body + " bb" }
    if rounded < 0 { return "−" + body + " bb" }
    return "0 bb"
  }

  /// One decimal, no trailing ".0".
  static func number(_ x: Double) -> String {
    let rounded = (x * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
  }
}
