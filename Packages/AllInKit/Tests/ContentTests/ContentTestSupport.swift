import Foundation
import PokerAI

@testable import Curriculum

enum ContentTestSupport {
  static let catalog: CharacterCatalog = {
    do { return try CharacterCatalog.load(directory: BotCharacter.sourceTreeDirectory) } catch {
      fatalError("\(error)")
    }
  }()

  static let fixtureFiles: [String: Data] = {
    do { return try ContentLibrary.files(at: ContentLibrary.fixtureRoot) } catch { fatalError("\(error)") }
  }()

  static let fixture: ContentLibrary = {
    do { return try ContentLibrary.load(files: fixtureFiles, characters: catalog) } catch { fatalError("\(error)") }
  }()

  static let tavern = "venues/fx.tavern/"

  /// The fixture pack with one JSON file edited in place.
  static func mutate(file: String, _ edit: (inout [String: Any]) -> Void) -> [String: Data] {
    var files = fixtureFiles
    guard let data = files[file], var tree = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      fatalError("no JSON file \(file)")
    }
    edit(&tree)
    files[file] = try! JSONSerialization.data(withJSONObject: tree, options: [.sortedKeys])
    return files
  }

  static func spot(_ name: String, _ edit: (inout [String: Any]) -> Void) -> [String: Data] {
    mutate(file: "\(tavern)spots/\(name).json", edit)
  }

  /// Load issues if the pack does not load, else structural and text issues.
  static func staticIssues(_ files: [String: Data]) -> [ContentIssue] {
    do {
      let library = try ContentLibrary.load(files: files, characters: catalog)
      return ContentValidator.structural(library) + ContentValidator.placeholders(library)
    } catch let error as ContentLoadError {
      return error.issues
    } catch {
      fatalError("\(error)")
    }
  }

  /// Full validation of a pack that must load, restricted to some templates.
  static func validate(
    _ files: [String: Data], templates: Set<String>, instances: Int = 20, evInstances: Int = 8
  ) async -> ValidationReport {
    guard let library = try? ContentLibrary.load(files: files, characters: catalog) else {
      fatalError("pack does not load")
    }
    var options = ValidationOptions()
    options.instances = instances
    options.evInstances = evInstances
    options.templates = templates
    options.budget = .test
    return await ContentValidator.validate(library, options: options)
  }
}
