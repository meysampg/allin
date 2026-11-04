import Foundation
import PokerAI
import PokerAnalysis
import PokerCore
import Testing

@Suite struct ReviewDemoGradeTests {
  /// The demo hand with the real roster and `.demo` budget gives `expectedGrades` (see `GoldenHands.reviewDemo`).
  @Test func reviewDemoMatchesWireframe() async throws {
    let hand = try GoldenHands.reviewDemo()
    let characters = try BotCharacter.loadAll(directory: BotCharacter.sourceTreeDirectory)
    let roster = try BotRoster.load()
    var opponents: [Int: any StrategyProvider] = [:]
    var names: [Int: String] = [:]
    var styles: [Int: String] = [:]
    for (seat, id) in hand.characters {
      let bot = try #require(roster.first { $0.id == id })
      opponents[seat] = bot.strategy
      names[seat] = bot.name
      styles[seat] = characters.first { $0.id == id }?.style
    }
    let input = HandAnalysisInput(
      log: hand.log, heroSeat: hand.heroSeat, opponents: opponents, heroContinuation: BaselineStrategy(),
      seatNames: names, seatStyles: styles, budget: .demo)
    let clock = ContinuousClock()
    var analysis: HandAnalysis?
    let elapsed = try await clock.measure { analysis = try await HandAnalyzer.analyze(input) }
    let result = try #require(analysis)
    print("Review demo analysis (.demo budget): \(elapsed)")
    print("Headline: \(result.headline); luck: \(result.luckText ?? "none"); score: \(result.decisionScore ?? -1)")
    for decision in result.decisions {
      let evs = decision.graded.candidates.map { "\($0.shortLabel) \(String(format: "%.2f", $0.evBB))" }
      print(
        "  \(decision.street.rawValue): \(decision.timelineText) | chose \(decision.graded.chosen.shortLabel), "
          + "best \(decision.graded.best.shortLabel), loss \(String(format: "%.2f", decision.graded.evLossBB)) "
          + "tol \(String(format: "%.2f", decision.graded.toleranceBB)) | \(evs.joined(separator: ", "))")
      print("    \(decision.title) \(decision.body)")
    }
    #expect(result.decisions.map(\.graded.grade) == hand.expectedGrades)
  }
}
