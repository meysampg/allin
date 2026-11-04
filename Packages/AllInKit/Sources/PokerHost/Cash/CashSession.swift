import PokerCore

/// A multi-hand cash game on top of ``GameHost``: button, top-ups, bust/sit-out and subscriber streams.
public actor CashSession {
  private let config: CashSessionConfig
  private let host: GameHost
  private let seatIDs: [Int]
  private var stackBySeat: [Int: Int]
  private var boughtIn: [Int: Int]
  private var sittingOut: Set<Int> = []
  private var button: Int?
  private var played = 0
  private var subscribers: [(viewer: Viewer, continuation: AsyncStream<SessionEvent>.Continuation)] = []

  public init(config: CashSessionConfig, seats: [any Seat]) throws {
    self.config = config
    self.host = try GameHost(config: config.table, seats: seats, options: config.hostOptions)
    let ids = seats.map(\.id).sorted()
    self.seatIDs = ids
    self.stackBySeat = Dictionary(uniqueKeysWithValues: ids.map { ($0, config.buyIn) })
    self.boughtIn = Dictionary(uniqueKeysWithValues: ids.map { ($0, config.buyIn) })
  }

  /// Register before `run`/`playNextHand`. Spectator: `.spectator`; the human's view: `.seat(humanSeat)`.
  public func subscribe(viewer: Viewer) -> AsyncStream<SessionEvent> {
    let (stream, continuation) = AsyncStream<SessionEvent>.makeStream(bufferingPolicy: .unbounded)
    subscribers.append((viewer, continuation))
    return stream
  }

  /// Applies from the next hand.
  public func sitOut(_ seat: Int) {
    guard seatIDs.contains(seat), sittingOut.insert(seat).inserted else { return }
    send(.satOut(seat: seat))
  }

  /// Applies from the next hand.
  public func sitIn(_ seat: Int) {
    guard seatIDs.contains(seat), sittingOut.remove(seat) != nil else { return }
    send(.satIn(seat: seat))
  }

  public var stacks: [SeatChips] { seatIDs.map { SeatChips(seat: $0, amount: stackBySeat[$0] ?? 0) } }
  public var handsPlayed: Int { played }

  /// nil when fewer than two seats can play.
  public func playNextHand() async throws -> HandOutcome? {
    applyTopUps()
    let eligible = seatIDs.filter { !sittingOut.contains($0) && (stackBySeat[$0] ?? 0) > 0 }
    guard eligible.count >= 2 else { return nil }

    let nextButton = Self.nextSeat(from: button, in: eligible, inclusive: button == nil, first: config.firstButton)
    let n = UInt64(played)
    let setup = HandSetup(
      handID: HandID(config.firstHandID + n), button: nextButton,
      stacks: eligible.map { SeatStack(seat: $0, stack: stackBySeat[$0] ?? 0) },
      deal: .seed(SeedMix.mix(config.seed, n)))
    let targets = subscribers
    let outcome = try await host.playHand(setup) { event in
      for target in targets where target.viewer.canSee(event.visibility) {
        target.continuation.yield(.hand(event))
      }
    }
    button = nextButton
    played += 1
    for chips in outcome.result.finalStacks { stackBySeat[chips.seat] = chips.amount }
    send(.handFinished(outcome.handID, outcome.result))
    return outcome
  }

  /// Plays up to `hands` hands, stops early when fewer than two can play, finishes all streams.
  public func run(hands: Int) async throws -> SessionSummary {
    defer { finishStreams() }
    var remaining = hands
    while remaining > 0, try await playNextHand() != nil { remaining -= 1 }
    let summary = summary()
    send(.ended(summary))
    return summary
  }

  // MARK: - Private

  private func summary() -> SessionSummary {
    SessionSummary(
      handsPlayed: played, stacks: stacks,
      totalBoughtIn: seatIDs.map { SeatChips(seat: $0, amount: boughtIn[$0] ?? 0) })
  }

  private func send(_ event: SessionEvent) {
    for subscriber in subscribers { subscriber.continuation.yield(event) }
  }

  private func finishStreams() {
    for subscriber in subscribers { subscriber.continuation.finish() }
  }

  /// Top-ups for seats that are sitting in, then auto sit-out for seats that are still broke.
  private func applyTopUps() {
    for seat in seatIDs where !sittingOut.contains(seat) {
      let stack = stackBySeat[seat] ?? 0
      let refill: Bool
      switch config.topUp {
      case .none: refill = false
      case .refillBelow(let threshold): refill = stack < threshold && stack < config.buyIn
      case .rebuyWhenBusted: refill = stack == 0
      }
      if refill {
        let amount = config.buyIn - stack
        stackBySeat[seat] = config.buyIn
        boughtIn[seat, default: 0] += amount
        send(.toppedUp(seat: seat, amount: amount, stackAfter: config.buyIn))
      } else if stack == 0 {
        sittingOut.insert(seat)
        send(.satOut(seat: seat))
      }
    }
  }

  /// The next eligible seat clockwise after `previous`. Without a previous button, `first` (or the lowest seat)
  /// is taken when eligible, else the next eligible one after it.
  private static func nextSeat(from previous: Int?, in eligible: [Int], inclusive: Bool, first: Int?) -> Int {
    let start = previous ?? first ?? (eligible.first ?? 0)
    if inclusive, eligible.contains(start) { return start }
    return eligible.first { $0 > start } ?? eligible[0]
  }
}
