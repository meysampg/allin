import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

public enum ThemeValidator {
  public static let maxPackBytes = 150 * 1024 * 1024
  public static let maxSoundSeconds = 3.0
  public static let maxMusicBytes = 3 * 1024 * 1024
  public static let minContrast = 4.5

  private static let minSuitDistance = 0.25
  private static let suitKeys: [PaletteKey] = [.suitRed, .suitBlack, .suitBlue, .suitGreen]

  /// Validates one `.allintheme` folder. `library` defaults to all packs next to it.
  public static func validate(packAt url: URL, library: ThemeLibrary? = nil) -> ThemeValidationReport {
    var issues: [ThemeIssue] = []
    let manifest: ThemeManifest
    do {
      let data = try Data(contentsOf: url.appending(path: "theme.json"))
      manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)
    } catch {
      issues.append(ThemeIssue(code: .unreadableManifest, message: "cannot read theme.json: \(error)"))
      return ThemeValidationReport(packID: nil, url: url, issues: issues)
    }

    let library =
      library ?? ((try? ThemeLibrary(directories: [url.deletingLastPathComponent()])) ?? ThemeLibrary(packs: []))

    if manifest.schemaVersion != ThemeManifest.currentSchemaVersion {
      issues.append(
        ThemeIssue(
          code: .unsupportedSchema,
          message: "schemaVersion \(manifest.schemaVersion) is not \(ThemeManifest.currentSchemaVersion)"))
    }

    let ancestors = checkExtends(manifest, library: library, issues: &issues)
    checkSlots(manifest, root: url, issues: &issues)
    checkPalette(manifest, ancestors: ancestors, issues: &issues)
    checkLicense(manifest, root: url, issues: &issues)

    let size = directorySize(url)
    if size > maxPackBytes {
      issues.append(
        ThemeIssue(
          code: .packTooLarge,
          message: "pack is \(size / (1024 * 1024)) MB, limit is \(maxPackBytes / (1024 * 1024)) MB"))
    }
    return ThemeValidationReport(packID: manifest.id, url: url, issues: issues)
  }

  /// Validates every `*.allintheme` child of `directory`, using all of them as the library.
  public static func validateAll(in directory: URL) -> [ThemeValidationReport] {
    let library = (try? ThemeLibrary(directories: [directory])) ?? ThemeLibrary(packs: [])
    let children =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return children.filter { $0.pathExtension == "allintheme" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { validate(packAt: $0, library: library) }
  }

  // MARK: Checks

  /// Returns the manifests of the resolvable `extends` chain (nearest first).
  private static func checkExtends(
    _ manifest: ThemeManifest, library: ThemeLibrary,
    issues: inout [ThemeIssue]
  ) -> [ThemeManifest] {
    func add(_ code: ThemeIssue.Code, _ message: String, _ slot: String?, _ warning: Bool) {
      issues.append(ThemeIssue(severity: warning ? .warning : .error, code: code, slotID: slot, message: message))
    }
    var chain: [ThemeManifest] = []
    var visited = [manifest.id]
    var next = manifest.extends
    while let id = next {
      if visited.contains(id) {
        add(.extendsCycle, "extends cycle: \((visited + [id]).joined(separator: " -> "))", nil, false)
        break
      }
      guard let pack = library.pack(id: id) else {
        add(.unresolvedExtends, "extends '\(id)' which is not in the library", nil, false)
        break
      }
      visited.append(id)
      chain.append(pack.manifest)
      next = pack.manifest.extends
    }
    return chain
  }

  private static func checkSlots(
    _ manifest: ThemeManifest, root: URL, issues: inout [ThemeIssue]
  ) {
    func add(_ code: ThemeIssue.Code, _ message: String, _ slot: String?, _ warning: Bool) {
      issues.append(ThemeIssue(severity: warning ? .warning : .error, code: code, slotID: slot, message: message))
    }
    for (slotID, entry) in manifest.slots.sorted(by: { $0.key < $1.key }) {
      guard let slot = AssetSlot(id: slotID) else {
        add(.unknownSlot, "'\(slotID)' is not a known slot id", slotID, false)
        continue
      }
      let set = [entry.procedural != nil, entry.file != nil, entry.files != nil].filter { $0 }.count
      guard set == 1 else {
        let why = set == 0 ? "has none of procedural, file, files" : "must have exactly one of procedural, file, files"
        add(.emptySlotEntry, why, slotID, false)
        continue
      }
      if let procedural = entry.procedural {
        if let kind = procedural.kind {
          if kind != slot.kind {
            add(
              .kindMismatch, "'\(procedural.rawValue)' is \(kind.rawValue), slot needs \(slot.kind.rawValue)", slotID,
              false)
          }
        } else {
          add(.unknownProcedural, "unknown procedural id '\(procedural.rawValue)'", slotID, false)
        }
      }
      var paths: [String] = []
      if let file = entry.file { paths.append(file) }
      if let files = entry.files {
        if files.isEmpty { add(.emptySlotEntry, "files is empty", slotID, false) }
        paths += files
      }
      for path in paths {
        checkFile(path, slot: slot, root: root) { code, message in add(code, message, slot.id, false) }
      }
    }
  }

  private static func checkFile(
    _ path: String, slot: AssetSlot, root: URL, report: (ThemeIssue.Code, String) -> Void
  ) {
    let url = root.appending(path: path)
    guard !path.contains(".."), FileManager.default.fileExists(atPath: url.path) else {
      report(.missingFile, "file '\(path)' does not exist")
      return
    }
    let ext = url.pathExtension.lowercased()
    switch slot.kind {
    case .image:
      guard ["png", "heic"].contains(ext) else {
        report(.badFormat, "'\(path)' must be png or heic")
        return
      }
      guard let image = ThemeImageIO.loadImage(at: url) else {
        report(.badFormat, "'\(path)' is not a readable image")
        return
      }
      checkImage(image, path: path, slot: slot, report: report)
    case .sound:
      guard ["caf", "m4a"].contains(ext) else {
        report(.badFormat, "'\(path)' must be caf or m4a")
        return
      }
      guard let file = try? AVAudioFile(forReading: url) else {
        report(.badFormat, "'\(path)' is not a readable audio file")
        return
      }
      let seconds = Double(file.length) / max(file.processingFormat.sampleRate, 1)
      if seconds > maxSoundSeconds {
        report(.soundTooLong, "'\(path)' is \(String(format: "%.1f", seconds)) s, limit is \(maxSoundSeconds) s")
      }
    case .music:
      guard ["caf", "m4a"].contains(ext) else {
        report(.badFormat, "'\(path)' must be caf or m4a")
        return
      }
      let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
      if bytes > maxMusicBytes { report(.musicTooLarge, "'\(path)' is \(bytes) bytes, limit is \(maxMusicBytes)") }
    case .font:
      if !["ttf", "otf"].contains(ext) { report(.badFormat, "'\(path)' must be ttf or otf") }
    case .effect:
      if ext != "json" { report(.badFormat, "'\(path)' must be json") }
    }
  }

  private static func checkImage(
    _ image: CGImage, path: String, slot: AssetSlot, report: (ThemeIssue.Code, String) -> Void
  ) {
    let w = image.width
    let h = image.height
    switch slot {
    case .cardFace, .cardFaceOverride, .cardCourt, .cardBack, .cardBackReward:
      let ratio = Double(w) / Double(max(h, 1))
      if abs(ratio / (5.0 / 7.0) - 1) > 0.01 { report(.badAspect, "'\(path)' is \(w)x\(h), cards must be 5:7 (+-1%)") }
      if w < 500 || h < 700 { report(.badSize, "'\(path)' is \(w)x\(h), cards must be at least 500x700") }
    case .avatar:
      if w != h { report(.badAspect, "'\(path)' is \(w)x\(h), avatars must be square") }
      if min(w, h) < 512 { report(.badSize, "'\(path)' is \(w)x\(h), avatars must be at least 512 px") }
      switch image.alphaInfo {
      case .none, .noneSkipFirst, .noneSkipLast: report(.missingAlpha, "'\(path)' has no alpha channel")
      default: break
      }
    default:
      if min(w, h) < 64 { report(.badSize, "'\(path)' is \(w)x\(h), images must be at least 64 px") }
    }
  }

  private static func checkPalette(
    _ manifest: ThemeManifest, ancestors: [ThemeManifest], issues: inout [ThemeIssue]
  ) {
    func add(_ code: ThemeIssue.Code, _ message: String, _ slot: String?, _ warning: Bool) {
      issues.append(ThemeIssue(severity: warning ? .warning : .error, code: code, slotID: slot, message: message))
    }
    for (key, value) in manifest.palette.sorted(by: { $0.key < $1.key }) {
      if PaletteKey(rawValue: key) == nil { add(.unknownPaletteKey, "'\(key)' is not a palette key", key, true) }
      if ThemeColor(hex: value) == nil { add(.invalidColor, "'\(value)' is not a valid hex color", key, false) }
    }
    // Effective palette: this pack first, then its extends chain, then hearthwood.
    var colors: [PaletteKey: ThemeColor] = [:]
    for m in ([manifest] + ancestors).reversed() {
      for (key, value) in m.palette {
        if let k = PaletteKey(rawValue: key), let c = ThemeColor(hex: value) { colors[k] = c }
      }
    }
    let palette = ThemePalette(colors: colors)
    for key in suitKeys where ThemeColor.contrastRatio(palette[key], palette[.cardFace]) < minContrast {
      let ratio = ThemeColor.contrastRatio(palette[key], palette[.cardFace])
      add(
        .lowContrast,
        "\(key.rawValue) contrast against cardFace is \(String(format: "%.2f", ratio)), needs \(minContrast)",
        key.rawValue, false)
    }
    for (i, a) in suitKeys.enumerated() {
      for b in suitKeys[(i + 1)...] where palette[a].distance(to: palette[b]) < minSuitDistance {
        add(
          .suitsNotDistinct, "\(a.rawValue) and \(b.rawValue) are too close (distance < \(minSuitDistance))",
          a.rawValue, false)
      }
    }
  }

  private static func checkLicense(
    _ manifest: ThemeManifest, root: URL, issues: inout [ThemeIssue]
  ) {
    func add(_ code: ThemeIssue.Code, _ message: String, _ slot: String?, _ warning: Bool) {
      issues.append(ThemeIssue(severity: warning ? .warning : .error, code: code, slotID: slot, message: message))
    }
    if (manifest.license ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
      add(.missingLicenseField, "manifest 'license' is empty", nil, false)
    }
    if !FileManager.default.fileExists(atPath: root.appending(path: "LICENSE.txt").path) {
      add(.missingLicenseFile, "LICENSE.txt is missing", nil, false)
    }
  }

  private static func directorySize(_ url: URL) -> Int {
    guard
      let walker = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
    else { return 0 }
    var total = 0
    for case let file as URL in walker {
      let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
    }
    return total
  }
}
