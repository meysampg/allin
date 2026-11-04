import Foundation
import PokerCore

/// A named bot in a match.
public struct Contestant: Sendable {
  public let name: String
  public let strategy: any StrategyProvider
  public init(name: String, strategy: any StrategyProvider) {
    self.name = name
    self.strategy = strategy
  }
}

/// Settings of a headless match. Stacks reset to `startingStack` every hand.
public struct MatchConfig: Sendable, Hashable {
  public var table: TableConfig
  public var startingStack: Int
  /// Duplicate pairs (heads-up) or hands (ring).
  public var deals: Int
  public var seed: UInt64

  public init(table: TableConfig, startingStack: Int, deals: Int, seed: UInt64) {
    self.table = table
    self.startingStack = startingStack
    self.deals = deals
    self.seed = seed
  }

  /// 2 seats, 50/100, chip unit 10, 100 bb.
  public static func headsUp(deals: Int, seed: UInt64) -> MatchConfig {
    MatchConfig(
      table: try! TableConfig(seatCount: 2, smallBlind: 50, bigBlind: 100, chipUnit: 10),
      startingStack: 10_000, deals: deals, seed: seed)
  }

  /// 6 seats, 50/100, chip unit 10, 100 bb.
  public static func sixMax(hands: Int, seed: UInt64) -> MatchConfig {
    MatchConfig(
      table: try! TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100, chipUnit: 10),
      startingStack: 10_000, deals: hands, seed: seed)
  }
}

public struct PlayedHand: Sendable {
  public let result: HandResult
  public let records: [HandRecord]
}

public struct HeadsUpReport: Sendable {
  public let a: String
  public let b: String
  public let hands: Int
  /// b's win rate is the negation.
  public let aWinRate: WinRate
  public let aStyle: StyleCounters
  public let bStyle: StyleCounters
}

public struct RingReport: Sendable {
  public let names: [String]
  public let hands: Int
  public let winRates: [WinRate]
  public let styles: [StyleCounters]
}

public enum HeadlessMatchError: Error, Sendable, Equatable {
  case missingStrategy(seat: Int)
  case tooManyActions
}

/// Plays hands without actors, event logs or timers: reducer, context, distribution, sample.
public enum HeadlessMatch {
  private static let maxActions = 2_000

  /// Synchronous: `HandReducer` + `DecisionContext.make` + distribution + sample. No `EventLog` (avoids the SHA
  /// cost). One action rng, seeded with `actionSeed`, is shared by all seats.
  public static func playHand(
    strategies: [Int: any StrategyProvider], table: TableConfig, button: Int, stacks: [SeatStack],
    deckSeed: UInt64, actionSeed: UInt64
  ) throws -> PlayedHand {
    var actionRng = SeededRNG(seed: actionSeed)
    var step = try HandReducer.start(config: table, button: button, stacks: stacks, seed: deckSeed)
    var records = step.records
    var history: [ActionEntry] = []
    var street = Street.preflop
    var cursor = 0
    var actions = 0
    while let seat = step.state.seatToAct {
      guard actions < maxActions else { throw HeadlessMatchError.tooManyActions }
      guard let strategy = strategies[seat] else { throw HeadlessMatchError.missingStrategy(seat: seat) }
      // Keeps `history` in step with `records` without re-scanning them at every decision.
      while cursor < records.count {
        switch records[cursor] {
        case .streetDealt(let s, _, _): street = s
        case .actionApplied(let a, _):
          history.append(
            ActionEntry(
              street: street, seat: a.seat, action: a.action, chipsAdded: a.chipsAdded,
              committedAfter: a.committedAfter, isAllIn: a.isAllIn))
        default: break
        }
        cursor += 1
      }
      let context = DecisionContext.make(from: step.state, for: seat, history: history)!
      let action = strategy.distribution(for: context).sample(using: &actionRng)
      step = try HandReducer.apply(action, to: step.state)
      records += step.records
      actions += 1
    }
    return PlayedHand(result: step.state.result!, records: records)
  }

  // MARK: Heads-up duplicate

  /// Deal k: deck seed mix(seed, k), one action rng mix(seed, k, 0xAC) shared by both hands of the pair; hand 1
  /// has a at seat 0 (the button), b at seat 1; hand 2 swaps the bots. A sample is a's net over both hands, in bb.
  public static func headsUpDuplicate(_ a: Contestant, _ b: Contestant, config: MatchConfig) -> HeadsUpReport {
    report(a, b, [duplicateShard(a, b, config, deals: 0..<config.deals)])
  }

  /// The same, split into `shards` deal ranges run in a task group and merged in shard order (deterministic).
  public static func headsUpDuplicate(
    _ a: Contestant, _ b: Contestant, config: MatchConfig, shards: Int
  ) async -> HeadsUpReport {
    let count = max(1, min(shards, max(1, config.deals)))
    let parts = await withTaskGroup(of: (Int, DuplicateShard).self) { group in
      for i in 0..<count {
        let range = (i * config.deals / count)..<((i + 1) * config.deals / count)
        group.addTask { (i, duplicateShard(a, b, config, deals: range)) }
      }
      var collected: [(Int, DuplicateShard)] = []
      for await part in group { collected.append(part) }
      return collected.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return report(a, b, parts)
  }

  private struct DuplicateShard: Sendable {
    var stats = RunningStats()
    var aStyle = StyleCounters()
    var bStyle = StyleCounters()
  }

  private static func report(_ a: Contestant, _ b: Contestant, _ parts: [DuplicateShard]) -> HeadsUpReport {
    var total = DuplicateShard()
    for part in parts {
      total.stats.merge(part.stats)
      total.aStyle.merge(part.aStyle)
      total.bStyle.merge(part.bStyle)
    }
    return HeadsUpReport(
      a: a.name, b: b.name, hands: total.stats.count * 2,
      aWinRate: WinRate(stats: total.stats, handsPerSample: 2), aStyle: total.aStyle, bStyle: total.bStyle)
  }

  private static func duplicateShard(
    _ a: Contestant, _ b: Contestant, _ config: MatchConfig, deals: Range<Int>
  ) -> DuplicateShard {
    var shard = DuplicateShard()
    let stacks = (0..<2).map { SeatStack(seat: $0, stack: config.startingStack) }
    let bigBlind = Double(config.table.bigBlind)
    let aFirst: [Int: any StrategyProvider] = [0: a.strategy, 1: b.strategy]
    let bFirst: [Int: any StrategyProvider] = [0: b.strategy, 1: a.strategy]
    for k in deals {
      let deckSeed = mix(config.seed, UInt64(k))
      let actionSeed = mix(config.seed, UInt64(k), 0xAC)
      let first = play(aFirst, config.table, 0, stacks, deckSeed, actionSeed)
      let second = play(bFirst, config.table, 0, stacks, deckSeed, actionSeed)
      let aNet = (first.result.netChips(of: 0) ?? 0) + (second.result.netChips(of: 1) ?? 0)
      shard.stats.add(Double(aNet) / bigBlind)
      shard.aStyle.record(first.records, seat: 0)
      shard.aStyle.record(second.records, seat: 1)
      shard.bStyle.record(first.records, seat: 1)
      shard.bStyle.record(second.records, seat: 0)
    }
    return shard
  }

  // MARK: Ring

  /// players[i] sits at seat i; the button rotates every hand (hand h: button h % n, deck seed mix(seed, h),
  /// action seed mix(seed, h, 0xAC)); stacks reset every hand. The table is resized to the player count if needed.
  public static func ring(_ players: [Contestant], config: MatchConfig) -> RingReport {
    let n = players.count
    var table = config.table
    if table.seatCount != n {
      table = try! TableConfig(
        seatCount: n, smallBlind: table.smallBlind, bigBlind: table.bigBlind, ante: table.ante,
        anteKind: table.anteKind, chipUnit: table.chipUnit)
    }
    var strategies: [Int: any StrategyProvider] = [:]
    for (i, p) in players.enumerated() { strategies[i] = p.strategy }
    let stacks = (0..<n).map { SeatStack(seat: $0, stack: config.startingStack) }
    let bigBlind = Double(table.bigBlind)
    var stats = Array(repeating: RunningStats(), count: n)
    var styles = Array(repeating: StyleCounters(), count: n)
    for h in 0..<config.deals {
      let played = play(
        strategies, table, h % n, stacks, mix(config.seed, UInt64(h)), mix(config.seed, UInt64(h), 0xAC))
      for seat in 0..<n {
        stats[seat].add(Double(played.result.netChips(of: seat) ?? 0) / bigBlind)
        styles[seat].record(played.records, seat: seat)
      }
    }
    return RingReport(
      names: players.map(\.name), hands: config.deals,
      winRates: stats.map { WinRate(stats: $0, handsPerSample: 1) }, styles: styles)
  }

  // MARK: Helpers

  /// A strategy that breaks the rules is a bug in the bot, so it stops the run loudly.
  private static func play(
    _ strategies: [Int: any StrategyProvider], _ table: TableConfig, _ button: Int, _ stacks: [SeatStack],
    _ deckSeed: UInt64, _ actionSeed: UInt64
  ) -> PlayedHand {
    do {
      return try playHand(
        strategies: strategies, table: table, button: button, stacks: stacks, deckSeed: deckSeed,
        actionSeed: actionSeed)
    } catch {
      fatalError("HeadlessMatch: hand failed (deck seed \(deckSeed)): \(error)")
    }
  }

  private static func finalize(_ z: UInt64) -> UInt64 {
    var z = z
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Private seed mixer (SplitMix64 finalizer chain). Stable across processes.
  private static func mix(_ seed: UInt64, _ a: UInt64) -> UInt64 {
    finalize(finalize(seed &+ 0x9E37_79B9_7F4A_7C15) ^ (a &+ 0xD1B5_4A32_D192_ED03))
  }

  private static func mix(_ seed: UInt64, _ a: UInt64, _ b: UInt64) -> UInt64 {
    finalize(mix(seed, a) ^ finalize(b &+ 0x8CB9_2BA7_2F3D_8DD7))
  }
}
