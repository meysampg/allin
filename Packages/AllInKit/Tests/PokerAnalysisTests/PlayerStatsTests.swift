import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct PlayerStatsTests {
  /// Three seats, button 0, small blind seat 1, big blind seat 2 (the seat whose stats are checked).
  private func logs() throws -> [EventLog] {
    let stacks = [200, 200, 200]
    // H1: seat 0 opens, seat 2 calls and wins a showdown; flop call, river bet.
    let h1 = try scriptedLog(
      seatCount: 3, button: 0, stacks: stacks, holes: [0: "Kd Qc", 1: "5h 5d", 2: "Ah Ad"], board: "2c 7d 9s Jh 3c",
      actions: [
        .raise(to: 6), .fold, .call, .check, .bet(to: 6), .call, .check, .check, .bet(to: 10), .call,
      ])
    // H2: seat 0 opens, seat 1 calls, seat 2 3-bets and everyone folds.
    let h2 = try scriptedLog(
      seatCount: 3, button: 0, stacks: stacks, holes: [0: "Kd Qc", 1: "5h 5d", 2: "Ah Ad"], board: "2c 7d 9s Jh 3c",
      actions: [.raise(to: 6), .call, .raise(to: 20), .fold, .fold], handID: 2)
    // H3: folded to the big blind.
    let h3 = try scriptedLog(
      seatCount: 3, button: 0, stacks: stacks, holes: [0: "Kd Qc", 1: "5h 5d", 2: "Ah Ad"], board: "2c 7d 9s Jh 3c",
      actions: [.fold, .fold], handID: 3)
    return [h1, h2, h3]
  }

  @Test func bigBlindStats() throws {
    var stats = PlayerStats()
    for log in try logs() { stats.record(log, seat: 2) }
    #expect(stats.hands == 3)
    #expect(stats.vpip == 2.0 / 3)
    #expect(stats.pfr == 1.0 / 3)
    #expect(stats.threeBetChances == 2)
    #expect(stats.threeBets == 1)
    #expect(stats.threeBet == 0.5)
    #expect(stats.sawFlop == 1)
    #expect(stats.wentToShowdown == 1)
    #expect(stats.wtsd == 1)
    #expect(stats.wonAtShowdown == 1)
    #expect(stats.wsd == 1)
    #expect(stats.postflopAggressive == 1)
    #expect(stats.postflopCalls == 1)
    #expect(stats.aggressionFactor == 1)
    #expect(stats.netChips == 36)
    #expect(stats.netBB == 18)
    #expect(stats.bbPer100 == 600)
  }

  @Test func openerStats() throws {
    var stats = PlayerStats()
    for log in try logs() { stats.record(log, seat: 0) }
    #expect(stats.hands == 3)
    #expect(stats.vpip == 2.0 / 3)
    #expect(stats.pfr == 2.0 / 3)
    // Seat 0 only ever faces a 4-bet chance (it opened), never a 3-bet chance.
    #expect(stats.threeBetChances == 0)
    #expect(stats.threeBets == 0)
    #expect(stats.sawFlop == 1)
    #expect(stats.wentToShowdown == 1)
    #expect(stats.wonAtShowdown == 0)
    #expect(stats.wsd == 0)
    #expect(stats.netChips == -22 - 6)
  }

  @Test func seatFilteredLogGivesTheSameStats() throws {
    var host = PlayerStats()
    var seat = PlayerStats()
    for log in try logs() {
      host.record(log, seat: 2)
      seat.record(log.view(for: .seat(2)), seat: 2)
    }
    #expect(host == seat)
  }

  @Test func emptyStatsAreZero() {
    let stats = PlayerStats()
    #expect(stats.vpip == 0 && stats.wtsd == 0 && stats.wsd == 0 && stats.bbPer100 == 0 && stats.aggressionFactor == 0)
  }
}
