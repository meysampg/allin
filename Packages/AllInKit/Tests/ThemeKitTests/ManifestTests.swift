import Foundation
import Testing

@testable import ThemeKit

@Suite struct ManifestTests {
  @Test func decodesShippedHearthwood() throws {
    let url = ThemeLibrary.sourceTreeThemesDirectory.appending(path: "hearthwood.allintheme")
    let pack = try ThemePack.load(from: url)
    #expect(pack.id == "hearthwood")
    #expect(pack.manifest.schemaVersion == 1)
    #expect(pack.manifest.palette.count == PaletteKey.allCases.count)
    #expect(pack.palette == ThemePalette.hearthwood)
  }

  @Test func hearthwoodSlotsMatchCodeDrawn() throws {
    let url = ThemeLibrary.sourceTreeThemesDirectory.appending(path: "hearthwood.allintheme")
    let pack = try ThemePack.load(from: url)
    #expect(pack.manifest.slots.count == 36)
    for id in pack.manifest.slots.keys {
      let slot = try #require(AssetSlot(id: id), "\(id)")
      #expect(pack.source(for: slot) == CodeDrawn.default(slot), "\(id)")
    }
  }

  @Test func roundTrip() throws {
    var manifest = ThemeManifest(
      id: "t", name: "T", version: "1.2.3", author: "me", license: "CC0-1.0", extends: "hearthwood",
      palette: ["felt": "#112233"],
      slots: [
        "table.felt": .init(file: "felt.png"),
        "card.back": .init(procedural: .backRuneknot, params: ["hue": 0.5, "flag": true, "name": "x"]),
        "chip.1": .init(files: ["a.png", "b.png"]),
      ])
    manifest.license = "MIT"
    let data = try JSONEncoder().encode(manifest)
    #expect(try JSONDecoder().decode(ThemeManifest.self, from: data) == manifest)
  }

  @Test func paramsDecodeScalars() throws {
    let json = ##"{"a": 1.5, "b": "#FF0000", "c": true}"##
    let params = try JSONDecoder().decode(ProceduralParams.self, from: Data(json.utf8))
    #expect(params.double("a", default: 0) == 1.5)
    #expect(params.string("b", default: "") == "#FF0000")
    #expect(params.bool("c", default: false))
    #expect(params.double("missing", default: 7) == 7)
    #expect(params.color("b", default: ThemeColor(red: 0, green: 0, blue: 0)).hex == "#FF0000")
    #expect(params.color("a", default: ThemeColor(red: 0, green: 1, blue: 0)).hex == "#00FF00")
  }

  @Test func proceduralIDKinds() {
    #expect(ProceduralID.coinGold.kind == .image)
    #expect(ProceduralID.sfxBell.kind == .sound)
    #expect(ProceduralID.musicSilence.kind == .music)
    #expect(ProceduralID.fontSystem.kind == .font)
    #expect(ProceduralID.fxParticles.kind == .effect)
    #expect(ProceduralID(rawValue: "nope").kind == nil)
  }

  @Test func loadingNonPackThrows() {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    #expect(throws: ThemeError.notAPack(url)) { try ThemePack.load(from: url) }
  }
}
