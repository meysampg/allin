import Foundation

/// Resolves a slot through a chain of packs (selected, then what it extends, then hearthwood), then CodeDrawn.
public struct ThemeResolver: Sendable {
  public static let hearthwoodID = "hearthwood"

  /// An empty chain: everything comes from CodeDrawn.
  public static let codeDrawn = ThemeResolver(chain: [])

  public let chain: [ThemePack]

  /// Chain = selected, its `extends` ancestors, then "hearthwood" (if in the library), deduplicated.
  /// - Throws: `extendsCycle` or `unknownPack`.
  public init(library: ThemeLibrary, selectedID: String? = nil) throws {
    var result: [ThemePack] = []
    var visited: [String] = []
    var current: String? = selectedID ?? (library.pack(id: ThemeResolver.hearthwoodID) != nil ? Self.hearthwoodID : nil)
    while let id = current {
      if visited.contains(id) { throw ThemeError.extendsCycle(visited + [id]) }
      guard let pack = library.pack(id: id) else { throw ThemeError.unknownPack(id) }
      visited.append(id)
      result.append(pack)
      current = pack.manifest.extends
    }
    if let base = library.pack(id: Self.hearthwoodID), !visited.contains(Self.hearthwoodID) { result.append(base) }
    chain = result
  }

  public init(chain: [ThemePack]) {
    var seen: Set<String> = []
    self.chain = chain.filter { seen.insert($0.id).inserted }
  }

  /// The library from `ThemeLibrary.sourceTreeThemesDirectory`, with no selection (hearthwood).
  public static func sourceTree() throws -> ThemeResolver {
    let library = try ThemeLibrary(directories: [ThemeLibrary.sourceTreeThemesDirectory])
    return try ThemeResolver(library: library, selectedID: nil)
  }

  /// The first pack in the chain that defines a key wins, then `.hearthwood`.
  public var palette: ThemePalette {
    var colors: [PaletteKey: ThemeColor] = [:]
    for pack in chain.reversed() {
      colors.merge(pack.explicitPaletteColors) { _, new in new }
    }
    return ThemePalette(colors: colors)
  }

  /// Chain lookup, then the `fallbackSlot` chain lookup, then `CodeDrawn.default(slot)`. Never fails.
  public func resolve(_ slot: AssetSlot) -> AssetSource {
    chainSource(for: slot) ?? CodeDrawn.default(slot)
  }

  private func chainSource(for slot: AssetSlot) -> AssetSource? {
    for pack in chain {
      if let source = pack.source(for: slot) { return source }
    }
    return slot.fallbackSlot.flatMap { chainSource(for: $0) }
  }

  /// nil means CodeDrawn.
  public func resolvedPackID(for slot: AssetSlot) -> String? {
    for pack in chain where pack.source(for: slot) != nil { return pack.id }
    if let fallback = slot.fallbackSlot { return resolvedPackID(for: fallback) }
    return nil
  }
}
