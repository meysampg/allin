import PokerAI
import PokerCore
import PokerHost
import Testing

@Suite struct SimBotGateTests {
  /// 10,000 deals = 20,000 hands, heads-up duplicate against the uniform random bot.
  @Test(arguments: SimSupport.allIDs)
  func beatsRandom(id: String) async {
    let config = MatchConfig.headsUp(deals: 10_000, seed: SimSupport.randomSeed)
    let (report, seconds) = await SimSupport.timed {
      await HeadlessMatch.headsUpDuplicate(
        SimSupport.contestant(id), SimSupport.random, config: config, shards: SimSupport.shards)
    }
    print(SimSupport.bbPer100Row("\(id) vs random", report.aWinRate, hands: report.hands, seconds: seconds))
    #expect(report.aWinRate.bbPer100 > 0)
  }

  /// 25,000 deals = 50,000 hands; Oryn's 95% CI must lie above zero.
  @Test(arguments: SimSupport.gateIDs)
  func orynBeats(id: String) async {
    let config = MatchConfig.headsUp(deals: 25_000, seed: SimSupport.orynSeed)
    let (report, seconds) = await SimSupport.timed {
      await HeadlessMatch.headsUpDuplicate(
        SimSupport.contestant("oryn"), SimSupport.contestant(id), config: config, shards: SimSupport.shards)
    }
    print(SimSupport.bbPer100Row("oryn vs \(id)", report.aWinRate, hands: report.hands, seconds: seconds))
    #expect(report.aWinRate.ciLow > 0)
  }
}
