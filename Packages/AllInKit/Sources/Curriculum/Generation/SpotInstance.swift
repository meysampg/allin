import Foundation
import PokerAI
import PokerCore

/// One concrete table situation generated from a template: the deal, the action prefix and the resulting
/// state, with the hero (or another seat) to act.
public struct SpotInstance: Sendable, Hashable {
  public let templateID: String
  public let seed: UInt64
  public let attempt: Int
  public let config: TableConfig
  public let button: Int
  public let heroSeat: Int
  /// Involved opponents in template order.
  public let villainSeats: [Int]
  /// Hero "You"; villains from characters or names; fillers from `fillerNames` or a default pool.
  public let seatNames: [Int: String]
  /// Villains with a character id.
  public let seatCharacters: [Int: String]
  public let positions: [Int: SeatPositionName]
  /// Every dealt seat.
  public let holeCards: [Int: [Card]]
  /// The five board cards the deck would deal.
  public let fullBoard: [Card]
  /// The applied prefix, in order.
  public let actions: [Action]
  /// After the prefix; `seatToAct` is not nil.
  public let state: HandState
  /// Host log of the prefix.
  public let log: EventLog
  /// Public actions of the prefix (the history a `DecisionContext` carries).
  public let history: [ActionEntry]
  /// Hero always; every involved seat when the template reveals all.
  public let reveal: Set<Int>
  /// 16 lowercase hex digits, FNV-1a 64 of the canonical string.
  public let instanceHash: String

  public init(
    templateID: String, seed: UInt64, attempt: Int, config: TableConfig, button: Int, heroSeat: Int,
    villainSeats: [Int], seatNames: [Int: String], seatCharacters: [Int: String],
    positions: [Int: SeatPositionName], holeCards: [Int: [Card]], fullBoard: [Card], actions: [Action],
    state: HandState, log: EventLog, history: [ActionEntry], reveal: Set<Int>, instanceHash: String
  ) {
    self.templateID = templateID
    self.seed = seed
    self.attempt = attempt
    self.config = config
    self.button = button
    self.heroSeat = heroSeat
    self.villainSeats = villainSeats
    self.seatNames = seatNames
    self.seatCharacters = seatCharacters
    self.positions = positions
    self.holeCards = holeCards
    self.fullBoard = fullBoard
    self.actions = actions
    self.state = state
    self.log = log
    self.history = history
    self.reveal = reveal
    self.instanceHash = instanceHash
  }

  public var board: [Card] { state.board }
  public var street: Street { state.street }
  public var actor: Int { state.seatToAct! }

  /// The hero's decision context when the hero is to act.
  public var heroContext: DecisionContext? {
    DecisionContext.make(from: state, for: heroSeat, history: history)
  }

  public var actorContext: DecisionContext {
    DecisionContext.make(from: state, for: actor, history: history)!
  }

  /// The first `.handStarted` of the log.
  public var start: HandStart { DecisionPoints.start(of: log.events)! }
}

/// Text of an action for the canonical hash string.
func actionText(_ action: Action) -> String {
  switch action {
  case .fold: "fold"
  case .check: "check"
  case .call: "call"
  case .bet(let to): "bet\(to)"
  case .raise(let to): "raise\(to)"
  case .allIn: "allin"
  }
}

public enum SpotGenerationError: Error, Sendable, Equatable, CustomStringConvertible {
  /// "could not build fx.x in 2000 tries (board 1720, line 280)"
  case exhausted(templateID: String, tries: Int, reasons: [String: Int])
  case invalidTemplate(String)

  public var description: String {
    switch self {
    case .exhausted(let id, let tries, let reasons):
      let list = reasons.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
      return "could not build \(id) in \(tries) tries (\(list))"
    case .invalidTemplate(let message):
      return "invalid template: \(message)"
    }
  }
}
