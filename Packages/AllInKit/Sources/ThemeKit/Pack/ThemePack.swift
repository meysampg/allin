import Foundation

public enum ThemeError: Error, Sendable, Equatable {
  case notAPack(URL)
  case unreadableManifest(URL, String)
  case unknownPack(String)
  case extendsCycle([String])
}

/// A `.allintheme` folder: a `theme.json` manifest plus asset files.
public struct ThemePack: Sendable, Hashable {
  public let manifest: ThemeManifest
  /// The `.allintheme` folder.
  public let rootURL: URL

  public var id: String { manifest.id }

  public init(manifest: ThemeManifest, rootURL: URL) {
    self.manifest = manifest
    self.rootURL = rootURL
  }

  /// Reads `<url>/theme.json`.
  public static func load(from url: URL) throws -> ThemePack {
    let manifestURL = url.appending(path: "theme.json")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
      FileManager.default.fileExists(atPath: manifestURL.path)
    else { throw ThemeError.notAPack(url) }
    do {
      let data = try Data(contentsOf: manifestURL)
      let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)
      return ThemePack(manifest: manifest, rootURL: url)
    } catch {
      throw ThemeError.unreadableManifest(url, String(describing: error))
    }
  }

  /// Only valid keys with valid hex values; everything else comes from `.hearthwood`.
  public var palette: ThemePalette { ThemePalette(colors: explicitPaletteColors) }

  /// The palette keys this pack explicitly sets (valid keys and valid hex only).
  var explicitPaletteColors: [PaletteKey: ThemeColor] {
    var colors: [PaletteKey: ThemeColor] = [:]
    for (rawKey, hex) in manifest.palette {
      if let key = PaletteKey(rawValue: rawKey), let color = ThemeColor(hex: hex) { colors[key] = color }
    }
    return colors
  }

  /// nil if the pack doesn't define the slot. File paths are resolved against `rootURL`.
  public func source(for slot: AssetSlot) -> AssetSource? {
    guard let entry = manifest.slots[slot.id] else { return nil }
    if let procedural = entry.procedural { return .procedural(procedural, entry.params ?? ProceduralParams()) }
    if let file = entry.file { return .file(rootURL.appending(path: file)) }
    if let files = entry.files, !files.isEmpty { return .files(files.map { rootURL.appending(path: $0) }) }
    return nil
  }
}
