import PokerCore
import PokerHost
import Synchronization

/// The human's seat. The UI answers with `submit(_:seq:)`; the host waits in `decide` until it arrives. The host
/// shows the UI an `actionRequested` event before it calls `decide`, so an answer may come first and is kept by seq.
final class LocalHumanSeat: Seat, Sendable {
  private struct State {
    var waiter: (seq: Int, continuation: CheckedContinuation<Action, Never>)?
    var early: [Int: Action] = [:]
    var cancelled = false
  }

  let id: SeatID
  private let state = Mutex(State())

  init(id: SeatID) {
    self.id = id
  }

  func observe(_ event: LoggedEvent) async {}

  func decide(_ request: DecisionRequest) async -> Action {
    let seq = request.seq
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Action, Never>) in
        let immediate: Action? = state.withLock { state in
          if state.cancelled { return .fold }
          if let early = state.early.removeValue(forKey: seq) { return early }
          state.waiter = (seq, continuation)
          return nil
        }
        if let immediate { continuation.resume(returning: immediate) }
      }
    } onCancel: {
      cancel()
    }
  }

  /// From the main actor. Resumes the waiter for `seq`, or keeps the answer for a `decide` that has not started yet.
  func submit(_ action: Action, seq: Int) {
    let continuation: CheckedContinuation<Action, Never>? = state.withLock { state in
      guard !state.cancelled else { return nil }
      if let waiter = state.waiter, waiter.seq == seq {
        state.waiter = nil
        return waiter.continuation
      }
      state.early[seq] = action
      return nil
    }
    continuation?.resume(returning: action)
  }

  /// Folds for the human from now on, so the host can never wait on a closed table.
  func cancel() {
    let continuation: CheckedContinuation<Action, Never>? = state.withLock { state in
      state.cancelled = true
      state.early.removeAll()
      let waiter = state.waiter
      state.waiter = nil
      return waiter?.continuation
    }
    continuation?.resume(returning: .fold)
  }
}
