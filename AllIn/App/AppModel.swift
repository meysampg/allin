import AllInUI
import Foundation
import OSLog
import Observation
import PokerAI
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

  private static let settingsKey = "AllInSettings"
  private static let log = Logger(subsystem: "app.allin", category: "AppModel")

  init(launch: DebugLaunch) {
    self.launch = launch
    let startScreen: Screen = launch.isDemo ? (launch.screen ?? .menu) : .menu
    router = AppRouter(initial: startScreen == .table ? .menu : startScreen)

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

    router.reduceMotion = effectiveReduceMotion(system: false)
    if launch.isDemo, launch.screen == .table { router.startTable(.demo(seed: launch.seed ?? 7)) }
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
