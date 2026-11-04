import Foundation

public struct ThemeLibrary: Sendable {
  public private(set) var packs: [ThemePack]

  /// Loads every `*.allintheme` child of each directory. Later directories don't override earlier ids.
  public init(directories: [URL]) throws {
    var result: [ThemePack] = []
    var seen: Set<String> = []
    for directory in directories {
      let children =
        (try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
      let folders = children.filter { $0.pathExtension == "allintheme" }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
      for folder in folders {
        let pack = try ThemePack.load(from: folder)
        if seen.insert(pack.id).inserted { result.append(pack) }
      }
    }
    packs = result
  }

  public init(packs: [ThemePack]) {
    self.packs = packs
  }

  public func pack(id: String) -> ThemePack? { packs.first { $0.id == id } }

  /// `bundle.resourceURL/Themes` if it exists.
  public static func bundledThemesDirectory(in bundle: Bundle = .main) -> URL? {
    guard let url = bundle.resourceURL?.appending(path: "Themes") else { return nil }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
      ? url : nil
  }

  /// `<repo>/Themes`, found from this file's `#filePath` (tools and tests only).
  public static var sourceTreeThemesDirectory: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return url.appending(path: "Themes")
  }
}
