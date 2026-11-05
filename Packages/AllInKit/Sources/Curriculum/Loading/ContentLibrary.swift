import Foundation
import PokerAI

/// A loaded content pack: the realm, skills, every open venue and the content its folder holds.
public struct ContentLibrary: Sendable {
  public let realm: Realm
  public let skills: SkillCatalog
  /// Open venues, in realm order.
  public let venues: [Venue]
  public let lessons: [String: Lesson]
  public let templates: [String: SpotTemplate]
  public let drills: [String: Drill]
  public let bosses: [String: BossSpec]
  public let exams: [String: ExamSpec]
  public let characters: CharacterCatalog
  /// Any content id to its root-relative file.
  public let fileOf: [String: String]
  public let warnings: [ContentIssue]

  public init(
    realm: Realm, skills: SkillCatalog, venues: [Venue], lessons: [String: Lesson],
    templates: [String: SpotTemplate], drills: [String: Drill], bosses: [String: BossSpec],
    exams: [String: ExamSpec], characters: CharacterCatalog, fileOf: [String: String],
    warnings: [ContentIssue] = []
  ) {
    self.realm = realm
    self.skills = skills
    self.venues = venues
    self.lessons = lessons
    self.templates = templates
    self.drills = drills
    self.bosses = bosses
    self.exams = exams
    self.characters = characters
    self.fileOf = fileOf
    self.warnings = warnings
  }

  // MARK: Roots

  /// `<repo>/Content`, found from this file's `#filePath` (dev tools and tests only).
  public static var sourceTreeRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return url.appending(path: "Content")
  }

  /// `<repo>/Content/fixtures/sample`.
  public static var fixtureRoot: URL {
    sourceTreeRoot.appending(path: "fixtures/sample")
  }

  /// True when `root` has a `realm.json`.
  public static func hasCurriculum(at root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: "realm.json").path)
  }

  // MARK: Reading

  /// Every curriculum JSON file under `root` (realm, skills and each venue folder), keyed by root-relative path.
  public static func files(at root: URL) throws -> [String: Data] {
    let manager = FileManager.default
    var result: [String: Data] = [:]
    func read(_ relative: String) throws {
      let url = root.appending(path: relative)
      var isDirectory: ObjCBool = false
      guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
      result[relative] = try Data(contentsOf: url)
    }
    func children(_ relative: String) -> [String] {
      let url = root.appending(path: relative)
      return ((try? manager.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }
    try read("realm.json")
    try read("skills.json")
    for venue in children("venues") where !venue.hasPrefix(".") {
      let base = "venues/\(venue)"
      try read("\(base)/venue.json")
      try read("\(base)/boss.json")
      try read("\(base)/exam.json")
      for folder in ["lessons", "spots", "drills"] {
        for name in children("\(base)/\(folder)") where name.hasSuffix(".json") && !name.hasPrefix(".") {
          try read("\(base)/\(folder)/\(name)")
        }
      }
    }
    return result
  }

  /// Loads `root`. Characters come from `charactersDirectory`, else `<root>/characters`, else `Content/characters`.
  public static func load(root: URL, charactersDirectory: URL? = nil) throws -> ContentLibrary {
    let files: [String: Data]
    let catalog: CharacterCatalog
    do {
      files = try Self.files(at: root)
      var directory = charactersDirectory ?? root.appending(path: "characters")
      if charactersDirectory == nil, !FileManager.default.fileExists(atPath: directory.path) {
        directory = BotCharacter.sourceTreeDirectory
      }
      catalog = try CharacterCatalog.load(directory: directory)
    } catch {
      throw ContentLoadError(
        issues: [ContentIssue(.error, code: "json.decode", file: "", message: "cannot read content: \(error)")])
    }
    return try load(files: files, characters: catalog)
  }

  // MARK: Loading

  /// Loads an in-memory pack. Every decode issue is collected before throwing `ContentLoadError`.
  public static func load(files: [String: Data], characters: CharacterCatalog) throws -> ContentLibrary {
    var loader = Loader(files: files)
    return try loader.run(characters: characters)
  }

  private struct Loader {
    let files: [String: Data]
    var issues: [ContentIssue] = []
    var seen: [String: [String: String]] = [:]  // kind -> id -> file
    var fileOf: [String: String] = [:]

    init(files: [String: Data]) { self.files = files }

    mutating func decode<T: Decodable>(_ type: T.Type, _ kind: ContentFileKind, _ file: String) -> T? {
      guard let data = files[file] else { return nil }
      return ContentDecoding.decode(type, kind: kind, data: data, file: file, issues: &issues)
    }

    /// Records the id; false (and an issue) when the id already exists for that kind.
    mutating func register(_ kind: String, _ id: String, file: String) -> Bool {
      if let first = seen[kind]?[id] {
        issues.append(
          ContentIssue(
            .error, code: "id.duplicate", file: file, path: "id",
            message: "duplicate \(kind) id '\(id)' (also in \(first))"))
        return false
      }
      seen[kind, default: [:]][id] = file
      fileOf[id] = file
      return true
    }

    mutating func run(characters: CharacterCatalog) throws -> ContentLibrary {
      guard files["realm.json"] != nil else {
        throw ContentLoadError(
          issues: [
            ContentIssue(.error, code: "json.decode", file: "realm.json", message: "missing file 'realm.json'")
          ])
      }
      let realm = decode(Realm.self, .realm, "realm.json")
      var skills = SkillCatalog(axes: [], skills: [])
      if files["skills.json"] == nil {
        issues.append(
          ContentIssue(.error, code: "json.decode", file: "skills.json", message: "missing file 'skills.json'"))
      } else if let decoded = decode(SkillCatalog.self, .skills, "skills.json") {
        skills = decoded
        for skill in decoded.skills { _ = register("skill", skill.id, file: "skills.json") }
      }
      for axis in skills.axes { _ = register("axis", axis.id, file: "skills.json") }

      var venues: [Venue] = []
      var lessons: [String: Lesson] = [:]
      var templates: [String: SpotTemplate] = [:]
      var drills: [String: Drill] = [:]
      var bosses: [String: BossSpec] = [:]
      var exams: [String: ExamSpec] = [:]
      var warnings: [ContentIssue] = []

      for entry in realm?.venues ?? [] {
        _ = register("venue", entry.id, file: "realm.json")
        guard entry.status == .open else { continue }
        let base = "venues/\(entry.id)"
        let venueFile = "\(base)/venue.json"
        guard files[venueFile] != nil else {
          issues.append(
            ContentIssue(
              .error, code: "realm.missingVenue", file: "realm.json", path: "venues",
              message: "open venue '\(entry.id)' has no \(venueFile)"))
          continue
        }
        if let venue = decode(Venue.self, .venue, venueFile) {
          if venue.id != entry.id {
            issues.append(
              ContentIssue(
                .error, code: "venue.folder", file: venueFile, path: "id",
                message: "venue id '\(venue.id)' does not match folder '\(entry.id)'"))
          }
          fileOf[entry.id] = venueFile
          venues.append(venue)
          for node in venue.nodes { _ = register("node", node.id, file: venueFile) }
        }
        for file in files.keys.sorted() where file.hasPrefix("\(base)/") {
          let rest = file.dropFirst(base.count + 1)
          if rest.hasPrefix("lessons/"), let lesson = decode(Lesson.self, .lesson, file) {
            if register("lesson", lesson.id, file: file) { lessons[lesson.id] = lesson }
          } else if rest.hasPrefix("spots/"), let template = decode(SpotTemplate.self, .spot, file) {
            if register("template", template.id, file: file) { templates[template.id] = template }
          } else if rest.hasPrefix("drills/"), let drill = decode(Drill.self, .drill, file) {
            if register("drill", drill.id, file: file) { drills[drill.id] = drill }
          } else if rest == "boss.json", let boss = decode(BossSpec.self, .boss, file) {
            if register("boss", boss.id, file: file) { bosses[boss.id] = boss }
          } else if rest == "exam.json", let exam = decode(ExamSpec.self, .exam, file) {
            if register("exam", exam.id, file: file) { exams[exam.id] = exam }
          }
        }
      }

      let listed = Set((realm?.venues ?? []).map(\.id))
      let folders = Set(files.keys.compactMap { $0.hasPrefix("venues/") ? $0.split(separator: "/")[1] : nil })
      for folder in folders.sorted() where !listed.contains(String(folder)) {
        warnings.append(
          ContentIssue(
            .warning, code: "venue.folder", file: "venues/\(folder)", message: "folder is not listed in realm.json"))
      }

      guard issues.isEmpty, let realm else { throw ContentLoadError(issues: issues) }
      return ContentLibrary(
        realm: realm, skills: skills, venues: venues, lessons: lessons, templates: templates, drills: drills,
        bosses: bosses, exams: exams, characters: characters, fileOf: fileOf, warnings: warnings)
    }
  }

  // MARK: Lookup

  public func realmVenue(_ id: String) -> RealmVenue? { realm.venues.first { $0.id == id } }

  public func venue(_ id: String) -> Venue? { venues.first { $0.id == id } }

  public func node(_ id: String) -> (venue: Venue, node: VenueNode)? {
    for venue in venues {
      if let node = venue.node(id) { return (venue, node) }
    }
    return nil
  }

  public func lesson(_ id: String) -> Lesson? { lessons[id] }

  public func template(_ id: String) -> SpotTemplate? { templates[id] }

  public func drill(_ id: String) -> Drill? { drills[id] }

  public func boss(_ id: String) -> BossSpec? { bosses[id] }

  public func exam(_ id: String) -> ExamSpec? { exams[id] }

  /// The venue whose folder holds `id` (a venue, node, lesson, template, drill, boss or exam id).
  public func venueID(ofContent id: String) -> String? {
    guard let file = fileOf[id], file.hasPrefix("venues/") else { return nil }
    return file.split(separator: "/").dropFirst().first.map(String.init)
  }

  /// `node.title`, else the referenced lesson, drill or boss title, else "Table session".
  public func title(of node: VenueNode) -> String {
    if let title = node.title { return title }
    if let id = node.lesson, let lesson = lessons[id] { return lesson.title }
    if let id = node.drill, let drill = drills[id] { return drill.title }
    if let id = node.boss, let boss = bosses[id] { return boss.title }
    return "Table session"
  }

  /// Templates of a skill, sorted by id.
  public func templates(forSkill skill: String) -> [SpotTemplate] {
    templates.values.filter { $0.skill == skill }.sorted { $0.id < $1.id }
  }
}
