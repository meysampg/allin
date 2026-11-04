import Foundation
import PokerAI
import PokerCore
import PokerHost

/// `allin-tool sim [--games N=2000] [--seed S=1] [--characters DIR] [--only session|vs-random|vs-oryn|style]
/// [--a ID --b ID] [--strict]`: bot-vs-bot simulations. N is the number of duplicate deals (two hands each) in the
/// heads-up sections and the number of hands in the 6-max sections. `--strict` exits 1 when a gate fails
/// (point estimates, so small N is noisy).
enum SimCommand {
  /// 6-max VPIP bands of the gated styles (PLAN section 9).
  static let vpipBands: [String: ClosedRange<Double>] = ["grumli": 0.50...0.60, "vexa": 0.12...0.16]

  private static let sections = ["session", "vs-random", "vs-oryn", "style"]
  private static let sessionIDs = ["grumli", "zib", "vexa", "mott", "bram", "oryn"]

  static func run(_ args: [String]) async throws -> Int32 {
    let parsed = try ToolArguments(args, booleanFlags: ["strict"])
    let games = try parsed.int("games", default: 2000)
    guard games > 0 else { throw ToolError("--games must be positive") }
    let seed = try parsed.uint64("seed", default: 1)
    let directory = parsed.string("characters").map { URL(fileURLWithPath: $0, isDirectory: true) }
    let only = parsed.string("only")
    if let only, !sections.contains(only) {
      throw ToolError("--only expects one of \(sections.joined(separator: ", ")), got '\(only)'")
    }
    let a = parsed.string("a")
    let b = parsed.string("b")
    guard (a == nil) == (b == nil) else { throw ToolError("--a and --b must be given together") }
    let roster = try Roster(directory: directory)
    let context = Context(games: games, seed: seed, roster: roster)
    let started = Date()
    var failures: [String] = []
    if let a, let b {
      failures += try await headsUp(a, b, context)
    } else {
      for section in sections where only == nil || only == section {
        switch section {
        case "session": failures += try await cashSession(context)
        case "vs-random": failures += try await versusRandom(context)
        case "vs-oryn": failures += try await versusOryn(context)
        default: failures += try await style(context)
        }
      }
    }
    print(String(format: "\nwall time %.1f s", Date().timeIntervalSince(started)))
    if failures.isEmpty {
      print("gates: all pass")
      return 0
    }
    print("gates failed: \(failures.joined(separator: "; "))")
    return parsed.has("strict") ? 1 : 0
  }

  // MARK: Setup

  private struct Context {
    let games: Int
    let seed: UInt64
    let roster: Roster
    var shards: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }
  }

  private struct Roster {
    let directory: URL?
    let bots: [String: RosterBot]

    init(directory: URL?) throws {
      self.directory = directory
      let loaded = try directory.map { try BotRoster.load(directory: $0) } ?? BotRoster.load()
      bots = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    func bot(_ id: String) throws -> RosterBot {
      guard let bot = bots[id] else { throw ToolError("unknown character '\(id)'") }
      return bot
    }

    func contestant(_ id: String) throws -> Contestant {
      let bot = try bot(id)
      return Contestant(name: bot.name, strategy: bot.strategy)
    }
  }

  private static let random = Contestant(name: "Random", strategy: UniformRandomStrategy())

  // MARK: Sections

  /// 6-max cash session with real seats: net, VPIP and PFR per seat, and chip conservation.
  private static func cashSession(_ c: Context) async throws -> [String] {
    print("== Cash session: 6-max, \(c.games) hands, 100 bb buy-in, refill below 40 bb ==")
    let table = try TableConfig(seatCount: 6, smallBlind: 50, bigBlind: 100, chipUnit: 10)
    let config = CashSessionConfig(
      table: table, buyIn: 10_000, topUp: .refillBelow(4_000), seed: SeedMix.mix(c.seed, 0x5E55))
    let bots = try sessionIDs.map { try c.roster.bot($0) }
    let seats: [any Seat] = bots.enumerated().map { index, bot in
      BotSeat(id: index, strategy: bot.strategy, seed: SeedMix.mix(c.seed, UInt64(index)))
    }
    let session = try CashSession(config: config, seats: seats)
    var styles = Array(repeating: StyleCounters(), count: bots.count)
    var played = 0
    while played < c.games, let outcome = try await session.playNextHand() {
      for seat in 0..<bots.count { styles[seat].record(outcome.log.events, seat: seat) }
      played += 1
    }
    let summary = try await session.run(hands: 0)  // plays nothing; reads the totals
    print("seat  bot       net bb    bb/100   VPIP   PFR")
    for (index, bot) in bots.enumerated() {
      let net = Double(summary.net[index].amount) / Double(table.bigBlind)
      let rate = played > 0 ? net / Double(played) * 100 : 0
      print(
        "\(index)     \(pad(bot.name, 9))\(num(net, 9, 1))\(num(rate, 10, 1))  \(pct(styles[index].vpip))"
          + "  \(pct(styles[index].pfr))")
    }
    let conserved = summary.stacks.reduce(0) { $0 + $1.amount } == summary.totalBoughtIn.reduce(0) { $0 + $1.amount }
    print("hands played: \(played), chips conserved: \(conserved ? "yes" : "no")\n")
    return conserved ? [] : ["session chips not conserved"]
  }

  private static func versusRandom(_ c: Context) async throws -> [String] {
    print("== Heads-up duplicate vs Random: \(c.games) deals (\(c.games * 2) hands) ==")
    print("bot       bb/100       95% CI                 ")
    var failures: [String] = []
    for id in BotRoster.gateIDs + ["oryn"] {
      let bot = try c.roster.contestant(id)
      let report = await HeadlessMatch.headsUpDuplicate(
        bot, random, config: .headsUp(deals: c.games, seed: SeedMix.mix(c.seed, 0x7A4D)), shards: c.shards)
      let win = report.aWinRate
      let pass = win.bbPer100 > 0
      print("\(pad(bot.name, 9))\(rateColumns(win))  \(pass ? "pass" : "FAIL")")
      if !pass { failures.append("\(id) vs random") }
    }
    print()
    return failures
  }

  private static func versusOryn(_ c: Context) async throws -> [String] {
    print("== Oryn vs each personality: heads-up duplicate, \(c.games) deals (\(c.games * 2) hands) ==")
    print("opponent  Oryn bb/100  95% CI                 ")
    var failures: [String] = []
    let oryn = try c.roster.contestant("oryn")
    for id in BotRoster.gateIDs {
      let opponent = try c.roster.contestant(id)
      let report = await HeadlessMatch.headsUpDuplicate(
        oryn, opponent, config: .headsUp(deals: c.games, seed: SeedMix.mix(c.seed, 0x0E17)), shards: c.shards)
      let win = report.aWinRate
      let pass = win.bbPer100 > 0
      print("\(pad(opponent.name, 9))\(rateColumns(win))  \(pass ? "pass" : "FAIL")")
      if !pass { failures.append("oryn vs \(id)") }
    }
    print()
    return failures
  }

  /// 6-max ring of one personality (seat 0) and five Oryn.
  private static func style(_ c: Context) async throws -> [String] {
    print("== Style: 6-max, personality + 5 Oryn, \(c.games) hands ==")
    print("bot       VPIP    PFR     3bet    band          status")
    let oryn = try c.roster.contestant("oryn")
    let contestants = try BotRoster.gateIDs.map { try c.roster.contestant($0) }
    let seed = SeedMix.mix(c.seed, 0x57E1)
    let hands = c.games
    let reports = await withTaskGroup(of: (Int, RingReport).self) { group in
      for (index, contestant) in contestants.enumerated() {
        let players = [contestant] + Array(repeating: oryn, count: 5)
        group.addTask { (index, HeadlessMatch.ring(players, config: .sixMax(hands: hands, seed: seed))) }
      }
      var out: [(Int, RingReport)] = []
      for await item in group { out.append(item) }
      return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
    var failures: [String] = []
    for (index, id) in BotRoster.gateIDs.enumerated() {
      let counters = reports[index].styles[0]
      var band = "-"
      var status = ""
      if let range = vpipBands[id] {
        band = "\(pct(range.lowerBound, digits: 0))-\(pct(range.upperBound, digits: 0))"
        let pass = range.contains(counters.vpip)
        status = pass ? "pass" : "FAIL"
        if !pass { failures.append("\(id) VPIP \(pct(counters.vpip))") }
      }
      print(
        "\(pad(contestants[index].name, 9))\(pct(counters.vpip))  \(pct(counters.pfr))  "
          + "\(pct(counters.threeBetRate))  \(pad(band, 13)) \(status)")
    }
    print()
    return failures
  }

  /// `--a ID --b ID`: one heads-up duplicate match.
  private static func headsUp(_ aID: String, _ bID: String, _ c: Context) async throws -> [String] {
    let a = try c.roster.contestant(aID)
    let b = try c.roster.contestant(bID)
    print("== \(a.name) vs \(b.name): heads-up duplicate, \(c.games) deals (\(c.games * 2) hands) ==")
    let report = await HeadlessMatch.headsUpDuplicate(
      a, b, config: .headsUp(deals: c.games, seed: c.seed), shards: c.shards)
    print("\(a.name) bb/100  95% CI")
    print("\(rateColumns(report.aWinRate))")
    print("VPIP/PFR  \(a.name): \(pct(report.aStyle.vpip))/\(pct(report.aStyle.pfr))")
    print("VPIP/PFR  \(b.name): \(pct(report.bStyle.vpip))/\(pct(report.bStyle.pfr))")
    return []
  }

  // MARK: Formatting

  private static func rateColumns(_ win: WinRate) -> String {
    "\(num(win.bbPer100, 9, 1))  [\(num(win.ciLow, 7, 1)), \(num(win.ciHigh, 7, 1))]"
  }

  private static func pad(_ text: String, _ width: Int) -> String {
    text.padding(toLength: width, withPad: " ", startingAt: 0)
  }

  private static func num(_ value: Double, _ width: Int, _ digits: Int) -> String {
    let text = String(format: "%.\(digits)f", value)
    return String(repeating: " ", count: max(0, width - text.count)) + text
  }

  private static func pct(_ value: Double, digits: Int = 1) -> String {
    String(format: "%5.\(digits)f%%", value * 100)
  }
}
