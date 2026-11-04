import PokerAI
import PokerCore
import PokerHost
import Testing

@Suite struct SimSessionSmokeTests {
  private static func run() async throws -> SessionSummary {
    let table = try TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100, chipUnit: 10)
    let config = CashSessionConfig(
      table: table, buyIn: 10_000, topUp: .refillBelow(4_000), seed: SimSupport.sessionSeed)
    let ids = ["grumli", "zib", "vexa", "mott", "bram", "oryn"]
    let seats: [any Seat] = ids.enumerated().map { index, id in
      BotSeat(id: index, strategy: SimSupport.bot(id).strategy, seed: SimSupport.sessionSeed &+ UInt64(index))
    }
    return try await CashSession(config: config, seats: seats).run(hands: 2_000)
  }

  @Test func botsPlayAConservingDeterministicSession() async throws {
    let first = try await Self.run()
    let second = try await Self.run()
    #expect(first.handsPlayed == 2_000)
    #expect(first.stacks.reduce(0) { $0 + $1.amount } == first.totalBoughtIn.reduce(0) { $0 + $1.amount })
    #expect(first == second)
  }
}
