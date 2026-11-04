import CoreGraphics
import Foundation

@testable import ThemeKit

/// Writes pack fixtures to a fresh temporary directory.
struct PackFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "themekit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }

  /// Creates `<root>/<id>.allintheme` with theme.json and (optionally) a LICENSE.txt.
  @discardableResult
  func writePack(
    _ manifest: ThemeManifest, license: Bool = true, files: [String: CGImage] = [:]
  ) throws -> URL {
    let dir = root.appending(path: "\(manifest.id).allintheme")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try JSONEncoder().encode(manifest).write(to: dir.appending(path: "theme.json"))
    if license { try Data("CC0".utf8).write(to: dir.appending(path: "LICENSE.txt")) }
    for (name, image) in files { try ThemeImageIO.writePNG(image, to: dir.appending(path: name)) }
    return dir
  }

  static func manifest(
    id: String = "fixture", extends: String? = nil, palette: [String: String] = [:],
    slots: [String: ThemeManifest.SlotEntry] = [:]
  ) -> ThemeManifest {
    ThemeManifest(
      id: id, name: id, version: "1.0.0", author: "test", license: "CC0-1.0", extends: extends, palette: palette,
      slots: slots)
  }

  /// A solid image, opaque or fully transparent.
  static func image(width: Int, height: Int, opaque: Bool = true) -> CGImage {
    let context = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    if opaque {
      context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return context.makeImage()!
  }

  /// An image saved without an alpha channel.
  static func opaqueRGBImage(width: Int, height: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.5, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }
}
