import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

/// Luck is the result minus its all-in expectation, so over many random all-ins it must average to zero.
@Suite struct LuckExpectationTests {
  private func meanLuck(hands: Int, salt: UInt64, preflopAllIn: Bool) throws -> (mean: Double, standardError: Double) {
    let config = try TableConfig(seatCount: 2, smallBlind: 1, bigBlind: 2)
    let stacks = [SeatStack(seat: 0, stack: 200), SeatStack(seat: 1, stack: 200)]
    var sum = 0.0
    var squares = 0.0
    for i in 0..<hands {
      var steps = [
        try HandReducer.start(
          config: config, button: 0, stacks: stacks, seed: StableSeed.mix(salt, UInt64(i)))
      ]
      let script: [Action] = preflopAllIn ? [.allIn, .call] : [.raise(to: 6), .call, .allIn, .call]
      for action in script { steps.append(try HandReducer.apply(action, to: steps[steps.count - 1].state)) }
      let log = EventLog(handID: HandID(UInt64(i + 1)), steps: steps)
      let luck = try LuckCalculator.luck(in: log, seat: 0)
      #expect(luck.wasAllIn)
      sum += luck.luckChips
      squares += luck.luckChips * luck.luckChips
    }
    let n = Double(hands)
    let mean = sum / n
    let variance = max(squares / n - mean * mean, 0) * n / (n - 1)
    return (mean, (variance / n).squareRoot())
  }

  @Test func preflopAllInLuckAveragesToZero() throws {
    let (mean, se) = try meanLuck(hands: 50_000, salt: 0x1CE, preflopAllIn: true)
    print("preflop all-in luck: mean \(mean) chips, SE \(se), z \(mean / se)")
    #expect(abs(mean) < 3 * se)
  }

  @Test func flopAllInLuckAveragesToZero() throws {
    let (mean, se) = try meanLuck(hands: 5_000, salt: 0xF10, preflopAllIn: false)
    print("flop all-in luck: mean \(mean) chips, SE \(se), z \(mean / se)")
    #expect(abs(mean) < 3 * se)
  }
}
