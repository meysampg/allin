import PokerCore
import PokerHost
import Testing

@testable import PokerAI

@Suite("DecisionPoints")
struct DecisionPointsTests {
  /// A deterministic mix of legal actions chosen from the request alone.
  private static func pick(_ request: DecisionRequest) -> Action {
    let legal = request.legal
    let k = (request.seq &+ Int(request.handID.rawValue)) % 5
    if k == 2, let range = legal.raiseRange {
      return legal.raiseKind == .bet ? .bet(to: range.lowerBound) : .raise(to: range.lowerBound)
    }
    if k == 3, legal.canAllIn { return .allIn }
    if legal.canCheck { return .check }
    return k == 4 ? .fold : (legal.canCall ? .call : .fold)
  }

  private static func play(seed: UInt64) async throws -> (HandOutcome, [ScriptedSeat]) {
    let config = try TableConfig(seatCount: 5, smallBlind: 50, bigBlind: 100, chipUnit: 10)
    let seats = (0..<5).map { ScriptedSeat(id: $0, decide: { pick($0) }) }
    let host = try GameHost(config: config, seats: seats)
    let stacks = (0..<5).map { SeatStack(seat: $0, stack: 5_000) }
    let setup = HandSetup(handID: HandID(seed), button: Int(seed % 5), stacks: stacks, deal: .seed(seed))
    return (try await host.playHand(setup), seats)
  }

  @Test func pointsMatchHostRequests() async throws {
    for seed in UInt64(1)...20 {
      let (outcome, seats) = try await Self.play(seed: seed)
      var requests: [Int: DecisionContext] = [:]
      for seat in seats { for request in await seat.requests { requests[request.seq] = request.context } }

      let points = try DecisionPoints.extract(from: outcome.log)
      let taken = outcome.log.events.filter { if case .actionTaken = $0.event { true } else { false } }
      #expect(points.count == taken.count)
      for (point, event) in zip(points, taken) {
        #expect(point.actionSeq == event.seq)
        #expect(point.context == requests[point.requestSeq])
        guard case .actionTaken(let t) = event.event else { continue }
        #expect(point.action == t.action)
        #expect(point.context.seat == t.seat)
      }
      #expect(points.map(\.index) == Array(0..<points.count))
    }
  }

  @Test func seatLogIsRejected() async throws {
    let (outcome, _) = try await Self.play(seed: 3)
    #expect(throws: DecisionPointError.notHostLog) {
      try DecisionPoints.extract(from: outcome.log.filtered(for: .seat(0)))
    }
  }

  @Test func unfinishedHandWorks() async throws {
    let (outcome, _) = try await Self.play(seed: 5)
    let events = outcome.log.events
    let requestIndexes = events.indices.filter { if case .actionRequested = events[$0].event { true } else { false } }
    #expect(requestIndexes.count >= 3)
    let cut = requestIndexes[2]
    let prefix = Array(events[...cut])
    let points = try DecisionPoints.extract(from: prefix)
    #expect(points.count == 2)
    let full = try DecisionPoints.extract(from: outcome.log)
    #expect(points == Array(full.prefix(2)))
  }
}
