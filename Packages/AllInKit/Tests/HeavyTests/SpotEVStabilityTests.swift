import Curriculum
import Foundation
import PokerAI
import PokerCore
import PokerEquity
import Testing

/// The right answer of an EV spot should not depend on the rollout seed.
@Suite struct SpotEVStabilityTests {
  static let library: ContentLibrary = {
    do {
      let catalog = try CharacterCatalog.load(directory: BotCharacter.sourceTreeDirectory)
      return try ContentLibrary.load(files: ContentLibrary.files(at: ContentLibrary.fixtureRoot), characters: catalog)
    } catch { fatalError("\(error)") }
  }()

  /// 100 spots as the factory builds them, each solved again with another rollout seed.
  @Test(arguments: ["fx.value.river-bet-or-check", "fx.reading.quiet-one-bets"])
  func answerClassIsStableAcrossEVSeeds(id: String) async throws {
    let factory = SpotFactory(library: Self.library, budget: .lesson)
    let evaluator = SpotEvaluator(characters: Self.library.characters, budget: .lesson)
    let template = try #require(Self.library.template(id))
    var same = 0
    var flips: [String] = []
    let total = 100
    for k in 0..<total {
      let spot = try await factory.make(templateID: id, seed: UInt64(40_000 + k))
      let i = spot.instance
      // The rollout seed is derived from the instance seed.
      let other = SpotInstance(
        templateID: i.templateID, seed: i.seed ^ 0x5EED_5EED, attempt: i.attempt, config: i.config,
        button: i.button, heroSeat: i.heroSeat, villainSeats: i.villainSeats, seatNames: i.seatNames,
        seatCharacters: i.seatCharacters, positions: i.positions, holeCards: i.holeCards, fullBoard: i.fullBoard,
        actions: i.actions, state: i.state, log: i.log, history: i.history, reveal: i.reveal,
        instanceHash: i.instanceHash)
      let again = try await evaluator.evaluate(other, template: template)
      if again.answerClass == spot.solution.answerClass {
        same += 1
      } else {
        flips.append("\(spot.solution.answerClass)->\(again.answerClass) gap \(spot.solution.gapBB ?? -1)")
      }
    }
    print("EVSTABILITY \(id): \(same)/\(total) equal; flips \(flips.prefix(8))")
    #expect(Double(same) >= 0.9 * Double(total))
  }
}
