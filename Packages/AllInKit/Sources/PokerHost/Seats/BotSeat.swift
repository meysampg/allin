import PokerCore

/// A seat driven by a ``StrategyProvider``. Stateless: the answer depends only on (seed, handID, seq), so any hand
/// replays alone.
public struct BotSeat: Seat {
  public let id: SeatID
  public let strategy: any StrategyProvider
  public let seed: UInt64
  public let thinkTime: ThinkTime

  public init(id: SeatID, strategy: any StrategyProvider, seed: UInt64, thinkTime: ThinkTime = .instant) {
    self.id = id
    self.strategy = strategy
    self.seed = seed
    self.thinkTime = thinkTime
  }

  public func observe(_ event: LoggedEvent) async {}

  public func decide(_ request: DecisionRequest) async -> Action {
    let decisionSeed = SeedMix.mix(seed, request.handID.rawValue, UInt64(request.seq))
    if !thinkTime.isInstant {
      // A separate stream, so pacing never changes the decision.
      var thinkRNG = SeededRNG(seed: SeedMix.mix(decisionSeed, 0x7448_494E_4B))
      try? await Task.sleep(for: thinkTime.delay(using: &thinkRNG))
    }
    var rng = SeededRNG(seed: decisionSeed)
    return strategy.distribution(for: request.context).sample(using: &rng)
  }
}
