import Foundation
import PokerAnalysis
import PokerCore
import PokerEquity

public struct Verdict: Sendable, Hashable {
  public let grade: Grade
  public let title: String
  public let detail: String

  public init(grade: Grade, title: String, detail: String) {
    self.grade = grade
    self.title = title
    self.detail = detail
  }
}

public struct ExplainPageModel: Sendable, Hashable {
  public let title: String
  public let verdict: Verdict
  public let explainers: [ExplainerData]
  /// One per explainer, after `bind`.
  public let captions: [String?]
  public let thinking: String?
  public let sandbox: SandboxSetup?
  public let nextLabel: String

  public init(
    title: String, verdict: Verdict, explainers: [ExplainerData], captions: [String?] = [], thinking: String?,
    sandbox: SandboxSetup?, nextLabel: String
  ) {
    self.title = title
    self.verdict = verdict
    self.explainers = explainers
    self.captions = captions
    self.thinking = thinking
    self.sandbox = sandbox
    self.nextLabel = nextLabel
  }
}

public enum ExplainPageBuilder {
  /// `explainers` = `explain?.explainers ?? template.explain`, each built with `ExplainerBuilder`; thinking,
  /// challenge and captions go through `bind`. Title = explain title, else sandbox title, else "Why it works".
  public static func build(
    explain: ExplainStep?, sandbox: SandboxStep?, instance: SpotInstance, template: SpotTemplate,
    verdict: Verdict, characters: CharacterCatalog, villainRanges: [Int: HandRange],
    bind: @Sendable (String) -> String, nextLabel: String
  ) async throws -> ExplainPageModel {
    let refs = explain?.explainers ?? template.explain
    var data: [ExplainerData] = []
    for ref in refs {
      data.append(
        try await ExplainerBuilder.build(
          ref, instance: instance, template: template, characters: characters, villainRanges: villainRanges))
    }
    var setup: SandboxSetup?
    if let sandbox {
      setup = SandboxSetup(
        title: sandbox.title ?? "Alchemist's Bench", controls: sandbox.controls, meters: sandbox.meters,
        challenge: sandbox.challenge.map(bind), explainer: sandbox.explainer,
        initial: SandboxCalculator.initialState(instance, villainRanges: villainRanges),
        seed: StableSeed.mix(instance.seed, 0x5A))
    }
    return ExplainPageModel(
      title: explain?.title ?? sandbox?.title ?? "Why it works", verdict: verdict, explainers: data,
      captions: refs.map { $0.caption.map(bind) }, thinking: explain?.thinking.map(bind), sandbox: setup,
      nextLabel: nextLabel)
  }
}
