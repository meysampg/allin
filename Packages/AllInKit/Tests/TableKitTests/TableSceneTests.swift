import PokerCore
import SpriteKit
import Testing
import ThemeKit

@testable import TableKit

@MainActor @Suite struct TableSceneTests {
  private func makeScene(seatCount: Int = 6, options: TableSceneOptions? = nil) throws -> TableScene {
    var options = options ?? TableSceneOptions()
    options.driver = .immediate
    let scene = TableScene(resolver: .codeDrawn, options: options)
    let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
    scene.configure(table: config, seats: TableDemo.seats(count: seatCount), heroSeat: 0)
    return scene
  }

  @Test func playsAFullHandInOrder() async throws {
    let scene = try makeScene()
    let events = try TableDemo.loggedHand(seed: 4).filtered(for: .seat(0))
    var seen: [Int] = []
    scene.onPresented = { event, _ in seen.append(event.seq) }
    scene.enqueue(contentsOf: events)
    await scene.waitUntilIdle()
    #expect(seen == events.map(\.seq))
    #expect(scene.presentedSnapshot.isHandOver)
    #expect(scene.isIdle)
    #expect(scene.nodeCount < 300)
  }

  @Test func nodeBudgetHoldsForNineSeats() async throws {
    let scene = try makeScene(seatCount: 9)
    scene.enqueue(contentsOf: try TableDemo.loggedHand(seed: 9, seatCount: 9).filtered(for: .seat(0)))
    await scene.waitUntilIdle()
    #expect(scene.nodeCount < 300)
  }

  @Test func snapshotsArriveWithTheirEvents() async throws {
    let scene = try makeScene()
    let events = try TableDemo.loggedHand(seed: 6).filtered(for: .seat(0))
    var boardCounts: [Int] = []
    scene.onPresented = { _, snapshot in boardCounts.append(snapshot.board.count) }
    scene.enqueue(contentsOf: events)
    await scene.waitUntilIdle()
    #expect(boardCounts == boardCounts.sorted())
    #expect(boardCounts.last == 5)
  }

  @Test func twoHandsBackToBackResetTheBoard() async throws {
    let scene = try makeScene()
    scene.enqueue(contentsOf: try TableDemo.loggedHand(seed: 1).filtered(for: .seat(0)))
    await scene.waitUntilIdle()
    #expect(scene.presentedSnapshot.board.count == 5)
    let second = try TableDemo.loggedHand(seed: 2).filtered(for: .seat(0))
    var boardAfterStart: Int?
    scene.onPresented = { event, snapshot in
      if case .handStarted = event.event { boardAfterStart = snapshot.board.count }
    }
    scene.enqueue(contentsOf: second)
    await scene.waitUntilIdle()
    #expect(boardAfterStart == 0)
    #expect(scene.presentedSnapshot.handsStarted == 2)
    #expect(scene.presentedSnapshot.isHandOver)
  }

  @Test func miniatureHidesSeatLabels() async throws {
    var options = TableSceneOptions()
    options.mode = .miniature
    let scene = try makeScene(options: options)
    scene.enqueue(contentsOf: try TableDemo.loggedHand(seed: 3).filtered(for: .seat(0)))
    await scene.waitUntilIdle()
    let normal = try makeScene()
    normal.enqueue(contentsOf: try TableDemo.loggedHand(seed: 3).filtered(for: .seat(0)))
    await normal.waitUntilIdle()
    #expect(labelNodes(in: normal).contains { !isEffectivelyHidden($0) && ($0.text ?? "").contains("Grumli") })
    #expect(!labelNodes(in: scene).contains { !isEffectivelyHidden($0) && ($0.text ?? "").contains("Grumli") })
  }

  @Test func spotModeShowsASnapshotWithoutAnimation() async throws {
    var options = TableSceneOptions()
    options.mode = .spot
    let scene = try makeScene(options: options)
    var table = try TableModel(
      config: TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2), seats: TableDemo.seats(count: 6), heroSeat: 0)
    for event in try TableDemo.loggedHand(seed: 8).filtered(for: .seat(0)).prefix(12) { _ = table.apply(event) }
    scene.show(table.snapshot)
    #expect(scene.presentedSnapshot == table.snapshot)
    #expect(scene.isIdle)
  }

  @Test func hudAndDeckSettingsApplyImmediately() async throws {
    let scene = try makeScene()
    scene.enqueue(contentsOf: Array(try TableDemo.loggedHand(seed: 12).filtered(for: .seat(0)).prefix(8)))
    await scene.waitUntilIdle()
    scene.hud = .off
    scene.hud = .full
    scene.fourColorDeck = true
    scene.timing = AnimationTiming(speedFactor: 0.3, reduceMotion: true)
    #expect(scene.timing.reduceMotion)
  }

  @Test func cancelAnimationsJumpsToTheLatestState() async throws {
    var options = TableSceneOptions()
    options.timing = AnimationTiming(speedFactor: 0.01)
    let scene = TableScene(resolver: .codeDrawn, options: options)
    let config = try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2)
    scene.configure(table: config, seats: TableDemo.seats(count: 6), heroSeat: 0)
    let events = try TableDemo.loggedHand(seed: 5).filtered(for: .seat(0))
    scene.enqueue(contentsOf: events)
    scene.cancelAnimations()
    #expect(scene.presentedSnapshot.isHandOver)
    await scene.waitUntilIdle()
  }

  @Test(arguments: [false, true])
  func animatedDriverPresentsEveryEvent(reduceMotion: Bool) async throws {
    var options = TableSceneOptions()
    options.timing = AnimationTiming(speedFactor: 0.02, reduceMotion: reduceMotion)
    let scene = TableScene(resolver: .codeDrawn, options: options)
    let config = try TableConfig(seatCount: 6, smallBlind: 1, bigBlind: 2)
    scene.configure(table: config, seats: TableDemo.seats(count: 6), heroSeat: 0)
    let events = try TableDemo.loggedHand(seed: 14).filtered(for: .seat(0))
    var seen: [Int] = []
    scene.onPresented = { event, _ in seen.append(event.seq) }
    scene.enqueue(contentsOf: events)
    await scene.waitUntilIdle()
    #expect(seen == events.map(\.seq))
    #expect(scene.presentedSnapshot.isHandOver)
  }

  @Test func runeShaderCompilesAndRenders() throws {
    let ring = TableRuneRing(size: CGSize(width: 400, height: 200), resolver: .codeDrawn, reduceMotion: false)
    let view = SKView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    let scene = SKScene(size: CGSize(width: 400, height: 200))
    scene.addChild(ring)
    ring.position = CGPoint(x: 200, y: 100)
    view.presentScene(scene)
    let texture = try #require(view.texture(from: ring))
    let image = texture.cgImage()
    #expect(image.width > 0 && image.height > 0)
    // The shader paints the marks in the rune color (cyan: blue above red); the unshaded ring would be white.
    let context = ThemeImageIO.makeContext(pixelWidth: image.width, pixelHeight: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    var cyan = 0
    for index in 0..<(image.width * image.height) {
      let base = index * 4
      if bytes[base + 3] > 40 && Int(bytes[base + 2]) > Int(bytes[base]) + 30 { cyan += 1 }
    }
    #expect(cyan > 50, "shader output pixels: \(cyan)")
  }

  private func labelNodes(in node: SKNode) -> [SKLabelNode] {
    var result: [SKLabelNode] = []
    if let label = node as? SKLabelNode { result.append(label) }
    for child in node.children { result += labelNodes(in: child) }
    return result
  }

  private func isEffectivelyHidden(_ node: SKNode) -> Bool {
    var current: SKNode? = node
    while let item = current {
      if item.isHidden { return true }
      current = item.parent
    }
    return false
  }
}
