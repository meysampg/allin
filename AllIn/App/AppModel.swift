import AllInStore
import AllInUI
import Curriculum
import Foundation
import OSLog
import Observation
import PokerAI
import PokerAnalysis
import SwiftData
import TableKit
import ThemeKit

@MainActor @Observable
final class AppModel {
  let launch: DebugLaunch
  let router: AppRouter
  var settings: AppSettings {
    didSet {
      soundBank.settings = settings.sound
      router.reduceMotion = effectiveReduceMotion(system: false)
      persistSettings()
    }
  }
  var profile = PlayerProfile()
  let themeResolver: ThemeResolver
  let theme: Theme
  let contentDirectory: URL
  var charactersDirectory: URL { contentDirectory.appending(path: "characters") }
  let characters: [BotCharacter]
  let soundBank: SoundBank
  let progress: ProgressStore
  let archive: HandArchive
  let analysis: HandAnalysisService
  let curriculum: CurriculumService

  private static let settingsKey = "AllInSettings"
  private static let log = Logger(subsystem: "app.allin", category: "AppModel")

  init(launch: DebugLaunch) {
    self.launch = launch
    let startScreen: Screen = launch.isDemo ? (launch.screen ?? .menu) : .menu
    let routedLater: Set<Screen> = [.table, .review, .venue, .lesson]
    router = AppRouter(initial: routedLater.contains(startScreen) ? .menu : startScreen)

    var loaded = AppSettings()
    if !launch.isDemo, let data = UserDefaults.standard.data(forKey: Self.settingsKey),
      let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
    {
      loaded = decoded
    }
    settings = loaded

    let resolver: ThemeResolver
    do {
      let dirs = ThemeLibrary.bundledThemesDirectory(in: .main).map { [$0] } ?? []
      resolver = try ThemeResolver(library: ThemeLibrary(directories: dirs))
    } catch {
      Self.log.error("theme load failed: \(String(describing: error))")
      resolver = .codeDrawn
    }
    themeResolver = resolver
    theme = Theme(resolver: resolver)

    let content = launch.contentDirectory ?? Bundle.main.resourceURL?.appending(path: "Content") ?? URL(filePath: "/")
    contentDirectory = content
    do {
      characters = try BotCharacter.loadAll(directory: content.appending(path: "characters"))
    } catch {
      Self.log.error("character load failed: \(String(describing: error))")
      characters = []
    }
    soundBank = SoundBank(resolver: resolver, settings: loaded.sound)

    let container = Self.makeContainer(inMemory: launch.isDemo)
    progress = ProgressStore(container: container)
    archive = HandArchive(container: container)
    analysis = HandAnalysisService(
      archive: archive, progress: progress, charactersDirectory: content.appending(path: "characters"),
      characters: characters, budget: launch.fast || launch.isDemo ? .demo : .standard)
    curriculum = CurriculumService(contentDirectory: content, progress: progress)
    if launch.isDemo, let library = curriculum.library { DemoProgress.seed(progress, library: library) }
    profile.careerProgress = curriculum.careerProgressText
    curriculum.onChange = { [weak self] in
      guard let self else { return }
      self.profile.careerProgress = self.curriculum.careerProgressText
    }

    router.reduceMotion = effectiveReduceMotion(system: false)
    if launch.isDemo { routeDemoCurriculum() }
    if launch.isDemo, launch.screen == .review { router.openReview(.demo(seed: launch.seed ?? 7)) }
    if launch.isDemo, launch.screen == .table { router.startTable(.demo(seed: launch.seed ?? 7)) }
  }

  /// Demo routing for `-AllInScreen venue[:<venueID>]` and `lesson[:<step>]`.
  private func routeDemoCurriculum() {
    switch launch.screen {
    case .venue:
      if let id = launch.screenArgument ?? curriculum.currentVenue()?.id { router.openVenue(id) }
    case .lesson:
      router.openLesson(fallbackLessonRequest(startStep: Int(launch.screenArgument ?? "") ?? 2))
    default:
      break
    }
  }

  /// A lesson request for the current node of the current venue (the first lesson node when that is not a lesson).
  func fallbackLessonRequest(startStep: Int? = nil) -> LessonRequest {
    let seed = launch.seed ?? 7
    guard let library = curriculum.library,
      let entry = curriculum.currentVenue() ?? library.realm.venues.first(where: { $0.status == .open }),
      let venue = library.venue(entry.id)
    else { return LessonRequest(venueID: "", nodeID: "", content: .lesson(""), seed: seed, startStep: startStep) }
    func request(_ node: VenueNode) -> LessonRequest? {
      if let id = node.lesson {
        return LessonRequest(venueID: venue.id, nodeID: node.id, content: .lesson(id), seed: seed, startStep: startStep)
      }
      if let id = node.drill {
        return LessonRequest(venueID: venue.id, nodeID: node.id, content: .drill(id), seed: seed, startStep: startStep)
      }
      return nil
    }
    if let node = curriculum.currentNode(in: venue), let found = request(node) { return found }
    for node in venue.nodes { if let found = request(node) { return found } }
    return LessonRequest(venueID: venue.id, nodeID: "", content: .lesson(""), seed: seed, startStep: startStep)
  }

  private static func makeContainer(inMemory: Bool) -> ModelContainer {
    do {
      return try AllInPersistence.makeContainer(inMemory: inMemory)
    } catch {
      log.error("store failed, using memory: \(String(describing: error))")
      do {
        return try AllInPersistence.makeContainer(inMemory: true)
      } catch {
        fatalError("Cannot create an in-memory store: \(error)")
      }
    }
  }

  func character(_ id: String) -> BotCharacter? {
    characters.first { $0.id == id }
  }

  func newSessionSeed() -> UInt64 {
    launch.seed ?? UInt64.random(in: .min ... .max)
  }

  func effectiveReduceMotion(system: Bool) -> Bool {
    system || settings.reduceMotion || launch.reduceMotion
  }

  private func persistSettings() {
    guard !launch.isDemo, let data = try? JSONEncoder().encode(settings) else { return }
    UserDefaults.standard.set(data, forKey: Self.settingsKey)
  }
}
