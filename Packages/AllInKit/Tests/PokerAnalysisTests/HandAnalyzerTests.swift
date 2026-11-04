import Foundation
import PokerAI
import PokerCore
import Testing

@testable import PokerAnalysis

@Suite struct HandAnalyzerTests {
  private func input(budget: EVBudget = .test) throws -> HandAnalysisInput {
    let hand = try GoldenHands.reviewDemo()
    var opponents: [Int: any StrategyProvider] = [:]
    var names: [Int: String] = [:]
    var styles: [Int: String] = [:]
    for (seat, id) in hand.characters {
      opponents[seat] = UniformRandomStrategy()
      names[seat] = id.capitalized
      styles[seat] = seat == 1 ? "calling station" : "balanced"
    }
    return HandAnalysisInput(
      log: hand.log, heroSeat: hand.heroSeat, opponents: opponents, heroContinuation: UniformRandomStrategy(),
      seatNames: names, seatStyles: styles, budget: budget)
  }

  @Test func reviewDemoHasFourHeroDecisions() async throws {
    let analysis = try await HandAnalyzer.analyze(try input())
    #expect(analysis.decisions.map(\.street) == [.preflop, .flop, .turn, .river])
    #expect(analysis.decisions.map(\.index) == [0, 1, 2, 3])
    #expect(analysis.headline.contains("decisions:"))
    #expect(analysis.handID == HandID(22))
    #expect(analysis.counts.total == 4)
    #expect(analysis.netChips > 0)
    #expect(analysis.potTotal > 0)
    #expect(analysis.decisionScore != nil)
    #expect(analysis.initialSelection != nil)
    for decision in analysis.decisions {
      #expect(!decision.title.isEmpty && !decision.body.isEmpty && !decision.timelineText.isEmpty)
      #expect(decision.graded.candidates.contains { $0.action == decision.graded.chosen.action })
    }
    // After the flop the focus villain is Grumli, the only opponent left.
    #expect(analysis.decisions[1].focusSeat == 1)
    #expect(analysis.decisions[1].focusName == "Grumli")
    #expect(analysis.decisions[1].focusRangeGrid?.count == 13)
    #expect(analysis.decisions[3].potOddsNeeded == nil)
  }

  @Test func deterministic() async throws {
    let a = try await HandAnalyzer.analyze(try input())
    let b = try await HandAnalyzer.analyze(try input())
    #expect(a == b)
  }

  @Test func encodesAsJSON() async throws {
    let analysis = try await HandAnalyzer.analyze(try input())
    let data = try JSONEncoder().encode(analysis)
    let decoded = try JSONDecoder().decode(HandAnalysis.self, from: data)
    #expect(decoded == analysis)
  }

  @Test func seatFilteredLogIsRejected() async throws {
    var request = try input()
    request.log = request.log.view(for: .seat(0))
    await #expect(throws: DecisionPointError.notHostLog) { try await HandAnalyzer.analyze(request) }
  }

  @Test func missingOpponentStrategyThrows() async throws {
    var request = try input()
    request.opponents[1] = nil
    await #expect(throws: EVError.missingStrategy(seat: 1)) { try await HandAnalyzer.analyze(request) }
  }
}
