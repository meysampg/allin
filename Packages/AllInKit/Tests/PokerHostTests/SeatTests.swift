import PokerCore
import Testing

@testable import PokerHost

@Suite struct SeatTests {
  @Test func thinkTimeInstantIsZero() {
    var rng = SeededRNG(seed: 1)
    #expect(ThinkTime.instant.delay(using: &rng) == .zero)
  }

  @Test func thinkTimeNeverBelowFloor() {
    var rng = SeededRNG(seed: 2)
    let tiny = ThinkTime(base: .milliseconds(10), jitter: .milliseconds(10), speed: .turbo)
    for _ in 0..<50 { #expect(tiny.delay(using: &rng) >= .milliseconds(120)) }
  }

  @Test func thinkTimeScalesWithSpeed() {
    let base = Duration.milliseconds(1000)
    var a = SeededRNG(seed: 3)
    var b = SeededRNG(seed: 3)
    var c = SeededRNG(seed: 3)
    let relaxed = ThinkTime(base: base, jitter: .zero, speed: .relaxed).delay(using: &a)
    let normal = ThinkTime(base: base, jitter: .zero, speed: .normal).delay(using: &b)
    let turbo = ThinkTime(base: base, jitter: .zero, speed: .turbo).delay(using: &c)
    #expect(relaxed == .milliseconds(1400))
    #expect(normal == .milliseconds(1000))
    #expect(turbo == .milliseconds(300))
    #expect(GameSpeed.allCases.map(\.factor) == [1.4, 1.0, 0.3])
  }

  @Test func thinkTimeJitterStaysInRange() {
    var rng = SeededRNG(seed: 4)
    let t = ThinkTime(base: .milliseconds(500), jitter: .milliseconds(200))
    for _ in 0..<100 {
      let d = t.delay(using: &rng)
      #expect(d >= .milliseconds(500) && d <= .milliseconds(700))
    }
  }

  @Test func botSeatSleepsForItsThinkTime() async throws {
    let config = HostFixture.config(seats: 2)
    let step = try HandReducer.start(
      config: config, button: 0, stacks: HostFixture.stacks([0, 1]), deck: HostFixture.fixedDeck)
    let context = try #require(DecisionContext.make(from: step.state, for: 0))
    let request = DecisionRequest(handID: 1, seq: 5, context: context, deadline: nil)
    let seat = BotSeat(
      id: 0, strategy: UniformRandomStrategy(), seed: 1,
      thinkTime: ThinkTime(base: .milliseconds(120), jitter: .zero, speed: .normal))
    let clock = ContinuousClock()
    let start = clock.now
    let action = await seat.decide(request)
    #expect(clock.now - start >= .milliseconds(110))
    // Pacing never changes the decision.
    let instant = BotSeat(id: 0, strategy: UniformRandomStrategy(), seed: 1)
    #expect(await instant.decide(request) == action)
  }

  @Test func botSeatDependsOnlyOnSeedHandAndSeq() async throws {
    let config = HostFixture.config(seats: 2)
    let step = try HandReducer.start(
      config: config, button: 0, stacks: HostFixture.stacks([0, 1]), deck: HostFixture.fixedDeck)
    let context = try #require(DecisionContext.make(from: step.state, for: 0))
    let seat = RandomSeat(id: 0, seed: 11)
    let request = DecisionRequest(handID: 4, seq: 9, context: context, deadline: nil)
    let first = await seat.decide(request)
    #expect(await seat.decide(request) == first)
    #expect(context.legal.isLegal(first))
    var seen: Set<Action> = []
    for seq in 0..<200 {
      seen.insert(await seat.decide(DecisionRequest(handID: 4, seq: seq, context: context, deadline: nil)))
    }
    #expect(seen.count > 1)
  }

  @Test func scriptedSeatExhaustionChecksOrFolds() async throws {
    let config = HostFixture.config(seats: 2)
    let step = try HandReducer.start(
      config: config, button: 0, stacks: HostFixture.stacks([0, 1]), deck: HostFixture.fixedDeck)
    let facingBlind = try #require(DecisionContext.make(from: step.state, for: 0))
    let seat = ScriptedSeat(id: 0, actions: [.call])
    let request = DecisionRequest(handID: 1, seq: 0, context: facingBlind, deadline: nil)
    #expect(await seat.decide(request) == .call)
    #expect(await seat.decide(request) == .fold)
    #expect(await seat.requests.count == 2)

    let closure = ScriptedSeat(id: 0) { _ in .allIn }
    #expect(await closure.decide(request) == .allIn)
  }
}
