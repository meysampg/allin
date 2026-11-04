import CoreGraphics
import Foundation
import PokerCore
import TableKit
import ThemeKit

/// `allin-tool theme render-cards`: writes the 52 faces, the back and a contact sheet as PNG files.
enum ThemeRenderCardsCommand {
  static let usage = """
    USAGE: allin-tool theme render-cards [--out <dir>] [--four-color] [--theme <dir>] [--width <px>]

    Writes <rank><suit>.png for all 52 cards, back.png and sheet.png (13x4 grid plus the back).
      --out <dir>     output folder (default: build/preview/cards)
      --four-color    use the four-color deck
      --theme <dir>   a .allintheme pack, or a folder of packs (default: the source-tree Themes folder)
      --width <px>    card width in pixels, height is width * 1.4 (default: 250)
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    var out = "build/preview/cards"
    var fourColor = false
    var theme: String?
    var width = 250
    var i = 0
    func value(_ flag: String) throws -> String {
      i += 1
      guard i < args.count else { throw ToolError("\(flag) needs a value") }
      return args[i]
    }
    while i < args.count {
      switch args[i] {
      case "--out": out = try value("--out")
      case "--four-color": fourColor = true
      case "--theme": theme = try value("--theme")
      case "--width":
        let text = try value("--width")
        guard let n = Int(text), n >= 20, n <= 4000 else { throw ToolError("--width must be an integer 20...4000") }
        width = n
      default: throw ToolError("unknown option '\(args[i])'")
      }
      i += 1
    }

    let resolver = try makeResolver(theme)
    let size = CGSize(width: width, height: Int((Double(width) * 1.4).rounded()))
    let renderer = CardRenderer(resolver: resolver, options: CardRenderOptions(pixelSize: size, fourColor: fourColor))
    let outURL = URL(fileURLWithPath: out, isDirectory: true)
    try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

    var faces: [CGImage] = []
    for card in Card.all {
      let image = renderer.face(card)
      faces.append(image)
      try ThemeImageIO.writePNG(image, to: outURL.appendingPathComponent("\(card.description).png"))
    }
    let back = renderer.back()
    try ThemeImageIO.writePNG(back, to: outURL.appendingPathComponent("back.png"))

    let sheet = contactSheet(faces: faces, back: back, size: size, background: resolver.palette[.felt])
    try ThemeImageIO.writePNG(sheet, to: outURL.appendingPathComponent("sheet.png"))
    print("wrote 52 cards, back.png and sheet.png to \(outURL.path)")
    return 0
  }

  private static func makeResolver(_ theme: String?) throws -> ThemeResolver {
    guard let theme else { return try ThemeResolver.sourceTree() }
    let url = URL(fileURLWithPath: theme)
    if url.pathExtension == "allintheme" {
      let pack = try ThemePack.load(from: url)
      let base = (try? ThemeLibrary(directories: [ThemeLibrary.sourceTreeThemesDirectory]))?.packs ?? []
      let library = ThemeLibrary(packs: [pack] + base.filter { $0.id != pack.id })
      return try ThemeResolver(library: library, selectedID: pack.id)
    }
    return try ThemeResolver(library: ThemeLibrary(directories: [url]))
  }

  /// Faces in 13 columns (two to ace) by 4 rows (clubs, diamonds, hearts, spades); the back sits below.
  private static func contactSheet(faces: [CGImage], back: CGImage, size: CGSize, background: ThemeColor) -> CGImage {
    let gap = 8
    let cellW = Int(size.width)
    let cellH = Int(size.height)
    let sheetW = 13 * cellW + 14 * gap
    let sheetH = 5 * cellH + 6 * gap
    let ctx = ThemeImageIO.makeContext(pixelWidth: sheetW, pixelHeight: sheetH)
    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    func rect(column: Int, row: Int) -> CGRect {
      CGRect(
        x: gap + column * (cellW + gap), y: sheetH - (row + 1) * (cellH + gap), width: cellW, height: cellH)
    }
    for card in Card.all {
      ctx.draw(
        faces[Int(card.index)], in: rect(column: Int(card.rank.rawValue), row: Int(card.suit.rawValue)))
    }
    ctx.draw(back, in: rect(column: 0, row: 4))
    return ctx.makeImage()!
  }
}
