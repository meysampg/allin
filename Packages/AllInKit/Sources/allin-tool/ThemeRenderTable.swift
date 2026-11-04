import CoreGraphics
import CoreText
import Foundation
import TableKit
import ThemeKit

/// `allin-tool theme render-table [--out build/preview/table] [--theme <dir>]`
enum ThemeRenderTableCommand {
  static let usage = """
    USAGE: allin-tool theme render-table [--out <dir>] [--theme <dir>]

    Writes table.png, felt.png, rail.png, dealer.png, chips.png and stacks.png (default: build/preview/table).
    --theme is a .allintheme folder; without it the source-tree hearthwood pack is used.
    """

  static func run(_ args: [String]) async throws -> Int32 {
    if args.contains("-h") || args.contains("--help") {
      print(usage)
      return 0
    }
    var out = "build/preview/table"
    var themePath: String?
    var index = 0
    while index < args.count {
      let arg = args[index]
      switch arg {
      case "--out", "--theme":
        guard index + 1 < args.count else { throw ToolError("\(arg) needs a value") }
        if arg == "--out" { out = args[index + 1] } else { themePath = args[index + 1] }
        index += 2
      default:
        throw ToolError("unknown option '\(arg)'")
      }
    }
    let resolver: ThemeResolver
    if let themePath {
      let pack = try ThemePack.load(from: URL(fileURLWithPath: themePath))
      resolver = ThemeResolver(chain: [pack])
    } else {
      resolver = try ThemeResolver.sourceTree()
    }
    let directory = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let table = TableRenderer(resolver: resolver)
    let size = CGSize(width: 2240, height: 1400)
    try write(table.tableImage(pixelSize: size), "table.png", to: directory)
    try write(table.feltImage(pixelSize: size), "felt.png", to: directory)
    try write(table.railImage(pixelSize: size), "rail.png", to: directory)
    try write(table.dealerButtonImage(pixelDiameter: 256), "dealer.png", to: directory)

    let chips = ChipRenderer(resolver: resolver)
    try write(chipSheet(chips, resolver: resolver), "chips.png", to: directory)
    try write(stackSheet(chips, resolver: resolver), "stacks.png", to: directory)
    return 0
  }

  private static func write(_ image: CGImage, _ name: String, to directory: URL) throws {
    let url = directory.appendingPathComponent(name)
    try ThemeImageIO.writePNG(image, to: url)
    print("wrote \(url.path) (\(image.width)x\(image.height))")
  }

  private static func chipSheet(_ chips: ChipRenderer, resolver: ThemeResolver) -> CGImage {
    let diameter = 200
    let pad = 24
    let all = ChipDenomination.allCases
    let width = all.count * (diameter + pad) + pad
    let height = diameter + 2 * pad
    let context = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    context.setFillColor(resolver.palette[.felt].cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, denomination) in all.enumerated() {
      let image = chips.chipImage(denomination, pixelDiameter: diameter)
      context.draw(image, in: CGRect(x: pad + i * (diameter + pad), y: pad, width: diameter, height: diameter))
    }
    return context.makeImage()!
  }

  private static func stackSheet(_ chips: ChipRenderer, resolver: ThemeResolver) -> CGImage {
    let diameter = 96
    let thickness = 12
    let pad = 24
    let amounts = [7, 135, 1234, 26_480]
    let layouts = amounts.map { ChipStackBuilder.columns(for: $0) }
    let rowHeight = diameter + 10 * thickness + pad
    let width = 4 * (diameter + pad) + pad
    let height = amounts.count * rowHeight + pad
    let context = ThemeImageIO.makeContext(pixelWidth: width, pixelHeight: height)
    context.setFillColor(resolver.palette[.felt].cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var cache: [ChipDenomination: CGImage] = [:]
    for (row, columns) in layouts.enumerated() {
      // Row 0 is drawn at the top of the sheet.
      let baseY = height - (row + 1) * rowHeight + pad / 2
      for (col, stack) in columns.enumerated() {
        for (level, denomination) in stack.enumerated() {
          let image = cache[denomination] ?? chips.chipImage(denomination, pixelDiameter: diameter)
          cache[denomination] = image
          let x = pad + col * (diameter + pad)
          let rect = CGRect(x: x, y: baseY + level * thickness, width: diameter, height: diameter)
          context.draw(image, in: rect)
        }
      }
    }
    return context.makeImage()!
  }
}
