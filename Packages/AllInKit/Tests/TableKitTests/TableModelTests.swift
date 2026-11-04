import PokerCore
import Testing

@testable import TableKit

@Suite struct TableModelTests {
  private func model(seatCount: Int = 6) throws -> TableModel {
    let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
    return TableModel(config: config, seats: TableDemo.seats(count: seatCount), heroSeat: 0)
  }

  @Test func stacksMatchTheResultAfterTheLastEvent() throws {
    for seed in UInt64(1)...20 {
      let log = try TableDemo.loggedHand(seed: seed)
      var table = try model()
      for event in log.filtered(for: .seat(0)) { _ = table.apply(event) }
      let snapshot = table.snapshot
      let result = try #require(snapshot.result)
      #expect(snapshot.isHandOver)
      for entry in result.finalStacks {
        #expect(snapshot.seat(entry.seat)?.stack == entry.amount, "seed \(seed) seat \(entry.seat)")
      }
    }
  }

  @Test func chipsAreConservedUntilTheAward() throws {
    for seed in UInt64(1)...20 {
      let log = try TableDemo.loggedHand(seed: seed)
      var table = try model()
      var awarded = false
      for event in log.filtered(for: .seat(0)) {
        if case .potAwarded = event.event { awarded = true }
        _ = table.apply(event)
        if awarded { break }
        let stacks = table.snapshot.seats.reduce(0) { $0 + $1.stack }
        if table.snapshot.handsStarted > 0 {
          #expect(stacks + table.snapshot.potTotal == 6 * 200, "seed \(seed) seq \(event.seq)")
        }
      }
    }
  }

  @Test func boardAndHoleCardsFollowTheStreets() throws {
    for seed in UInt64(1)...20 {
      let log = try TableDemo.loggedHand(seed: seed)
      var table = try model()
      var showdownSeen = false
      for event in log.filtered(for: .seat(0)) {
        _ = table.apply(event)
        let snapshot = table.snapshot
        let expected = [Street.preflop: 0, .flop: 3, .turn: 4, .river: 5][snapshot.street]!
        #expect(snapshot.board.count == expected)
        if case .showdown = event.event { showdownSeen = true }
        if !showdownSeen {
          for seat in snapshot.seats where seat.info.seat != 0 { #expect(seat.holeCards == nil) }
        }
      }
      #expect(!table.snapshot.showdown.isEmpty)
    }
  }

  @Test func hostOnlyEventsGiveNoCues() throws {
    let log = try TableDemo.loggedHand(seed: 3)
    var table = try model()
    var checked = 0
    for event in log.events {
      let before = table.snapshot
      let cues = table.apply(event)
      if event.visibility == .hostOnly {
        #expect(cues.isEmpty)
        #expect(table.snapshot == before)
        checked += 1
      }
    }
    #expect(checked >= 4)
  }

  @Test func headsUpPositionsAreButtonAndBigBlind() throws {
    let log = try TableDemo.loggedHand(seed: 5, seatCount: 2)
    var table = try model(seatCount: 2)
    for event in log.filtered(for: .seat(0)).prefix(1) { _ = table.apply(event) }
    let names = table.snapshot.seats.compactMap(\.positionName).sorted()
    #expect(names == ["BB", "BTN"])
    #expect(table.snapshot.button == 0)
  }

  @Test func sixMaxPositionNamesFollowTheButton() {
    let names = TablePositions.assign(button: 2, seats: Array(0..<6))
    #expect(names[2] == "BTN" && names[3] == "SB" && names[4] == "BB")
    #expect(names[5] == "UTG" && names[0] == "HJ" && names[1] == "CO")
    #expect(TablePositions.names(count: 9).count == 9)
  }

  @Test func cuesFollowTheHandAndLabelsReadWell() throws {
    let log = try TableDemo.loggedHand(seed: 7)
    var table = try model()
    var cues: [TableCue] = []
    var sawAction = false
    for event in log.filtered(for: .seat(0)) {
      cues += table.apply(event)
      if table.snapshot.seats.contains(where: { $0.lastAction != nil }) { sawAction = true }
    }
    #expect(sawAction)
    guard case .newHand(let button, let seats)? = cues.first else {
      Issue.record("first cue should be newHand")
      return
    }
    #expect(button == 0 && seats == Array(0..<6))
    let dealIndex = try #require(cues.firstIndex { if case .dealHoles = $0 { true } else { false } })
    guard case .dealHoles(let order) = cues[dealIndex] else { return }
    #expect(order.count == 12 && order.first == 1)
    #expect(cues.contains { if case .revealHero = $0 { true } else { false } })
    #expect(cues.contains(.collectBets))
    if case .handEnded? = cues.last {} else { Issue.record("last cue should be handEnded") }
  }

  @Test func actionLabels() throws {
    var table = try model()
    let log = try TableDemo.loggedHand(seed: 11)
    var labels: Set<String> = []
    for event in log.filtered(for: .seat(0)) {
      _ = table.apply(event)
      for seat in table.snapshot.seats { if let label = seat.lastAction { labels.insert(label) } }
    }
    #expect(labels.contains("Check") || labels.contains { $0.hasPrefix("Call") })
  }
}
