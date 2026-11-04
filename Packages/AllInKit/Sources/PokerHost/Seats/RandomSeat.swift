import PokerCore

/// A ``BotSeat`` over ``UniformRandomStrategy``.
public struct RandomSeat: Seat {
  private let bot: BotSeat
  public var id: SeatID { bot.id }

  public init(id: SeatID, seed: UInt64) {
    bot = BotSeat(id: id, strategy: UniformRandomStrategy(), seed: seed)
  }

  public func observe(_ event: LoggedEvent) async { await bot.observe(event) }
  public func decide(_ request: DecisionRequest) async -> Action { await bot.decide(request) }
}
