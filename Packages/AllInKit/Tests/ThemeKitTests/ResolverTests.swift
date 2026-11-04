import Foundation
import Testing

@testable import ThemeKit

@Suite struct ResolverTests {
  private func library(_ fixture: PackFixture) throws -> ThemeLibrary {
    let hearth = ThemeManifest(
      id: "hearthwood", name: "H", version: "1", author: "a", license: "CC0-1.0",
      palette: ["felt": "#102030"],
      slots: ["table.felt": .init(procedural: .feltCloth, params: ["color": "#102030"])])
    try fixture.writePack(hearth)
    let child = PackFixture.manifest(
      id: "child", extends: "hearthwood", palette: ["gold": "#FFFF00"],
      slots: ["table.felt": .init(file: "felt.png"), "chip.5": .init(file: "sub/chip5.png")])
    try fixture.writePack(child)
    return try ThemeLibrary(directories: [fixture.root])
  }

  @Test func chainOrderAndSlotLookup() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let resolver = try ThemeResolver(library: library(fixture), selectedID: "child")
    #expect(resolver.chain.map(\.id) == ["child", "hearthwood"])
    guard case .file(let url) = resolver.resolve(.tableFelt) else {
      Issue.record("expected file")
      return
    }
    #expect(url.lastPathComponent == "felt.png")
    #expect(url.path.hasPrefix(resolver.chain[0].rootURL.path))
    guard case .file(let nested) = resolver.resolve(.chip(.five)) else {
      Issue.record("expected file")
      return
    }
    #expect(nested.path.hasSuffix("child.allintheme/sub/chip5.png"))
    #expect(resolver.resolvedPackID(for: .tableFelt) == "child")
  }

  @Test func fallsThroughToCodeDrawn() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let resolver = try ThemeResolver(library: library(fixture), selectedID: "child")
    #expect(resolver.resolve(.tableRail) == CodeDrawn.default(.tableRail))
    #expect(resolver.resolvedPackID(for: .tableRail) == nil)
    let hearthOnly = try ThemeResolver(library: library(fixture), selectedID: nil)
    #expect(hearthOnly.chain.map(\.id) == ["hearthwood"])
    #expect(hearthOnly.resolvedPackID(for: .tableFelt) == "hearthwood")
  }

  @Test func overrideFallsBackToCardFace() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let pack = PackFixture.manifest(id: "faces", slots: ["card.face": .init(file: "face.png")])
    try fixture.writePack(pack)
    let resolver = try ThemeResolver(library: ThemeLibrary(directories: [fixture.root]), selectedID: "faces")
    let override = AssetSlot.cardFaceOverride(CardKey(symbol: "As")!)
    #expect(resolver.resolve(override) == resolver.resolve(.cardFace))
    #expect(resolver.resolvedPackID(for: override) == "faces")
    let court = AssetSlot.cardCourt(CardKey(symbol: "Qh")!)
    #expect(resolver.resolvedPackID(for: court) == "faces")
    #expect(ThemeResolver.codeDrawn.resolve(override) == CodeDrawn.default(.cardFace))
    #expect(ThemeResolver.codeDrawn.resolve(.cardBackReward("zz")) == CodeDrawn.default(.cardBackReward("zz")))
  }

  @Test func paletteMergesAcrossChain() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let resolver = try ThemeResolver(library: library(fixture), selectedID: "child")
    #expect(resolver.palette[.gold].hex == "#FFFF00")
    #expect(resolver.palette[.felt].hex == "#102030")
    #expect(resolver.palette[.rail] == ThemePalette.hearthwood[.rail])
    #expect(ThemeResolver.codeDrawn.palette == ThemePalette.hearthwood)
  }

  @Test func cycleAndUnknownThrow() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    try fixture.writePack(PackFixture.manifest(id: "a", extends: "b"))
    try fixture.writePack(PackFixture.manifest(id: "b", extends: "a"))
    let lib = try ThemeLibrary(directories: [fixture.root])
    #expect(throws: ThemeError.extendsCycle(["a", "b", "a"])) { try ThemeResolver(library: lib, selectedID: "a") }
    #expect(throws: ThemeError.unknownPack("nope")) { try ThemeResolver(library: lib, selectedID: "nope") }
  }

  @Test func earlierDirectoryWinsOnDuplicateIDs() throws {
    let first = try PackFixture()
    let second = try PackFixture()
    defer {
      first.remove()
      second.remove()
    }
    try first.writePack(PackFixture.manifest(id: "dup", palette: ["felt": "#111111"]))
    try second.writePack(PackFixture.manifest(id: "dup", palette: ["felt": "#222222"]))
    let lib = try ThemeLibrary(directories: [first.root, second.root])
    #expect(lib.packs.count == 1)
    #expect(lib.pack(id: "dup")?.palette[.felt].hex == "#111111")
  }

  @Test func sourceTreeResolverUsesHearthwood() throws {
    let resolver = try ThemeResolver.sourceTree()
    #expect(resolver.chain.map(\.id) == ["hearthwood"])
    #expect(resolver.palette == ThemePalette.hearthwood)
  }
}
