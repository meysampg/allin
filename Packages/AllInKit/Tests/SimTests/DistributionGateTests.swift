import PokerAI
import PokerCore
import Testing

@Suite struct SimDistributionGateTests {
  /// Random playouts (2-9 seats, random blinds and stacks) driven by the uniform bot; at every decision every
  /// roster bot must return a legal distribution that sums to 1.
  @Test func distributionsAreLegalAndNormalised() throws {
    let bots = BotRoster.gateIDs.map { SimSupport.bot($0) } + [SimSupport.bot("oryn")]
    var rng = SeededRNG(seed: SimSupport.distributionSeed)
    let driver = UniformRandomStrategy()
    var decisions = 0
    for _ in 0..<3_000 {
      let seats = Int.random(in: 2...9, using: &rng)
      let bigBlind = [2, 10, 100].randomElement(using: &rng)!
      let table = try TableConfig(seatCount: seats, smallBlind: bigBlind / 2, bigBlind: bigBlind)
      let stacks = (0..<seats).map { SeatStack(seat: $0, stack: bigBlind * Int.random(in: 5...200, using: &rng)) }
      var step = try HandReducer.start(
        config: table, button: Int.random(in: 0..<seats, using: &rng), stacks: stacks, seed: rng.next())
      var records = step.records
      while let seat = step.state.seatToAct {
        let context = DecisionContext.make(from: step.state, for: seat, history: ActionEntry.entries(from: records))!
        for bot in bots {
          let distribution = bot.strategy.distribution(for: context)
          try distribution.validate(against: context.legal)
          let total = distribution.entries.reduce(0) { $0 + $1.probability }
          #expect(abs(total - 1) < 1e-9, "\(bot.id) sums to \(total)")
          #expect(distribution.entries.allSatisfy { $0.probability >= 0 })
        }
        decisions += 1
        step = try HandReducer.apply(driver.distribution(for: context).sample(using: &rng), to: step.state)
        records += step.records
      }
    }
    print("SIM distributions: \(decisions) decisions x \(bots.count) bots checked")
  }
}
