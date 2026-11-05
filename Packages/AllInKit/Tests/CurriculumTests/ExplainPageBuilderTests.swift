import PokerAnalysis
import PokerCore
import PokerEquity
import Testing

@testable import Curriculum

@Suite struct ExplainPageBuilderTests {
  static let verdict = Verdict(grade: .good, title: "Good call", detail: "Nice.")

  static func page(
    _ b: ExplainTestSupport.Built, explain: ExplainStep?, sandbox: SandboxStep?, next: String = "Next"
  ) async throws -> ExplainPageModel {
    try await ExplainPageBuilder.build(
      explain: explain, sandbox: sandbox, instance: b.instance, template: b.template, verdict: verdict,
      characters: ExplainTestSupport.catalog, villainRanges: b.ranges,
      bind: { $0.replacingOccurrences(of: "{villain}", with: "Bram") },
      nextLabel: next)
  }

  @Test func titleFallbacks() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let step = ExplainStep(title: "Why calling works", explainers: [ExplainerRef(explainer: .potSlices)])
    let sandbox = SandboxStep(title: "Bench", controls: [.villainBet], meters: [.priceNeeded])
    #expect(try await Self.page(b, explain: step, sandbox: sandbox).title == "Why calling works")
    #expect(try await Self.page(b, explain: nil, sandbox: sandbox).title == "Bench")
    #expect(try await Self.page(b, explain: nil, sandbox: nil).title == "Why it works")
    let untitled = SandboxStep(controls: [.villainBet], meters: [.priceNeeded])
    #expect(try await Self.page(b, explain: nil, sandbox: untitled).title == "Why it works")
  }

  @Test func explainersFallBackToTheTemplate() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let fallback = try await Self.page(b, explain: nil, sandbox: nil)
    #expect(fallback.explainers.map(\.kind) == b.template.explain.map(\.explainer))
    let step = ExplainStep(explainers: [ExplainerRef(explainer: .potCounter)])
    let own = try await Self.page(b, explain: step, sandbox: nil)
    #expect(own.explainers.map(\.kind) == [.potCounter])
    #expect(own.verdict == Self.verdict)
  }

  @Test func bindsThinkingChallengeAndCaptions() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let step = ExplainStep(
      explainers: [ExplainerRef(explainer: .potSlices, caption: "What {villain} bets")], thinking: "Ask {villain}.")
    let sandbox = SandboxStep(
      controls: [.villainBet], meters: [.priceNeeded], explainer: .potSlices, challenge: "Make {villain} shove.")
    let page = try await Self.page(b, explain: step, sandbox: sandbox, next: "Onward")
    #expect(page.thinking == "Ask Bram.")
    #expect(page.captions == ["What Bram bets"])
    #expect(page.sandbox?.challenge == "Make Bram shove.")
    #expect(page.sandbox?.explainer == .potSlices)
    #expect(page.nextLabel == "Onward")
  }

  @Test func sandboxSeedAndInitialState() async throws {
    let b = try await ExplainTestSupport.built("fx.potodds.flush-draw")
    let sandbox = SandboxStep(controls: [.heroCards, .board], meters: [.yourChance])
    let page = try await Self.page(b, explain: nil, sandbox: sandbox)
    let setup = try #require(page.sandbox)
    #expect(setup.seed == StableSeed.mix(b.instance.seed, 0x5A))
    #expect(setup.initial == SandboxCalculator.initialState(b.instance, villainRanges: b.ranges))
    #expect(setup.controls == [.heroCards, .board])
    #expect(setup.meters == [.yourChance])
    #expect(try await Self.page(b, explain: nil, sandbox: nil).sandbox == nil)
  }
}
