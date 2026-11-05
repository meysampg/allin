import CoreGraphics
import Curriculum
import Foundation
import OSLog
import Observation
import PokerAnalysis
import PokerCore
import PokerEquity
import TableKit

/// Plays one lesson or drill: builds the page list, solves spots off the main actor (one page ahead), grades the
/// answers, records progress and owns the table scene shared by every spot page.
@MainActor @Observable
final class LessonController {
  struct StepInfo: Equatable {
    let index: Int
    let total: Int
    let kind: LessonStepKind
    var label: String { "Step \(index) / \(total)" }
  }

  /// One spot shown on the table.
  struct SpotPage: Equatable {
    let spot: EvaluatedSpot
    let showsCoach: Bool
    let coachText: String?
    /// "Spot 2 / 3" or "Rep 4 / 10".
    let repLabel: String?
  }

  struct Summary: Equatable {
    let stars: Int
    let puzzleGood: Bool?
    let applyGood: Int
    let applyTotal: Int
    let hintsUsed: Int
  }

  enum Phase: Equatable {
    case preparing
    case question(SpotPage)
    case feedback(SpotPage, SpotGrade)
    case explain(ExplainPageModel)
    case summary(Summary)
    case failed(String)
  }

  /// What the SwiftUI layer draws over the table.
  struct TableOverlay: Equatable {
    let villainTag: String?
    let villainSeat: Int?
    let heroSeat: Int
    let seatCount: Int
    let potText: String
  }

  let request: LessonRequest
  let title: String
  let isDrill: Bool
  let scene: TableScene
  private(set) var step: StepInfo
  private(set) var phase: Phase = .preparing
  private(set) var hintShown = false
  private(set) var hintsUsed = 0
  /// "Step 2 / 5", or "Drill".
  private(set) var stepLabel: String
  /// 0...1, for the progress bar.
  private(set) var progress: Double = 0
  private(set) var overlay: TableOverlay?
  /// Changes with every page, so views can drop their drafts.
  private(set) var pageID = 0
  /// False for the hook and for drills.
  private(set) var hintCostsStar = true

  @ObservationIgnored private let model: AppModel
  @ObservationIgnored private let library: ContentLibrary?
  @ObservationIgnored private let lesson: Lesson?
  @ObservationIgnored private let drill: Drill?
  @ObservationIgnored private var pages: [Page] = []
  @ObservationIgnored private var pageIndex = 0
  @ObservationIgnored private var token = 0
  @ObservationIgnored private var replay = 0
  @ObservationIgnored private var started = false
  @ObservationIgnored private var spotTasks: [Int: Task<EvaluatedSpot, Error>] = [:]
  @ObservationIgnored private var explainTasks: [Int: Task<ExplainPageModel, Error>] = [:]
  @ObservationIgnored private var avoid: Set<String> = []
  @ObservationIgnored private let sessionSalt: UInt64
  @ObservationIgnored private let factory: SpotFactory?
  @ObservationIgnored private var lastAnswered: (spot: EvaluatedSpot, grade: SpotGrade)?
  @ObservationIgnored private var lastFeedback: (index: Int, page: SpotPage, grade: SpotGrade)?
  @ObservationIgnored private var hintCounted = false
  @ObservationIgnored private var questionStart = ContinuousClock.now
  @ObservationIgnored private var puzzleGood: Bool?
  @ObservationIgnored private var applyGood = 0
  @ObservationIgnored private var applyTotal = 0
  @ObservationIgnored private var decisionsGood = 0
  @ObservationIgnored private var decisionsTotal = 0

  private static let log = Logger(subsystem: "app.allin", category: "LessonController")

  /// A page of the player: a spot, or the merged explain and sandbox page.
  private struct Page {
    enum Kind {
      case hook(SpotStep)
      case puzzle(SpotStep)
      case explain(ExplainStep?, SandboxStep?)
      case apply(ApplyStep, rep: Int)
      case drillRep(template: String, rep: Int)
    }

    let kind: Kind
    /// 1-based index of the lesson step the page belongs to (the explain step for a merged page).
    let stepIndex: Int
    /// The last lesson step the page covers.
    let lastStep: Int
    let repLabel: String?

    var templateID: String? {
      switch kind {
      case .hook(let step), .puzzle(let step): step.spot
      case .apply(let step, _): step.spot
      case .drillRep(let template, _): template
      case .explain: nil
      }
    }

    var isSpot: Bool { templateID != nil }

    var repIndex: Int {
      switch kind {
      case .apply(_, let rep), .drillRep(_, let rep): rep
      default: 0
      }
    }
  }

  init(request: LessonRequest, model: AppModel) {
    self.request = request
    self.model = model
    let library = model.curriculum.library
    self.library = library
    var lesson: Lesson?
    var drill: Drill?
    switch request.content {
    case .lesson(let id): lesson = library?.lesson(id)
    case .drill(let id): drill = library?.drill(id)
    }
    self.lesson = lesson
    self.drill = drill
    isDrill = drill != nil
    title = lesson?.title ?? drill?.title ?? "Lesson"
    let fast = model.launch.fast || model.launch.isDemo
    factory = library.map { SpotFactory(library: $0, budget: fast ? .test : .lesson) }
    sessionSalt = model.newSessionSeed()
    let first = StepInfo(index: 1, total: max(1, lesson?.steps.count ?? drill?.reps ?? 1), kind: .hook)
    step = first
    stepLabel = drill != nil ? "Drill" : first.label

    let timing = AnimationTiming(
      speedFactor: 1, reduceMotion: model.effectiveReduceMotion(system: false))
    let options = TableSceneOptions(
      timing: timing, hud: .basic, fourColorDeck: model.settings.fourColorDeck, driver: .immediate, mode: .spot)
    scene = TableScene(resolver: model.themeResolver, options: options, soundBank: nil)
  }

  // MARK: Lifecycle

  func start() {
    guard !started else { return }
    started = true
    avoid = model.curriculum.avoidHashes(now: Date())
    pages = buildPages()
    guard !pages.isEmpty else {
      phase = .failed("This lesson has nothing to play yet.")
      return
    }
    var first = 0
    if let startStep = request.startStep, lesson != nil {
      first = pages.firstIndex { $0.lastStep >= startStep } ?? 0
    }
    token += 1
    let current = token
    let firstIndex = first
    Task { [weak self] in
      guard let self else { return }
      if !pages[firstIndex].isSpot, !(await prepareSkippedSpot(before: firstIndex)) { return }
      guard current == token else { return }
      go(to: firstIndex)
    }
  }

  func close() {
    stop()
    model.router.closeLesson()
  }

  func stop() {
    token += 1
    for task in spotTasks.values { task.cancel() }
    for task in explainTasks.values { task.cancel() }
    spotTasks = [:]
    explainTasks = [:]
  }

  /// Plays the lesson again with new spots.
  func restart() {
    stop()
    replay += 1
    started = false
    hintsUsed = 0
    hintShown = false
    hintCounted = false
    puzzleGood = nil
    applyGood = 0
    applyTotal = 0
    decisionsGood = 0
    decisionsTotal = 0
    lastAnswered = nil
    lastFeedback = nil
    phase = .preparing
    start()
  }

  // MARK: Player actions

  func submit(_ response: SpotResponse) {
    guard case .question(let page) = phase else { return }
    let grade = SpotEvaluator.grade(response, solution: page.spot.solution)
    record(page, grade: grade)
    lastAnswered = (page.spot, grade)
    lastFeedback = (pageIndex, page, grade)
    phase = .feedback(page, grade)
    prepareExplain(after: pageIndex)
  }

  func showHint() {
    guard case .question = phase, !hintShown else { return }
    hintShown = true
    if hintCostsStar, !hintCounted {
      hintCounted = true
      hintsUsed += 1
    }
  }

  /// Feedback or explain page: on to the next page, or to the summary after the last one.
  func next() {
    switch phase {
    case .feedback, .explain: advance()
    default: break
    }
  }

  func backFromExplain() {
    guard case .explain = phase else { return }
    guard let feedback = lastFeedback else {
      close()
      return
    }
    token += 1
    pageIndex = feedback.index
    updateStep(for: pages[feedback.index])
    phase = .feedback(feedback.page, feedback.grade)
  }

  /// Gives the failed lesson another go.
  func retry() {
    guard case .failed = phase else { return }
    restart()
  }

  // MARK: Pages

  private func buildPages() -> [Page] {
    if let lesson {
      var result: [Page] = []
      var i = 0
      while i < lesson.steps.count {
        let index = i + 1
        switch lesson.steps[i] {
        case .hook(let step):
          result.append(Page(kind: .hook(step), stepIndex: index, lastStep: index, repLabel: nil))
        case .puzzle(let step):
          result.append(Page(kind: .puzzle(step), stepIndex: index, lastStep: index, repLabel: nil))
        case .explain(let explain):
          if i + 1 < lesson.steps.count, case .sandbox(let sandbox) = lesson.steps[i + 1] {
            result.append(Page(kind: .explain(explain, sandbox), stepIndex: index, lastStep: index + 1, repLabel: nil))
            i += 1
          } else {
            result.append(Page(kind: .explain(explain, nil), stepIndex: index, lastStep: index, repLabel: nil))
          }
        case .sandbox(let sandbox):
          result.append(Page(kind: .explain(nil, sandbox), stepIndex: index, lastStep: index, repLabel: nil))
        case .apply(let apply):
          for rep in 0..<apply.count {
            result.append(
              Page(
                kind: .apply(apply, rep: rep), stepIndex: index, lastStep: index,
                repLabel: "Spot \(rep + 1) / \(apply.count)"))
          }
        }
        i += 1
      }
      return result
    }
    if let drill, !drill.spots.isEmpty {
      let total = max(1, drill.reps)
      return (0..<total).map { rep in
        Page(
          kind: .drillRep(template: pickDrillTemplate(drill, rep: rep), rep: rep), stepIndex: rep + 1,
          lastStep: rep + 1, repLabel: "Rep \(rep + 1) / \(total)")
      }
    }
    return []
  }

  private func pickDrillTemplate(_ drill: Drill, rep: Int) -> String {
    let weights = drill.spots.map { max(0, $0.weight) }
    let sum = weights.reduce(0, +)
    guard sum > 0 else { return drill.spots[rep % drill.spots.count].template }
    let unit = Double(StableSeed.mix(request.seed, UInt64(rep)) % 1_000_000) / 1_000_000
    var target = unit * sum
    for (spot, weight) in zip(drill.spots, weights) {
      if target < weight { return spot.template }
      target -= weight
    }
    return drill.spots[drill.spots.count - 1].template
  }

  private func updateStep(for page: Page) {
    if isDrill {
      step = StepInfo(index: page.stepIndex, total: pages.count, kind: .apply)
      stepLabel = "Drill"
      progress = Double(page.stepIndex) / Double(max(1, pages.count))
    } else {
      step = StepInfo(index: page.stepIndex, total: lesson?.steps.count ?? 1, kind: kind(of: page))
      stepLabel = step.label
      progress = Double(page.stepIndex) / Double(max(1, step.total))
    }
    pageID += 1
  }

  private func kind(of page: Page) -> LessonStepKind {
    switch page.kind {
    case .hook: .hook
    case .puzzle: .puzzle
    case .explain: .explain
    case .apply, .drillRep: .apply
    }
  }

  private func go(to index: Int) {
    pageIndex = index
    token += 1
    let current = token
    let page = pages[index]
    updateStep(for: page)
    hintShown = false
    hintCounted = false
    hintCostsStar = !isDrill && !isHook(page)
    phase = .preparing
    Task { [weak self] in
      guard let self else { return }
      if page.isSpot {
        await showSpot(page, index: index, token: current)
      } else {
        await showExplain(page, index: index, token: current)
      }
    }
  }

  private func isHook(_ page: Page) -> Bool {
    if case .hook = page.kind { return true }
    return false
  }

  private func advance() {
    let nextIndex = pageIndex + 1
    if nextIndex >= pages.count {
      finish()
    } else {
      go(to: nextIndex)
    }
  }

  // MARK: Spots

  private func seed(for page: Page) -> UInt64 {
    let pageNumber = UInt64(max(0, page.stepIndex - 1))
    var seed = StableSeed.mix(request.seed, pageNumber << 8 | UInt64(page.repIndex))
    if replay > 0 { seed = StableSeed.mix(seed, UInt64(replay)) }
    var fresh = isDrill
    if case .apply(let apply, _) = page.kind { fresh = apply.freshSeeds }
    if fresh, !model.launch.isDemo { seed = StableSeed.mix(seed, sessionSalt) }
    return seed
  }

  private func spotTask(at index: Int) -> Task<EvaluatedSpot, Error> {
    if let existing = spotTasks[index] { return existing }
    let page = pages[index]
    guard let factory, let templateID = page.templateID else {
      let failed = Task<EvaluatedSpot, Error> { throw SpotFactoryError.evaluation("content is not available") }
      spotTasks[index] = failed
      return failed
    }
    var hint: String?
    switch page.kind {
    case .hook(let step), .puzzle(let step): hint = step.hint
    default: break
    }
    let seed = seed(for: page)
    let avoid = avoid
    let hintOverride = hint
    let task = Task.detached(priority: .userInitiated) {
      try await factory.make(templateID: templateID, seed: seed, avoid: avoid, hintOverride: hintOverride)
    }
    spotTasks[index] = task
    return task
  }

  /// Starts solving the next spot page, so it is ready when the player gets there.
  private func prefetch(after index: Int) {
    guard let next = pages.indices.first(where: { $0 > index && pages[$0].isSpot }) else { return }
    _ = spotTask(at: next)
  }

  private func showSpot(_ page: Page, index: Int, token current: Int) async {
    do {
      let spot = try await spotTask(at: index).value
      guard current == token else { return }
      let spotPage = makePage(page, spot: spot)
      presentTable(spot)
      hintShown = false
      questionStart = ContinuousClock.now
      phase = .question(spotPage)
      prefetch(after: index)
    } catch {
      guard current == token else { return }
      Self.log.error("spot failed: \(String(describing: error))")
      phase = .failed("Hoot could not set up this table: \(Self.describe(error))")
    }
  }

  private static func describe(_ error: Error) -> String {
    if let factoryError = error as? SpotFactoryError {
      switch factoryError {
      case .unknownTemplate(let id): return "unknown spot \(id)"
      case .generation(let inner): return inner.description
      case .evaluation(let message): return message
      }
    }
    return String(describing: error)
  }

  private func makePage(_ page: Page, spot: EvaluatedSpot) -> SpotPage {
    let bindings = spot.solution.bindings
    func bound(_ text: String?) -> String? {
      guard let text else { return nil }
      return (try? TextBinder.bind(text, bindings)) ?? text
    }
    var raw: String?
    var shows = false
    switch page.kind {
    case .hook(let step), .puzzle(let step):
      raw = step.coach ?? spot.template.coach
      shows = true
    case .apply(let step, _):
      raw = step.coach ?? spot.template.coach
      shows = raw != nil && coachLevel(for: spot.template.skill) == .full
    case .drillRep:
      raw = spot.template.coach
      shows = raw != nil && coachLevel(for: spot.template.skill) == .full
    case .explain:
      break
    }
    var text = bound(raw)
    if text == spot.prompt { text = nil }
    return SpotPage(spot: spot, showsCoach: shows, coachText: shows ? text : nil, repLabel: page.repLabel)
  }

  private func coachLevel(for skill: String) -> CoachLevel {
    guard let library else { return .full }
    let base = library.skills.skill(skill)?.baseDifficulty ?? 0.5
    return CoachEngine.level(meter: model.curriculum.skillModel().meter(skill, baseDifficulty: base))
  }

  // MARK: Table

  private func presentTable(_ spot: EvaluatedSpot) {
    let shown = LessonSnapshot(instance: spot.instance, characters: library?.characters)
    scene.configure(table: spot.instance.config, seats: shown.seats, heroSeat: spot.instance.heroSeat)
    scene.show(shown.snapshot)
    overlay = shown.overlay
  }

  // MARK: Answers and progress

  private func record(_ page: SpotPage, grade: SpotGrade) {
    let isHook = isHook(pages[pageIndex])
    guard !isHook else { return }
    let solution = page.spot.solution
    let good = grade.grade == .good
    decisionsTotal += 1
    if good { decisionsGood += 1 }
    switch pages[pageIndex].kind {
    case .puzzle: puzzleGood = good
    case .apply, .drillRep:
      applyTotal += 1
      if good { applyGood += 1 }
    default: break
    }
    let elapsed = ContinuousClock.now - questionStart
    model.curriculum.recordDecision(
      skill: page.spot.template.skill, difficulty: solution.difficulty, quality: grade.quality,
      key: solution.decisionType, grade: grade.grade, fast: elapsed < DrillScheduler.fastThreshold,
      usedHint: hintShown, instanceHash: page.spot.instance.instanceHash, at: Date())
  }

  private func finish() {
    let stars: Int
    if let lesson {
      stars = LessonScoring.stars(
        lesson.stars, puzzleGood: puzzleGood, applyGood: applyGood, applyTotal: applyTotal, hintsUsed: hintsUsed)
    } else {
      stars = LessonScoring.drillStars(good: applyGood, total: applyTotal)
    }
    let score = decisionsTotal > 0 ? Double(decisionsGood) / Double(decisionsTotal) : nil
    if !request.nodeID.isEmpty {
      model.curriculum.completeNode(request.nodeID, stars: stars, score: score, at: Date())
    }
    progress = 1
    phase = .summary(
      Summary(
        stars: stars, puzzleGood: puzzleGood, applyGood: applyGood, applyTotal: applyTotal, hintsUsed: hintsUsed))
  }

  // MARK: Explain

  private func nextLabel(after index: Int) -> String {
    guard index + 1 < pages.count else { return "Finish →" }
    if case .apply(let apply, _) = pages[index + 1].kind {
      return "Next: try \(apply.count) \(apply.count == 1 ? "spot" : "spots") on your own →"
    }
    return "Next →"
  }

  /// Starts building the explain page that follows the page just answered, while the player reads the verdict.
  private func prepareExplain(after index: Int) {
    guard index + 1 < pages.count, case .explain = pages[index + 1].kind, explainTasks[index + 1] == nil,
      let answered = lastAnswered
    else { return }
    explainTasks[index + 1] = makeExplainTask(at: index + 1, spot: answered.spot, grade: answered.grade)
  }

  private func makeExplainTask(at index: Int, spot: EvaluatedSpot, grade: SpotGrade) -> Task<ExplainPageModel, Error> {
    guard case .explain(let explain, let sandbox) = pages[index].kind, let characters = library?.characters else {
      return Task { throw SpotFactoryError.evaluation("content is not available") }
    }
    let verdict = Verdict(grade: grade.grade, title: grade.verdictTitle, detail: grade.verdictDetail)
    let bindings = spot.solution.bindings
    let label = nextLabel(after: index)
    return Task.detached(priority: .userInitiated) {
      try await ExplainPageBuilder.build(
        explain: explain, sandbox: sandbox, instance: spot.instance, template: spot.template, verdict: verdict,
        characters: characters, villainRanges: spot.solution.villainRanges,
        bind: { (try? TextBinder.bind($0, bindings)) ?? $0 }, nextLabel: label)
    }
  }

  private func showExplain(_ page: Page, index: Int, token current: Int) async {
    do {
      if explainTasks[index] == nil {
        var answered = lastAnswered
        if answered == nil {
          // A lesson that opens on an explain page: use its neighbouring spot, marked as seen.
          guard
            let neighbour = pages.indices.first(where: { $0 > index && pages[$0].isSpot })
              ?? pages.indices.last(where: { $0 < index && pages[$0].isSpot })
          else { throw SpotFactoryError.evaluation("explain page without a spot") }
          let spot = try await spotTask(at: neighbour).value
          answered = (spot, SpotEvaluator.grade(spot.solution.correct, solution: spot.solution))
        }
        guard let answered else { return }
        explainTasks[index] = makeExplainTask(at: index, spot: answered.spot, grade: answered.grade)
      }
      guard let task = explainTasks[index] else { return }
      let explained = try await task.value
      guard current == token else { return }
      prefetch(after: index)
      phase = .explain(explained)
    } catch {
      guard current == token else { return }
      Self.log.error("explain failed: \(String(describing: error))")
      phase = .failed("Hoot could not prepare this page: \(Self.describe(error))")
    }
  }

  /// Demo start past the first spot: solves the spots before `index` and answers them correctly (not recorded), so
  /// the explain page has its verdict. Returns false when the lesson could not be prepared.
  private func prepareSkippedSpot(before index: Int) async -> Bool {
    guard let previous = pages.indices.last(where: { $0 < index && pages[$0].isSpot }) else { return true }
    do {
      let spot = try await spotTask(at: previous).value
      lastAnswered = (spot, SpotEvaluator.grade(spot.solution.correct, solution: spot.solution))
      return true
    } catch {
      Self.log.error("skipped spot failed: \(String(describing: error))")
      phase = .failed("Hoot could not set up this table: \(Self.describe(error))")
      return false
    }
  }
}
