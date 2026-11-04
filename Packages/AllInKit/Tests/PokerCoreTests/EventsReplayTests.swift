import Foundation
import Testing

@testable import PokerCore

@Suite struct EventsReplayTests {
  private func scripted() throws -> (log: EventLog, state: HandState) {
    var h = try HandScript.start(
      seatCount: 3, button: 0, stacks: [0: 1000, 1: 1000, 2: 1000],
      holes: [0: "AhAd", 1: "KsKd", 2: "7c2d"], board: "As5d9cJh3s")
    // Seat 0 button; seat 1 SB, seat 2 BB.
    try h.act(.raise(to: 300), .call, .fold)  // preflop
    try h.act(.check, .bet(to: 400), .call)  // flop
    try h.act(.check, .check)  // turn
    try h.act(.allIn, .call)  // river
    #expect(h.state.isComplete)
    return (EventLog(handID: 7, steps: [HandStep(state: h.state, records: h.records)]), h.state)
  }

  @Test func mapperKeepsRecordOrder() throws {
    let played = try EventsRandomHands.play(seed: 3)
    let events = played.log.events.map(\.event)
    guard case .handStarted = events.first, case .deckSetup = events[1], case .handEnded = events.last else {
      Issue.record("unexpected framing")
      return
    }
    #expect(played.log.events.map(\.seq) == Array(0..<events.count))
  }

  @Test func scriptedHandReplaysIdentically() throws {
    let (log, state) = try scripted()
    let replay = try HandReplayer.replay(log)
    #expect(replay.state == state)
    #expect(replay.log == log)
  }

  @Test func randomHandsReplayIdentically() throws {
    for seed in UInt64(1)...300 {
      let played = try EventsRandomHands.play(seed: seed)
      let replay = try HandReplayer.replay(played.log)
      #expect(replay.state == played.state, "seed \(seed)")
      #expect(replay.log.events.map(\.event) == played.log.events.map(\.event), "seed \(seed)")
    }
  }

  @Test func deckSuppliedHandsReplay() throws {
    var h = try HandScript.start(
      button: 0, stacks: [0: 500, 1: 500], holes: [0: "AsKs", 1: "QdQh"], board: "2c7d9hTsJc")
    try h.act(.allIn, .call)
    let log = EventLog(handID: 2, steps: [HandStep(state: h.state, records: h.records)])
    let replay = try HandReplayer.replay(log)
    #expect(replay.state == h.state)
  }

  @Test func partialLogReplaysToSameMidHandState() throws {
    var h = try HandScript.start(button: 0, stacks: [0: 500, 1: 500])
    try h.act(.call)
    let log = EventLog(handID: 3, steps: [HandStep(state: h.state, records: h.records)])
    let replay = try HandReplayer.replay(log)
    #expect(replay.state == h.state && !replay.state.isComplete)
  }

  @Test func tamperedLogIsRejected() throws {
    let played = try EventsRandomHands.play(seed: 11)
    var tampered = EventLog(handID: played.log.handID)
    for e in played.log.events {
      if case .handEnded(let r) = e.event {
        tampered.append(
          .handEnded(
            HandResult(reason: r.reason, board: r.board, finalStacks: r.net, net: r.net, contributions: r.contributions)
          ))
      } else {
        tampered.append(e.event)
      }
    }
    #expect(throws: ReplayError.self) { try HandReplayer.replay(tampered) }
    let hostless = played.log.view(for: .spectator)
    #expect(throws: ReplayError.incompleteLog) { try HandReplayer.replay(hostless) }
  }

  @Test func jsonRoundTrip() throws {
    for seed in UInt64(1)...40 {
      let played = try EventsRandomHands.play(seed: seed)
      let data = try JSONEncoder().encode(played.log)
      let decoded = try JSONDecoder().decode(EventLog.self, from: data)
      #expect(decoded == played.log)
      let replay = try HandReplayer.replay(decoded)
      #expect(replay.state == played.state)
    }
  }

  @Test func deterministicLogPerSeed() throws {
    let a = try EventsRandomHands.play(seed: 99)
    let b = try EventsRandomHands.play(seed: 99)
    #expect(a.log == b.log)
  }
}
