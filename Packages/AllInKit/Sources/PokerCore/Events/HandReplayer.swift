/// Why a log could not be replayed.
public enum ReplayError: Error, Sendable, Equatable {
  /// The log lacks `handStarted` or `deckSetup`, so it is not a full host log.
  case incompleteLog
  /// The reducer rejected a logged action.
  case illegalAction(seq: Int)
  /// The replay produced a different event than the log holds at this index.
  case divergence(index: Int)
  /// The log has more or fewer events than the replay produced.
  case lengthMismatch(logged: Int, replayed: Int)
}

/// The outcome of a replay.
public struct HandReplay: Sendable, Hashable {
  /// The state after the last logged action.
  public let state: HandState
  /// The rebuilt host log; equal to the input when the replay verified.
  public let log: EventLog
}

/// Rebuilds a hand from its host log: the start (config, seats, deck) and the applied actions, run through
/// ``HandReducer``. Everything else in the log (deals, pots, awards) is recomputed and compared, so a tampered or
/// stale log is rejected.
public enum HandReplayer {
  /// Replays a full host log and verifies that it reproduces the same events.
  public static func replay(_ log: EventLog) throws -> HandReplay {
    var start: HandStart?
    var setup: (seed: UInt64?, deck: [Card])?
    var actions: [(seq: Int, action: Action)] = []
    for logged in log.events {
      switch logged.event {
      case .handStarted(let s): start = s
      case .deckSetup(let seed, let deck): setup = (seed, deck)
      case .actionTaken(let t): actions.append((logged.seq, t.action))
      default: break
      }
    }
    guard let start, let setup else { throw ReplayError.incompleteLog }

    let stacks = start.seats.map { SeatStack(seat: $0.seat, stack: $0.stack) }
    var step: HandStep
    if let seed = setup.seed {
      step = try HandReducer.start(
        config: start.config, button: start.button, stacks: stacks, seed: seed, burnsCards: start.burnsCards)
    } else {
      step = try HandReducer.start(
        config: start.config, button: start.button, stacks: stacks, deck: setup.deck, burnsCards: start.burnsCards)
    }
    var rebuilt = EventLog(handID: log.handID)
    rebuilt.append(step)
    for (seq, action) in actions {
      do { step = try HandReducer.apply(action, to: step.state) } catch { throw ReplayError.illegalAction(seq: seq) }
      rebuilt.append(step)
    }
    let a = log.events
    let b = rebuilt.events
    for i in 0..<min(a.count, b.count) where a[i] != b[i] { throw ReplayError.divergence(index: i) }
    guard a.count == b.count else { throw ReplayError.lengthMismatch(logged: a.count, replayed: b.count) }
    return HandReplay(state: step.state, log: rebuilt)
  }
}
