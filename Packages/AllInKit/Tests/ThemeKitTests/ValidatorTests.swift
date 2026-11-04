import CoreGraphics
import Foundation
import Testing

@testable import ThemeKit

@Suite struct ValidatorTests {
  private func codes(_ report: ThemeValidationReport) -> Set<ThemeIssue.Code> { Set(report.issues.map(\.code)) }

  private func validate(
    _ manifest: ThemeManifest, license: Bool = true, files: [String: CGImage] = [:]
  ) throws -> ThemeValidationReport {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let url = try fixture.writePack(manifest, license: license, files: files)
    return ThemeValidator.validate(packAt: url)
  }

  @Test func minimalPackIsValid() throws {
    let report = try validate(
      PackFixture.manifest(slots: ["table.felt": .init(procedural: .feltCloth, params: ["color": "#1F4D3A"])]))
    #expect(report.isValid, "\(report.issues)")
    #expect(report.packID == "fixture")
  }

  @Test func slotErrors() throws {
    let report = try validate(
      PackFixture.manifest(slots: [
        "bogus.slot": .init(procedural: .feltCloth),
        "table.rail": .init(procedural: "rail.nope"),
        "sound.win": .init(procedural: .feltCloth),
        "table.shoe": .init(file: "missing.png"),
        "table.light": .init(),
        "table.runes": .init(procedural: .runesRing, file: "x.png"),
      ]))
    #expect(!report.isValid)
    let found = codes(report)
    for code in [
      ThemeIssue.Code.unknownSlot, .unknownProcedural, .kindMismatch, .missingFile, .emptySlotEntry,
    ] {
      #expect(found.contains(code), "\(code)")
    }
  }

  @Test func cardAspectAndSize() throws {
    let square = PackFixture.image(width: 500, height: 500)
    let small = PackFixture.image(width: 250, height: 350)
    let good = PackFixture.image(width: 500, height: 700)
    let bad = try validate(
      PackFixture.manifest(slots: ["card.face": .init(file: "a.png"), "card.back": .init(file: "b.png")]),
      files: ["a.png": square, "b.png": small])
    #expect(codes(bad).contains(.badAspect))
    #expect(codes(bad).contains(.badSize))
    let ok = try validate(
      PackFixture.manifest(slots: ["card.face": .init(file: "a.png")]), files: ["a.png": good])
    #expect(ok.isValid, "\(ok.issues)")
  }

  @Test func avatarNeedsAlpha() throws {
    let flat = PackFixture.opaqueRGBImage(width: 512, height: 512)
    let report = try validate(
      PackFixture.manifest(slots: ["avatar.grumli": .init(file: "a.png")]), files: ["a.png": flat])
    #expect(codes(report).contains(.missingAlpha), "\(report.issues)")
    let withAlpha = try validate(
      PackFixture.manifest(slots: ["avatar.grumli": .init(file: "a.png")]),
      files: ["a.png": PackFixture.image(width: 512, height: 512)])
    #expect(withAlpha.isValid, "\(withAlpha.issues)")
  }

  @Test func badFormatForWrongExtension() throws {
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let url = try fixture.writePack(
      PackFixture.manifest(slots: ["table.felt": .init(file: "felt.jpg"), "font.body": .init(file: "f.woff")]))
    try Data("x".utf8).write(to: url.appending(path: "felt.jpg"))
    try Data("x".utf8).write(to: url.appending(path: "f.woff"))
    let report = ThemeValidator.validate(packAt: url)
    #expect(codes(report).contains(.badFormat))
  }

  @Test func paletteProblems() throws {
    let low = try validate(PackFixture.manifest(palette: ["suitRed": "#FBF6EA"]))
    #expect(codes(low).contains(.lowContrast))
    let same = try validate(PackFixture.manifest(palette: ["suitBlue": "#1B1B1B"]))
    #expect(codes(same).contains(.suitsNotDistinct))
    let junk = try validate(PackFixture.manifest(palette: ["gold": "gold", "nonsense": "#000000"]))
    #expect(codes(junk).contains(.invalidColor))
    #expect(junk.issues.contains { $0.code == .unknownPaletteKey && $0.severity == .warning })
  }

  @Test func licenseProblems() throws {
    let noFile = try validate(PackFixture.manifest(), license: false)
    #expect(codes(noFile).contains(.missingLicenseFile))
    var manifest = PackFixture.manifest()
    manifest.license = ""
    let noField = try validate(manifest)
    #expect(codes(noField).contains(.missingLicenseField))
  }

  @Test func extendsProblems() throws {
    let unresolved = try validate(PackFixture.manifest(extends: "ghost"))
    #expect(codes(unresolved).contains(.unresolvedExtends))
    let fixture = try PackFixture()
    defer { fixture.remove() }
    try fixture.writePack(PackFixture.manifest(id: "a", extends: "b"))
    try fixture.writePack(PackFixture.manifest(id: "b", extends: "a"))
    let reports = ThemeValidator.validateAll(in: fixture.root)
    #expect(reports.count == 2)
    #expect(reports.allSatisfy { codes($0).contains(.extendsCycle) })
  }

  @Test func schemaAndManifestProblems() throws {
    var manifest = PackFixture.manifest()
    manifest.schemaVersion = 2
    #expect(codes(try validate(manifest)).contains(.unsupportedSchema))
    let fixture = try PackFixture()
    defer { fixture.remove() }
    let dir = fixture.root.appending(path: "broken.allintheme")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: dir.appending(path: "theme.json"))
    let report = ThemeValidator.validate(packAt: dir)
    #expect(codes(report) == [.unreadableManifest])
    #expect(report.packID == nil)
  }

  @Test func issueDescriptionFormat() {
    let issue = ThemeIssue(code: .unknownSlot, slotID: "x.y", message: "nope")
    #expect(issue.description == "error unknownSlot [x.y] nope")
  }
}
