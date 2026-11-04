import Foundation
import PokerCore
import Testing

@testable import PokerHost

private func matchRandom(_ fractions: [Double] = [0.5, 1.0]) -> Contestant {
  Contestant(name: "random", strategy: UniformRandomStrategy(sizeFractions: fractions))
}

/// Plays a 3-handed hand (button 0, small blind 1, big blind 2) through scripted actions, then checks it down.
private func matchScripted(_ actions: [Action], checkDown: Bool = false) throws -> [HandStep] {
  let table = try TableConfig(seatCount: 3, smallBlind: 50, bigBlind: 100, chipUnit: 10)
  let stacks = (0..<3).map { SeatStack(seat: $0, stack: 10_000) }
  var steps = [try HandReducer.start(config: table, button: 0, stacks: stacks, seed: 7)]
  for action in actions { steps.append(try HandReducer.apply(action, to: steps[steps.count - 1].state)) }
  while checkDown, steps[steps.count - 1].state.seatToAct != nil {
    steps.append(try HandReducer.apply(.check, to: steps[steps.count - 1].state))
  }
  return steps
}

private func matchRecords(_ steps: [HandStep]) -> [HandRecord] { steps.flatMap(\.records) }

private func matchStyle(_ actions: [Action], seat: Int, checkDown: Bool = false) throws -> StyleCounters {
  var counters = StyleCounters()
  counters.record(matchRecords(try matchScripted(actions, checkDown: checkDown)), seat: seat)
  return counters
}

@Suite struct HeadlessMatchTests {
  @Test func identicalStrategiesMirrorToExactlyZero() {
    let report = HeadlessMatch.headsUpDuplicate(
      matchRandom(), matchRandom(), config: .headsUp(deals: 200, seed: 11))
    #expect(report.hands == 400)
    #expect(report.aWinRate.samples == 200)
    #expect(report.aWinRate.bbPer100 == 0)
    #expect(report.aStyle == report.bStyle)
  }

  @Test func chipsAreConservedInEveryHand() throws {
    let table = try TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100, ante: 10, chipUnit: 10)
    let strategy = UniformRandomStrategy()
    let strategies = Dictionary(uniqueKeysWithValues: (0..<6).map { ($0, strategy as any StrategyProvider) })
    let stacks = (0..<6).map { SeatStack(seat: $0, stack: 10_000) }
    for h in 0..<60 {
      let played = try HeadlessMatch.playHand(
        strategies: strategies, table: table, button: h % 6, stacks: stacks, deckSeed: UInt64(h),
        actionSeed: UInt64(h) &+ 1000)
      #expect(played.result.net.reduce(0) { $0 + $1.amount } == 0)
      #expect(played.result.finalStacks.reduce(0) { $0 + $1.amount } == 60_000)
    }
  }

  @Test func missingStrategyThrows() throws {
    let table = try TableConfig(seatCount: 2, smallBlind: 50, bigBlind: 100, chipUnit: 10)
    let stacks = (0..<2).map { SeatStack(seat: $0, stack: 10_000) }
    #expect(throws: HeadlessMatchError.self) {
      try HeadlessMatch.playHand(
        strategies: [1: UniformRandomStrategy()], table: table, button: 0, stacks: stacks, deckSeed: 1,
        actionSeed: 2)
    }
  }

  @Test func duplicateIsDeterministicAndSeedSensitive() {
    let a = matchRandom([0.5, 1.0])
    let b = matchRandom([0.33, 0.75, 2.0])
    let config = MatchConfig.headsUp(deals: 80, seed: 5)
    let first = HeadlessMatch.headsUpDuplicate(a, b, config: config)
    let second = HeadlessMatch.headsUpDuplicate(a, b, config: config)
    #expect(first.aWinRate == second.aWinRate)
    #expect(first.aStyle == second.aStyle)
    #expect(first.bStyle == second.bStyle)
    let other = HeadlessMatch.headsUpDuplicate(a, b, config: .headsUp(deals: 80, seed: 6))
    #expect(other.aWinRate != first.aWinRate)
  }

  @Test func shardedMatchesUnsharded() async {
    let a = matchRandom([0.5, 1.0])
    let b = matchRandom([0.33, 0.75, 2.0])
    let config = MatchConfig.headsUp(deals: 90, seed: 21)
    let plain = HeadlessMatch.headsUpDuplicate(a, b, config: config)
    for shards in [1, 3, 4, 200] {
      let sharded = await HeadlessMatch.headsUpDuplicate(a, b, config: config, shards: shards)
      #expect(sharded.hands == plain.hands)
      #expect(sharded.aStyle == plain.aStyle)
      #expect(sharded.bStyle == plain.bStyle)
      #expect(sharded.aWinRate.samples == plain.aWinRate.samples)
      #expect(abs(sharded.aWinRate.bbPer100 - plain.aWinRate.bbPer100) < 1e-9)
      #expect(abs(sharded.aWinRate.standardError - plain.aWinRate.standardError) < 1e-9)
    }
  }

  @Test func ringIsZeroSumAndCountsHands() {
    let players = (0..<6).map { Contestant(name: "r\($0)", strategy: UniformRandomStrategy()) }
    let config = MatchConfig.sixMax(hands: 120, seed: 3)
    let report = HeadlessMatch.ring(players, config: config)
    #expect(report.hands == 120)
    #expect(report.names.count == 6)
    #expect(abs(report.winRates.reduce(0) { $0 + $1.bbPer100 }) < 1e-6)
    #expect(report.styles.allSatisfy { $0.hands == 120 })
    let again = HeadlessMatch.ring(players, config: config)
    #expect(again.winRates == report.winRates)
    #expect(again.styles == report.styles)
  }

  // MARK: WinRate

  @Test func runningStatsMatchTheDefinition() {
    var all = RunningStats()
    var left = RunningStats()
    var right = RunningStats()
    let xs: [Double] = [1, 2, 3, 4, 10, -3]
    for (i, x) in xs.enumerated() {
      all.add(x)
      if i < 2 { left.add(x) } else { right.add(x) }
    }
    left.merge(right)
    let mean = xs.reduce(0, +) / 6
    let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 5
    #expect(abs(all.mean - mean) < 1e-12)
    #expect(abs(all.variance - variance) < 1e-12)
    #expect(left.count == 6)
    #expect(abs(left.mean - all.mean) < 1e-12)
    #expect(abs(left.variance - all.variance) < 1e-12)
    #expect(RunningStats().variance == 0)
  }

  @Test func winRateMathOnHandMadeSamples() {
    var stats = RunningStats()
    for x in [1.0, 2.0, 3.0, 4.0] { stats.add(x) }
    let pair = WinRate(stats: stats, handsPerSample: 2)
    #expect(pair.samples == 4)
    #expect(abs(pair.bbPer100 - 125) < 1e-9)
    let se = 100 * (5.0 / 3.0 / 4.0).squareRoot() / 2
    #expect(abs(pair.standardError - se) < 1e-9)
    #expect(abs(pair.ciLow - (125 - 1.96 * se)) < 1e-9)
    #expect(abs(pair.ciHigh - (125 + 1.96 * se)) < 1e-9)
    let single = WinRate(stats: stats, handsPerSample: 1)
    #expect(abs(single.bbPer100 - 250) < 1e-9)
    #expect(abs(single.standardError - 2 * se) < 1e-9)
  }

  // MARK: StyleCounters

  @Test func limp() throws {
    let utg = try matchStyle([.call, .call, .check], seat: 0, checkDown: true)
    #expect(utg.hands == 1 && utg.vpipHands == 1 && utg.pfrHands == 0)
    #expect(utg.threeBetChances == 0 && utg.sawFlop == 1 && utg.wentToShowdown == 1)
    #expect(utg.vpip == 1 && utg.pfr == 0)
  }

  @Test func open() throws {
    let opener = try matchStyle([.raise(to: 300), .fold, .fold], seat: 0)
    #expect(opener.vpipHands == 1 && opener.pfrHands == 1)
    #expect(opener.threeBetChances == 0 && opener.sawFlop == 0 && opener.wentToShowdown == 0)
    let folder = try matchStyle([.raise(to: 300), .fold, .fold], seat: 1)
    #expect(folder.vpipHands == 0 && folder.pfrHands == 0)
    #expect(folder.threeBetChances == 1 && folder.threeBets == 0)
  }

  @Test func threeBet() throws {
    let actions: [Action] = [.raise(to: 300), .raise(to: 900), .fold, .fold]
    let threeBettor = try matchStyle(actions, seat: 1)
    #expect(threeBettor.vpipHands == 1 && threeBettor.pfrHands == 1)
    #expect(threeBettor.threeBetChances == 1 && threeBettor.threeBets == 1)
    #expect(threeBettor.threeBetRate == 1)
    let opener = try matchStyle(actions, seat: 0)
    #expect(opener.pfrHands == 1 && opener.threeBetChances == 0 && opener.threeBets == 0)
    let bigBlind = try matchStyle(actions, seat: 2)
    #expect(bigBlind.threeBetChances == 0)
  }

  @Test func bigBlindWalk() throws {
    let bigBlind = try matchStyle([.fold, .fold], seat: 2)
    #expect(bigBlind.hands == 1)
    #expect(bigBlind.vpipHands == 0 && bigBlind.pfrHands == 0 && bigBlind.sawFlop == 0)
    #expect(bigBlind.wentToShowdown == 0 && bigBlind.threeBetChances == 0)
  }

  @Test func bigBlindCheck() throws {
    let bigBlind = try matchStyle([.call, .call, .check], seat: 2, checkDown: true)
    #expect(bigBlind.vpipHands == 0 && bigBlind.pfrHands == 0)
    #expect(bigBlind.sawFlop == 1 && bigBlind.wentToShowdown == 1)
    let smallBlind = try matchStyle([.call, .call, .check], seat: 1, checkDown: true)
    #expect(smallBlind.vpipHands == 1)
  }

  @Test func foldedBeforeFlopDoesNotSeeIt() throws {
    let step = try matchScripted([.call, .fold, .check], checkDown: true)
    var small = StyleCounters()
    small.record(matchRecords(step), seat: 1)
    var button = StyleCounters()
    button.record(matchRecords(step), seat: 0)
    #expect(small.sawFlop == 0 && small.wentToShowdown == 0)
    #expect(button.sawFlop == 1 && button.wentToShowdown == 1)
  }

  @Test func eventVariantMatchesRecordVariant() throws {
    let scripts: [[Action]] = [
      [.call, .call, .check], [.raise(to: 300), .fold, .fold], [.raise(to: 300), .raise(to: 900), .fold, .fold],
      [.fold, .fold],
    ]
    for script in scripts {
      let steps = try matchScripted(script, checkDown: true)
      let records = matchRecords(steps)
      var log = EventLog(handID: 1)
      for step in steps { log.append(step) }
      let events = log.events
      for seat in 0..<3 {
        var fromRecords = StyleCounters()
        fromRecords.record(records, seat: seat)
        var fromEvents = StyleCounters()
        fromEvents.record(events, seat: seat)
        #expect(fromRecords == fromEvents)
      }
    }
  }

  @Test func mergeAddsCounters() throws {
    var total = try matchStyle([.raise(to: 300), .fold, .fold], seat: 0)
    total.merge(try matchStyle([.call, .call, .check], seat: 0, checkDown: true))
    #expect(total.hands == 2 && total.vpipHands == 2 && total.pfrHands == 1)
    #expect(total.vpip == 1 && total.pfr == 0.5)
  }
}
