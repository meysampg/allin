import PokerCore
import Testing

@testable import PokerHost

private enum CashFixture {
  static func table(seats: Int = 6) -> TableConfig {
    try! TableConfig(seatCount: seats, smallBlind: 1, bigBlind: 2)
  }

  static func randoms(_ ids: [Int], seed: UInt64 = 7) -> [any Seat] {
    ids.map { RandomSeat(id: $0, seed: seed &+ UInt64($0)) }
  }

  /// Seats that only check or fold, so stacks move by blinds alone and nobody busts.
  static func passives(_ ids: [Int]) -> [any Seat] { ids.map { ScriptedSeat(id: $0, actions: []) } }

  static func config(
    seats: Int = 6, buyIn: Int = 200, topUp: TopUpPolicy = .none, seed: UInt64 = 42, firstButton: Int? = nil
  ) -> CashSessionConfig {
    CashSessionConfig(table: table(seats: seats), buyIn: buyIn, topUp: topUp, seed: seed, firstButton: firstButton)
  }

  static func total(_ chips: [SeatChips]) -> Int { chips.reduce(0) { $0 + $1.amount } }

  static func drain(_ stream: AsyncStream<SessionEvent>) async -> [SessionEvent] {
    var out: [SessionEvent] = []
    for await event in stream { out.append(event) }
    return out
  }
}

@Suite struct CashSessionTests {
  @Test func thousandHandsConserveChips() async throws {
    let session = try CashSession(
      config: CashFixture.config(buyIn: 200, topUp: .refillBelow(80)), seats: CashFixture.randoms(Array(0..<6)))
    let stream = await session.subscribe(viewer: .spectator)
    let summary = try await session.run(hands: 1000)
    #expect(summary.handsPlayed == 1000)
    #expect(await session.handsPlayed == 1000)
    #expect(CashFixture.total(summary.stacks) == CashFixture.total(summary.totalBoughtIn))
    var stacks = Array(repeating: 200, count: 6)
    var bought = 1200
    var boundaries = 0
    for event in await CashFixture.drain(stream) {
      switch event {
      case .toppedUp(let seat, let amount, _):
        stacks[seat] += amount
        bought += amount
      case .handFinished(_, let result):
        for chips in result.finalStacks { stacks[chips.seat] = chips.amount }
        #expect(stacks.reduce(0, +) == bought)
        boundaries += 1
      default: break
      }
    }
    #expect(boundaries == 1000)
    #expect(bought == CashFixture.total(summary.totalBoughtIn))
  }

  @Test func conservationHoldsAtEveryHandBoundary() async throws {
    let session = try CashSession(
      config: CashFixture.config(buyIn: 100, topUp: .refillBelow(40)), seats: CashFixture.randoms(Array(0..<6)))
    let stream = await session.subscribe(viewer: .spectator)
    let summary = try await session.run(hands: 300)
    #expect(summary.handsPlayed == 300)
    var stacks = Array(repeating: 100, count: 6)
    var bought = 600
    for event in await CashFixture.drain(stream) {
      switch event {
      case .toppedUp(let seat, let amount, let after):
        stacks[seat] += amount
        bought += amount
        #expect(stacks[seat] == after)
      case .handFinished(_, let result):
        for chips in result.finalStacks { stacks[chips.seat] = chips.amount }
        #expect(stacks.reduce(0, +) == bought)
      default: break
      }
    }
    #expect(summary.net.reduce(0) { $0 + $1.amount } == summary.stacks.reduce(0) { $0 + $1.amount } - bought)
  }

  @Test func noTopUpEndsWhenOnePlayerHoldsEverything() async throws {
    let session = try CashSession(
      config: CashFixture.config(seats: 3, buyIn: 20), seats: CashFixture.randoms([0, 1, 2]))
    let summary = try await session.run(hands: 100_000)
    #expect(summary.handsPlayed < 100_000)
    #expect(CashFixture.total(summary.stacks) == 60)
    #expect(summary.stacks.filter { $0.amount > 0 }.count == 1)
    #expect(try await session.playNextHand() == nil)
    #expect(summary.totalBoughtIn.allSatisfy { $0.amount == 20 })
  }

  @Test func rebuyWhenBustedRefillsToBuyIn() async throws {
    let session = try CashSession(
      config: CashFixture.config(seats: 2, buyIn: 20, topUp: .rebuyWhenBusted), seats: CashFixture.randoms([0, 1]))
    let summary = try await session.run(hands: 60)
    #expect(summary.handsPlayed == 60)
    #expect(CashFixture.total(summary.stacks) == CashFixture.total(summary.totalBoughtIn))
    #expect(CashFixture.total(summary.totalBoughtIn) > 40)
  }

  @Test func buttonMovesClockwiseAndSkipsSatOutSeats() async throws {
    let session = try CashSession(
      config: CashFixture.config(buyIn: 1000), seats: CashFixture.passives(Array(0..<6)))
    await session.sitOut(2)
    var buttons: [Int] = []
    for _ in 0..<7 {
      if let outcome = try await session.playNextHand() { buttons.append(outcome.finalState.button) }
    }
    #expect(buttons == [0, 1, 3, 4, 5, 0, 1])
  }

  @Test func firstButtonIsHonouredAndFallsForwardWhenEmpty() async throws {
    let session = try CashSession(
      config: CashFixture.config(firstButton: 3), seats: CashFixture.randoms([0, 1, 4]))
    let first = try await session.playNextHand()
    #expect(first?.finalState.button == 4)
    let second = try await session.playNextHand()
    #expect(second?.finalState.button == 0)
  }

  @Test func sameConfigGivesIdenticalResults() async throws {
    func play() async throws -> [HandResult] {
      let session = try CashSession(
        config: CashFixture.config(buyIn: 100, topUp: .rebuyWhenBusted), seats: CashFixture.randoms(Array(0..<4)))
      var results: [HandResult] = []
      for _ in 0..<40 { if let outcome = try await session.playNextHand() { results.append(outcome.result) } }
      return results
    }
    let a = try await play()
    let b = try await play()
    #expect(a.count == 40)
    #expect(a == b)
  }

  @Test func handIDsStartAtFirstHandID() async throws {
    var config = CashFixture.config()
    config.firstHandID = 500
    let session = try CashSession(config: config, seats: CashFixture.randoms([0, 1]))
    #expect(try await session.playNextHand()?.handID == HandID(500))
    #expect(try await session.playNextHand()?.handID == HandID(501))
  }

  @Test func subscribersOnlySeeWhatTheirViewerMay() async throws {
    let session = try CashSession(
      config: CashFixture.config(seats: 3, buyIn: 200), seats: CashFixture.randoms([0, 1, 2]))
    let mine = await session.subscribe(viewer: .seat(0))
    let watcher = await session.subscribe(viewer: .spectator)
    let host = await session.subscribe(viewer: .host)
    _ = try await session.run(hands: 5)

    let mineEvents = await CashFixture.drain(mine)
    let watcherEvents = await CashFixture.drain(watcher)
    let hostEvents = await CashFixture.drain(host)

    func hand(_ events: [SessionEvent]) -> [LoggedEvent] {
      events.compactMap { if case .hand(let e) = $0 { e } else { nil } }
    }
    for e in hand(mineEvents) { #expect(e.visibility == .public || e.visibility == .seat(0)) }
    for e in hand(watcherEvents) { #expect(e.visibility == .public) }
    #expect(hand(mineEvents).contains { $0.visibility == .seat(0) })
    #expect(hand(hostEvents).contains { $0.visibility == .hostOnly })
    #expect(hand(hostEvents).count > hand(mineEvents).count)
    #expect(hand(mineEvents).count > hand(watcherEvents).count)
    for events in [mineEvents, watcherEvents, hostEvents] {
      guard case .ended(let summary) = events.last else {
        Issue.record("last event is not .ended")
        continue
      }
      #expect(summary.handsPlayed == 5)
      #expect(events.filter { if case .handFinished = $0 { true } else { false } }.count == 5)
    }
  }

  @Test func sitOutAndSitInApplyFromTheNextHand() async throws {
    let session = try CashSession(
      config: CashFixture.config(seats: 3, buyIn: 1000), seats: CashFixture.passives([0, 1, 2]))
    let stream = await session.subscribe(viewer: .spectator)
    let first = try await session.playNextHand()
    #expect(first?.finalState.button == 0)
    await session.sitOut(1)
    let second = try await session.playNextHand()
    #expect(second?.result.finalStacks.map(\.seat) == [0, 2])
    await session.sitIn(1)
    let third = try await session.playNextHand()
    #expect(third?.result.finalStacks.map(\.seat) == [0, 1, 2])
    _ = try await session.run(hands: 0)
    let events = await CashFixture.drain(stream)
    #expect(events.contains { if case .satOut(let s) = $0 { s == 1 } else { false } })
    #expect(events.contains { if case .satIn(let s) = $0 { s == 1 } else { false } })
  }

  @Test func fewerThanTwoSeatsPlayingEndsImmediately() async throws {
    let session = try CashSession(config: CashFixture.config(), seats: CashFixture.randoms([0, 1]))
    await session.sitOut(1)
    #expect(try await session.playNextHand() == nil)
    let summary = try await session.run(hands: 10)
    #expect(summary.handsPlayed == 0)
  }
}
