import PokerCore

/// One action of one seat, with the context the host gave it.
public struct DecisionPoint: Sendable, Hashable {
  /// 0-based over every action of the hand.
  public let index: Int
  /// Seq of the matching `.actionRequested`.
  public let requestSeq: Int
  /// Seq of the `.actionTaken`.
  public let actionSeq: Int
  /// Exactly what the host passed to `decide`; `holeCards` are the ACTOR's real cards.
  public let context: DecisionContext
  /// The action applied (after any host fallback).
  public let action: Action
  /// Full host state just before the action.
  public let state: HandState

  public init(
    index: Int, requestSeq: Int, actionSeq: Int, context: DecisionContext, action: Action, state: HandState
  ) {
    self.index = index
    self.requestSeq = requestSeq
    self.actionSeq = actionSeq
    self.context = context
    self.action = action
    self.state = state
  }
}

public enum DecisionPointError: Error, Sendable, Equatable {
  case notHostLog
  case illegalAction(seq: Int)
}

public enum DecisionPoints {
  /// Replays a HOST-view log (needs `.handStarted` and `.deckSetup`) with `HandReducer`. Works on unfinished
  /// hands (live coach).
  public static func extract(from events: [LoggedEvent]) throws -> [DecisionPoint] {
    guard let start = start(of: events) else { throw DecisionPointError.notHostLog }
    var deckSetup: (seed: UInt64?, deck: [Card])?
    for logged in events {
      if case .deckSetup(let seed, let deck) = logged.event {
        deckSetup = (seed, deck)
        break
      }
    }
    guard let deckSetup else { throw DecisionPointError.notHostLog }

    let stacks = start.seats.map { SeatStack(seat: $0.seat, stack: $0.stack) }
    var step: HandStep
    if let seed = deckSetup.seed {
      step = try HandReducer.start(
        config: start.config, button: start.button, stacks: stacks, seed: seed, burnsCards: start.burnsCards)
    } else {
      step = try HandReducer.start(
        config: start.config, button: start.button, stacks: stacks, deck: deckSetup.deck,
        burnsCards: start.burnsCards)
    }
    var records = step.records

    var points: [DecisionPoint] = []
    var lastRequestSeq = 0
    for logged in events {
      switch logged.event {
      case .actionRequested:
        lastRequestSeq = logged.seq
      case .actionTaken(let taken):
        let history = ActionEntry.entries(from: records)
        guard let context = DecisionContext.make(from: step.state, for: taken.seat, history: history) else {
          throw DecisionPointError.illegalAction(seq: logged.seq)
        }
        points.append(
          DecisionPoint(
            index: points.count, requestSeq: lastRequestSeq, actionSeq: logged.seq, context: context,
            action: taken.action, state: step.state))
        do {
          step = try HandReducer.apply(taken.action, to: step.state)
        } catch {
          throw DecisionPointError.illegalAction(seq: logged.seq)
        }
        records += step.records
      default:
        break
      }
    }
    return points
  }

  public static func extract(from log: EventLog) throws -> [DecisionPoint] {
    try extract(from: log.events)
  }

  /// The public start of the hand (first `.handStarted`).
  public static func start(of events: [LoggedEvent]) -> HandStart? {
    for logged in events {
      if case .handStarted(let start) = logged.event { return start }
    }
    return nil
  }
}
