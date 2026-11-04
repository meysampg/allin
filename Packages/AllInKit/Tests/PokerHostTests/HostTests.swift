import PokerCore
import Testing

@testable import PokerHost

@Suite struct GameHostTests {
  /// Reference: drive the reducer with the same script (two calls, then checks) and build the log directly.
  @Test func scriptedHandMatchesReducerLog() async throws {
    let config = HostFixture.config(seats: 3)
    let seats: [any Seat] = [
      ScriptedSeat(id: 0, actions: [.call]), ScriptedSeat(id: 1, actions: [.call]), ScriptedSeat(id: 2, actions: []),
    ]
    let host = try GameHost(config: config, seats: seats)
    let setup = HostFixture.setup(seats: [0, 1, 2])
    let outcome = try await host.playHand(setup)

    var step = try HandReducer.start(
      config: config, button: 0, stacks: setup.stacks, deck: HostFixture.fixedDeck)
    var steps = [step]
    var n = 0
    while step.state.seatToAct != nil {
      let action: Action = n < 2 ? .call : .check
      step = try HandReducer.apply(action, to: step.state)
      steps.append(step)
      n += 1
    }
    let expected = EventLog(handID: setup.handID, steps: steps)
    #expect(outcome.log == expected)
    #expect(outcome.warnings.isEmpty)
    #expect(outcome.result == step.state.result)
    let replay = try HandReplayer.replay(outcome.log)
    #expect(replay.log == outcome.log)
  }

  @Test func seatsSeeOnlyTheirOwnView() async throws {
    let a = ScriptedSeat(id: 0, actions: [.call])
    let b = ScriptedSeat(id: 1, actions: [.call])
    let c = ScriptedSeat(id: 2, actions: [])
    let host = try GameHost(config: HostFixture.config(seats: 3), seats: [a, b, c])
    let outcome = try await host.playHand(HostFixture.setup(seats: [0, 1, 2]))
    for seat in [a, b, c] {
      let seen = await seat.observed
      #expect(seen == outcome.log.filtered(for: .seat(seat.id)))
      #expect(!seen.isEmpty)
      for logged in seen {
        #expect(logged.visibility != .hostOnly)
        if case .holeCardsDealt(let owner, _) = logged.event { #expect(owner == seat.id) }
      }
    }
  }

  @Test func onEventReceivesHostViewInOrder() async throws {
    let host = try GameHost(
      config: HostFixture.config(seats: 2), seats: [ScriptedSeat(id: 0, actions: []), ScriptedSeat(id: 1, actions: [])])
    let box = EventBox()
    let outcome = try await host.playHand(HostFixture.setup(seats: [0, 1])) { box.append($0) }
    #expect(box.events == outcome.log.events)
  }

  @Test func illegalCheckFacingBetBecomesFold() async throws {
    let seat0 = ScriptedSeat(id: 0, actions: [.check])
    let host = try GameHost(config: HostFixture.config(seats: 2), seats: [seat0, ScriptedSeat(id: 1, actions: [])])
    let outcome = try await host.playHand(HostFixture.setup(seats: [0, 1]))
    #expect(outcome.warnings == [.illegalAction(seat: 0, attempted: .check, applied: .fold)])
    #expect(HostFixture.actions(outcome.log) == [.fold])
  }

  @Test func raiseBelowMinimumBecomesCheckWhenFree() async throws {
    // Heads up, button 0 is the small blind: it limps, then the big blind tries a raise below the minimum.
    let seat0 = ScriptedSeat(id: 0, actions: [.call])
    let seat1 = ScriptedSeat(id: 1, actions: [.raise(to: 3)])
    let host = try GameHost(config: HostFixture.config(seats: 2), seats: [seat0, seat1])
    let outcome = try await host.playHand(HostFixture.setup(seats: [0, 1]))
    #expect(outcome.warnings.first == .illegalAction(seat: 1, attempted: .raise(to: 3), applied: .check))
    #expect(HostFixture.actions(outcome.log).prefix(2) == [.call, .check])
  }

  @Test func timeoutAppliesFallbackAndIgnoresLateAnswer() async throws {
    let sleeper = SleepingSeat(id: 0)
    let host = try GameHost(
      config: HostFixture.config(seats: 2), seats: [sleeper, ScriptedSeat(id: 1, actions: [])],
      options: HostOptions(decisionTimeout: .milliseconds(50)))
    let clock = ContinuousClock()
    let start = clock.now
    let outcome = try await host.playHand(HostFixture.setup(seats: [0, 1]))
    // The sleeper waits 10 s; a loose bound keeps this stable under parallel test load.
    #expect(clock.now - start < .seconds(5))
    #expect(outcome.warnings == [.timedOut(seat: 0, applied: .fold)])
    #expect(outcome.result.reason == .uncontested)
  }

  @Test func decisionRequestCarriesTheContext() async throws {
    let config = HostFixture.config(seats: 3)
    let seat0 = ScriptedSeat(id: 0, actions: [.call])
    let host = try GameHost(
      config: config, seats: [seat0, ScriptedSeat(id: 1, actions: []), ScriptedSeat(id: 2, actions: [])],
      options: HostOptions(decisionTimeout: .seconds(5)))
    let setup = HostFixture.setup(seats: [0, 1, 2])
    let outcome = try await host.playHand(setup)

    let step = try HandReducer.start(config: config, button: 0, stacks: setup.stacks, deck: HostFixture.fixedDeck)
    let expected = DecisionContext.make(
      from: step.state, for: 0, history: ActionEntry.entries(from: step.records))
    let request = try #require(await seat0.requests.first)
    #expect(request.context == expected)
    #expect(request.handID == setup.handID)
    #expect(request.deadline == .seconds(5))
    #expect(request.legal == expected?.legal)
    let requested = outcome.log.events.first { if case .actionRequested = $0.event { true } else { false } }
    #expect(request.seq == requested?.seq)
  }

  @Test func botSeatsAreDeterministicAndDependOnHandID() async throws {
    func play(_ ids: Range<UInt64>) async throws -> [[Action]] {
      let seats: [any Seat] = (0..<4).map { BotSeat(id: $0, strategy: UniformRandomStrategy(), seed: 99) }
      let host = try GameHost(config: HostFixture.config(seats: 4), seats: seats)
      var result: [[Action]] = []
      for id in ids {
        let outcome = try await host.playHand(HostFixture.setup(id: id, seats: [0, 1, 2, 3]))
        result.append(HostFixture.actions(outcome.log))
      }
      return result
    }
    let first = try await play(1..<51)
    let again = try await play(1..<51)
    let other = try await play(1001..<1051)
    #expect(first == again)
    #expect(first != other)
  }

  @Test func randomHandsConserveChipsAndTerminate() async throws {
    let seats: [any Seat] = (0..<6).map { RandomSeat(id: $0, seed: 7) }
    let host = try GameHost(config: HostFixture.config(seats: 6), seats: seats)
    for hand in 0..<300 {
      let setup = HostFixture.setup(
        id: UInt64(hand), button: hand % 6, seats: Array(0..<6), deal: .seed(SeedMix.mix(5, UInt64(hand))))
      let outcome = try await host.playHand(setup)
      #expect(outcome.finalState.isComplete)
      #expect(outcome.result.finalStacks.reduce(0) { $0 + $1.amount } == HostFixture.total(setup))
      #expect(outcome.result.net.reduce(0) { $0 + $1.amount } == 0)
      #expect(outcome.warnings.isEmpty)
    }
  }

  @Test func invalidSetupsThrow() async throws {
    let config = HostFixture.config(seats: 3)
    #expect(throws: HostError.duplicateSeat(1)) {
      _ = try GameHost(config: config, seats: [ScriptedSeat(id: 1, actions: []), ScriptedSeat(id: 1, actions: [])])
    }
    #expect(throws: HostError.seatOutOfRange(3)) {
      _ = try GameHost(config: config, seats: [ScriptedSeat(id: 3, actions: [])])
    }
    let host = try GameHost(
      config: config, seats: [ScriptedSeat(id: 0, actions: []), ScriptedSeat(id: 1, actions: [])])
    await #expect(throws: HostError.noSeatFor(2)) {
      _ = try await host.playHand(HostFixture.setup(seats: [0, 1, 2]))
    }
    await #expect(throws: HostError.duplicateSeat(0)) {
      _ = try await host.playHand(HostFixture.setup(seats: [0, 0]))
    }
  }

  @Test func actionLimitThrows() async throws {
    let host = try GameHost(
      config: HostFixture.config(seats: 2),
      seats: [ScriptedSeat(id: 0, actions: [.call]), ScriptedSeat(id: 1, actions: [])],
      options: HostOptions(maxActionsPerHand: 1))
    await #expect(throws: HostError.actionLimitExceeded(1)) {
      _ = try await host.playHand(HostFixture.setup(seats: [0, 1]))
    }
  }

  @Test func seedMixIsStable() {
    #expect(SeedMix.mix(1, 2) == SeedMix.mix(1, 2))
    #expect(SeedMix.mix(1, 2) != SeedMix.mix(2, 1))
    #expect(SeedMix.mix(1, 2, 3) == SeedMix.mix(SeedMix.mix(1, 2), 3))
    // Pinned value: SplitMix64 finaliser of (0 + golden * 1).
    #expect(SeedMix.mix(0, 0) == 0xE220_A839_7B1D_CDAF)
  }
}
