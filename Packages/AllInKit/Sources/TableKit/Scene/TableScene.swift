import CoreGraphics
import Foundation
import PokerCore
import SpriteKit
import ThemeKit

/// The poker table: felt, rune ring, seats, board, pot and dealer button, animated from the event stream.
///
/// Events are reduced by a ``TableModel`` as soon as they are enqueued; the animations then play in order and
/// `onPresented` reports each event once its animation has finished.
@MainActor public final class TableScene: SKScene {
  public nonisolated static let baseSize = CGSize(width: 1120, height: 700)

  public var onPresented: (@MainActor (LoggedEvent, TableSnapshot) -> Void)?
  public private(set) var presentedSnapshot = TableSnapshot()

  public var timing: AnimationTiming {
    didSet {
      if timing.reduceMotion != oldValue.reduceMotion { rebuildRuneRing() }
      sync(presentedSnapshot)
    }
  }

  public var hud: TableHUD {
    didSet { sync(presentedSnapshot) }
  }

  public var fourColorDeck: Bool {
    didSet {
      cardCache.fourColor = fourColorDeck
      sync(presentedSnapshot)
    }
  }

  public var isIdle: Bool { queue.isIdle }

  /// Every node in the scene, recursively (the scene itself included).
  public var nodeCount: Int { Self.count(self) }

  private let resolver: ThemeResolver
  private let soundBank: SoundBank?
  private let mode: TableSceneMode
  private let queue: AnimationQueue
  private let cardCache: CardTextureCache
  private let chipCache: ChipTextureCache
  private let tableRenderer: TableRenderer

  private let world = SKNode()
  private let background = SKSpriteNode()
  private var runeRing: TableRuneRing
  private let shoe = SKSpriteNode()
  private let board = BoardNode()
  private let pot = PotNode()
  private let dealerButton: DealerButtonNode
  private let ribbon = SKLabelNode()
  private var seatNodes: [Int: SeatNode] = [:]
  private var seatPoints: [Int: CGPoint] = [:]
  private var model: TableModel?
  private var heroSeat: Int?
  private var generation = 0

  public init(
    size: CGSize = TableScene.baseSize, resolver: ThemeResolver, options: TableSceneOptions = TableSceneOptions(),
    soundBank: SoundBank? = nil
  ) {
    self.resolver = resolver
    self.soundBank = soundBank
    mode = options.mode
    var timing = options.timing
    if options.mode == .miniature { timing.speedFactor = 0.5 }
    self.timing = timing
    hud = options.hud
    fourColorDeck = options.fourColorDeck
    queue = AnimationQueue(driver: options.mode == .spot ? .immediate : options.driver)
    cardCache = CardTextureCache(
      renderer: CardRenderer(
        resolver: resolver,
        options: CardRenderOptions(pixelSize: CGSize(width: 150, height: 210), fourColor: options.fourColorDeck)))
    chipCache = ChipTextureCache(renderer: ChipRenderer(resolver: resolver), pixelDiameter: 64)
    tableRenderer = TableRenderer(resolver: resolver)
    dealerButton = DealerButtonNode(renderer: TableRenderer(resolver: resolver))
    runeRing = Self.makeRuneRing(resolver: resolver, reduceMotion: timing.reduceMotion)
    super.init(size: size)
    scaleMode = .aspectFit
    anchorPoint = .zero
    backgroundColor = SKColor(
      srgbRed: resolver.palette[.night].red, green: resolver.palette[.night].green,
      blue: resolver.palette[.night].blue, alpha: 1)
    buildStaticLayers()
  }

  @available(*, unavailable) required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Public API

  /// Resets the model and the seat nodes for a new table.
  public func configure(table: TableConfig, seats: [TableSeatInfo], heroSeat: Int?) {
    cancelAnimations()
    self.heroSeat = heroSeat
    let model = TableModel(config: table, seats: seats, heroSeat: heroSeat)
    self.model = model
    buildSeats(infos: model.snapshot.seats.map(\.info), heroSeat: heroSeat)
    presentedSnapshot = model.snapshot
    sync(presentedSnapshot)
  }

  public func enqueue(_ event: LoggedEvent) {
    guard model != nil else { return }
    let cues = model!.apply(event)
    let snapshot = model!.snapshot
    let token = generation
    queue.enqueue { [weak self] in
      await self?.present(event, cues: cues, snapshot: snapshot, token: token)
    }
  }

  public func enqueue(contentsOf events: [LoggedEvent]) {
    for event in events { enqueue(event) }
  }

  public func waitUntilIdle() async {
    await queue.waitUntilIdle()
  }

  /// Shows a position without animation (the `.spot` mode). Builds the seats from the snapshot when needed.
  public func show(_ snapshot: TableSnapshot) {
    let infos = snapshot.seats.map(\.info)
    if Set(seatNodes.keys) != Set(infos.map(\.seat)) {
      heroSeat = infos.first(where: \.isHero)?.seat
      buildSeats(infos: infos, heroSeat: heroSeat)
    }
    sync(snapshot)
    presentedSnapshot = snapshot
  }

  /// Drops the animations that have not played and jumps to the latest state. `onPresented` is not called for
  /// the dropped events.
  public func cancelAnimations() {
    generation += 1
    queue.cancelAll()
    removeAllActionsRecursively(world)
    if let model { presentedSnapshot = model.snapshot }
    sync(presentedSnapshot)
  }

  // MARK: Presenting

  private var animates: Bool { queue.driver == .spriteKit && mode != .spot }

  private func present(_ event: LoggedEvent, cues: [TableCue], snapshot: TableSnapshot, token: Int) async {
    guard token == generation else { return }
    if animates {
      for cue in cues {
        await play(cue, snapshot: snapshot)
        guard token == generation else { return }
      }
    }
    sync(snapshot)
    presentedSnapshot = snapshot
    onPresented?(event, snapshot)
  }

  private func play(_ cue: TableCue, snapshot: TableSnapshot) async {
    switch cue {
    case .newHand(let button, _): await playNewHand(button: button)
    case .postBlind(let seat, _): await playBet(seat: seat, snapshot: snapshot)
    case .dealHoles(let order): await playDealHoles(order: order)
    case .revealHero(let cards): await playRevealHero(cards)
    case .actionRequested: break
    case .act(let seat, let action, let isAllIn):
      if isAllIn {
        runeRing.pulse()
        sound(.allIn)
      }
      if action != .check { await playBet(seat: seat, snapshot: snapshot, quiet: isAllIn) }
    case .fold(let seat): await playFold(seat: seat)
    case .returnBet(let seat, _): await playReturnBet(seat: seat)
    case .collectBets: await playCollect()
    case .dealBoard(_, let cards): await playDealBoard(cards: cards, snapshot: snapshot)
    case .showdown(let reveals): await playShowdown(reveals, snapshot: snapshot)
    case .award(let info): await playAward(info)
    case .handEnded: await wait(timing.duration(.handEndPause))
    }
  }

  // MARK: Cue animations

  private func playNewHand(button: Int) async {
    guard let target = buttonPosition(forSeat: button) else { return }
    let duration = timing.duration(.chipSlide)
    if dealerButton.isHidden || timing.reduceMotion {
      dealerButton.isHidden = false
      dealerButton.position = target
      dealerButton.alpha = 0
      start(dealerButton, .fadeIn(withDuration: timing.duration(.crossfade)))
      await wait(timing.duration(.crossfade))
    } else {
      start(dealerButton, .move(to: target, duration: duration))
      await wait(duration)
    }
  }

  private func playBet(seat: Int, snapshot: TableSnapshot, quiet: Bool = false) async {
    guard let node = seatNodes[seat], let state = snapshot.seat(seat), state.committed > 0 else { return }
    node.betStack.setAmount(state.committed, textures: chipTextures)
    node.betStack.isHidden = false
    let duration = timing.duration(.chipSlide)
    startMove(node.betStack, from: .zero, to: node.betOffset, duration: duration)
    if !quiet { sound(.chipBet) }
    await wait(duration)
  }

  private func playDealHoles(order: [Int]) async {
    for node in seatNodes.values {
      for sprite in node.cardSprites { sprite.isHidden = true }
    }
    var dealt: [Int: Int] = [:]
    for seat in order {
      guard let node = seatNodes[seat] else { continue }
      let index = dealt[seat, default: 0]
      dealt[seat] = index + 1
      guard node.cardSprites.indices.contains(index) else { continue }
      let sprite = node.cardSprites[index]
      sprite.texture = cardCache.backTexture()
      sprite.isHidden = false
      sprite.removeAllActions()
      startMove(
        sprite, from: CGPoint(x: shoe.position.x - node.position.x, y: shoe.position.y - node.position.y),
        to: node.restPosition(index), duration: timing.dealTravel, spin: true)
      sound(.cardDeal)
      await wait(timing.duration(.dealCard))
    }
    await wait(timing.dealTravel)
  }

  private func playRevealHero(_ faces: [Card]) async {
    guard let hero = heroSeat, let node = seatNodes[hero], faces.count == 2 else { return }
    for (index, sprite) in node.cardSprites.enumerated() {
      flip(sprite, to: cardCache.texture(for: faces[index]))
    }
    sound(.cardFlip)
    await wait(timing.duration(.flip))
  }

  private func playFold(seat: Int) async {
    guard let node = seatNodes[seat] else { return }
    let duration = timing.duration(.fold)
    for sprite in node.cardSprites where !sprite.isHidden {
      if timing.reduceMotion {
        start(sprite, .fadeOut(withDuration: duration))
      } else {
        let toward = CGPoint(x: -node.position.x * 0.12, y: (SeatLayout.tableCenterWorld.y - node.position.y) * 0.12)
        let slide = SKAction.moveBy(x: toward.x, y: toward.y, duration: duration)
        start(sprite, .group([slide, .fadeOut(withDuration: duration)]))
      }
    }
    await wait(duration)
  }

  private func playReturnBet(seat: Int) async {
    guard let node = seatNodes[seat], node.betStack.amount > 0 else { return }
    let duration = timing.duration(.chipSlide)
    if timing.reduceMotion {
      start(node.betStack, .fadeOut(withDuration: duration))
    } else {
      start(node.betStack, .group([.move(to: .zero, duration: duration), .fadeOut(withDuration: duration)]))
    }
    sound(.chipStack)
    await wait(duration)
  }

  private func playCollect() async {
    let duration = timing.duration(.collect)
    var any = false
    for node in seatNodes.values where node.betStack.amount > 0 {
      any = true
      let target = CGPoint(x: potWorld.x - node.position.x, y: potWorld.y - node.position.y)
      if timing.reduceMotion {
        start(node.betStack, .fadeOut(withDuration: duration))
      } else {
        start(node.betStack, .group([.move(to: target, duration: duration), .fadeOut(withDuration: duration)]))
      }
    }
    if any {
      sound(.potSweep)
      await wait(duration)
    }
  }

  private func playDealBoard(cards: [Card], snapshot: TableSnapshot) async {
    let first = max(snapshot.board.count - cards.count, 0)
    runeRing.pulse()
    let slide = timing.duration(.boardSlide)
    for (offset, card) in cards.enumerated() {
      let index = first + offset
      guard board.slots.indices.contains(index) else { continue }
      let sprite = board.slots[index]
      sprite.removeAllActions()
      sprite.texture = cardCache.backTexture()
      sprite.isHidden = false
      sprite.colorBlendFactor = 0
      startMove(
        sprite, from: CGPoint(x: shoe.position.x - board.position.x, y: shoe.position.y - board.position.y),
        to: BoardNode.restPosition(index), duration: slide)
      sound(.cardDeal)
      await wait(timing.duration(.dealCard))
      _ = card
    }
    await wait(slide)
    for (offset, card) in cards.enumerated() {
      let index = first + offset
      guard board.slots.indices.contains(index) else { continue }
      flip(board.slots[index], to: cardCache.texture(for: card))
    }
    sound(.cardFlip)
    await wait(timing.duration(.flip))
  }

  private func playShowdown(_ reveals: [Reveal], snapshot: TableSnapshot) async {
    for reveal in reveals {
      guard let node = seatNodes[reveal.seat], reveal.holeCards.count == 2 else { continue }
      for (index, sprite) in node.cardSprites.enumerated() {
        sprite.isHidden = false
        flip(sprite, to: cardCache.texture(for: reveal.holeCards[index]))
      }
    }
    if !reveals.isEmpty { sound(.cardFlip) }
    await wait(timing.duration(.flip))
    ribbon.alpha = 0
    ribbon.text = ribbonText(snapshot)
    start(ribbon, .fadeIn(withDuration: timing.duration(.crossfade)))
    let lift = timing.duration(.showdownLift)
    if !timing.reduceMotion {
      for slot in board.slots where !slot.isHidden { start(slot, .moveBy(x: 0, y: 4, duration: lift)) }
    }
    await wait(lift)
  }

  private func playAward(_ info: PotAwardInfo) async {
    let duration = timing.duration(.award)
    var flying: [SKSpriteNode] = []
    for share in info.shares where share.amount > 0 {
      guard let node = seatNodes[share.seat] else { continue }
      let denomination = ChipStackBuilder.breakdown(share.amount).first?.denomination ?? .one
      let chip = SKSpriteNode(texture: chipCache.texture(for: denomination))
      chip.size = CGSize(width: ChipStackNode.chipSize + 6, height: ChipStackNode.chipSize + 6)
      chip.zPosition = 40
      world.addChild(chip)
      flying.append(chip)
      startMove(chip, from: potWorld, to: node.position, duration: duration)
    }
    if !flying.isEmpty { sound(.win) }
    await wait(duration)
    for chip in flying { chip.removeFromParent() }
  }

  // MARK: Sync (end states)

  private var chipTextures: ChipTextureCache { chipCache }

  /// Sets every node to the snapshot. Idempotent; the animations only decorate the way there.
  private func sync(_ snapshot: TableSnapshot) {
    let textures = SeatTextures(cards: cardCache, chips: chipCache)
    let sets = showdownSets(snapshot)
    let breathing = animates && !timing.reduceMotion
    for (index, node) in seatNodes {
      guard let seat = snapshot.seat(index) else { continue }
      node.apply(
        seat, hud: hud, mode: mode, breathing: breathing, textures: textures, lifted: sets.heldLift,
        dimmed: sets.heldDim)
    }
    for (index, slot) in board.slots.enumerated() {
      slot.removeAllActions()
      slot.position = BoardNode.restPosition(index)
      slot.xScale = 1
      slot.alpha = 1
      guard index < snapshot.board.count else {
        slot.isHidden = true
        continue
      }
      let card = snapshot.board[index]
      slot.isHidden = false
      slot.texture = cardCache.texture(for: card)
      slot.colorBlendFactor = 0
      if sets.boardLift.contains(card) {
        slot.position.y += 8
        slot.color = SKColor(srgbRed: 0.85, green: 0.64, blue: 0.25, alpha: 1)
        slot.colorBlendFactor = 0.18
      } else if !sets.boardLift.isEmpty {
        slot.color = .black
        slot.colorBlendFactor = 0.45
      }
    }
    let committed = snapshot.seats.reduce(0) { $0 + $1.committed }
    pot.set(settled: max(snapshot.potTotal - committed, 0), total: snapshot.potTotal, textures: chipCache)
    if let button = snapshot.button, let position = buttonPosition(forSeat: button) {
      dealerButton.removeAllActions()
      dealerButton.isHidden = false
      dealerButton.alpha = 1
      dealerButton.position = position
    } else {
      dealerButton.isHidden = true
    }
    ribbon.removeAllActions()
    ribbon.alpha = 1
    ribbon.text = ribbonText(snapshot)
    ribbon.isHidden = ribbon.text == nil || mode == .miniature
  }

  private struct ShowdownSets {
    var boardLift: Set<Card> = []
    var heldLift: Set<Card> = []
    var heldDim: Set<Card> = []
  }

  private func showdownSets(_ snapshot: TableSnapshot) -> ShowdownSets {
    var sets = ShowdownSets()
    guard let best = snapshot.showdown.max(by: { $0.value < $1.value }) else { return sets }
    sets.boardLift = Set(best.bestFive)
    for reveal in snapshot.showdown {
      sets.heldLift.formUnion(reveal.holeCards.filter { reveal.bestFive.contains($0) })
      sets.heldDim.formUnion(reveal.holeCards.filter { !reveal.bestFive.contains($0) })
    }
    return sets
  }

  private func ribbonText(_ snapshot: TableSnapshot) -> String? {
    guard let best = snapshot.showdown.max(by: { $0.value < $1.value }) else { return nil }
    let name = snapshot.seat(best.seat)?.info.name ?? "Seat \(best.seat + 1)"
    return "\(name): \(HandDescription.describe(best.value))"
  }

  // MARK: Construction

  private func buildStaticLayers() {
    addChild(world)
    let unit = size.width / Self.baseSize.width
    world.setScale(unit)

    let base = Self.baseSize
    let pixels = mode == .miniature ? CGSize(width: base.width / 2, height: base.height / 2) : base
    background.texture = SKTexture(cgImage: tableRenderer.tableImage(pixelSize: pixels))
    background.size = base
    background.position = CGPoint(x: base.width / 2, y: base.height / 2)
    background.zPosition = 0
    world.addChild(background)

    positionRuneRing()
    world.addChild(runeRing)

    shoe.texture = cardCache.backTexture()
    shoe.size = CGSize(width: 34, height: 48)
    shoe.position = worldPoint(CGPoint(x: 0.5, y: 0.035))
    shoe.zPosition = 3
    world.addChild(shoe)

    board.position = worldPoint(SeatLayout.boardCenter)
    world.addChild(board)

    pot.position = worldPoint(SeatLayout.potPoint)
    world.addChild(pot)

    world.addChild(dealerButton)

    ribbon.fontName = "Georgia-BoldItalic"
    ribbon.fontSize = 17
    ribbon.fontColor = SKColor(srgbRed: 0.95, green: 0.8, blue: 0.4, alpha: 1)
    ribbon.verticalAlignmentMode = .center
    ribbon.position = worldPoint(CGPoint(x: 0.5, y: 0.575))
    ribbon.zPosition = 30
    ribbon.isHidden = true
    world.addChild(ribbon)
  }

  private func positionRuneRing() {
    let felt = TableRenderer.feltRect
    let base = Self.baseSize
    runeRing.position = CGPoint(x: (felt.midX) * base.width, y: (1 - felt.midY) * base.height)
    runeRing.zPosition = 1
  }

  @MainActor private static func makeRuneRing(resolver: ThemeResolver, reduceMotion: Bool) -> TableRuneRing {
    // The rune marks sit at 0.78...0.96 of the sprite radius, so the sprite is a little larger than the felt oval.
    let felt = TableRenderer.feltRect
    let size = CGSize(width: felt.width * baseSize.width * 1.06, height: felt.height * baseSize.height * 1.06)
    return TableRuneRing(size: size, resolver: resolver, reduceMotion: reduceMotion)
  }

  private func rebuildRuneRing() {
    runeRing.removeFromParent()
    runeRing = Self.makeRuneRing(resolver: resolver, reduceMotion: timing.reduceMotion)
    positionRuneRing()
    world.addChild(runeRing)
  }

  private func buildSeats(infos: [TableSeatInfo], heroSeat: Int?) {
    for node in seatNodes.values { node.removeFromParent() }
    seatNodes = [:]
    let normalized = SeatLayout.positions(seatCount: infos.count, heroSeat: heroSeat)
    seatPoints = [:]
    for info in infos {
      guard let point = normalized[info.seat] else { continue }
      let position = worldPoint(point)
      let bet = worldPoint(SeatLayout.betPoint(for: point))
      let node = SeatNode(
        info: info, betOffset: CGPoint(x: bet.x - position.x, y: bet.y - position.y), resolver: resolver)
      node.position = position
      node.zPosition = 10
      world.addChild(node)
      seatNodes[info.seat] = node
      seatPoints[info.seat] = position
    }
  }

  // MARK: Helpers

  private var potWorld: CGPoint { worldPoint(SeatLayout.potPoint) }

  private func worldPoint(_ normalized: CGPoint) -> CGPoint {
    CGPoint(x: normalized.x * Self.baseSize.width, y: (1 - normalized.y) * Self.baseSize.height)
  }

  /// Just left of the seat's medallion.
  private func buttonPosition(forSeat seat: Int) -> CGPoint? {
    guard let point = seatPoints[seat] else { return nil }
    return CGPoint(x: point.x - 48, y: point.y - 2)
  }

  private func sound(_ event: SoundEvent) {
    guard mode != .miniature else { return }
    soundBank?.play(event)
  }

  private func wait(_ seconds: TimeInterval) async {
    guard seconds > 0 else { return }
    try? await Task.sleep(for: .seconds(seconds))
  }

  /// Starts a move from `from` to `to` (a fade-in at `to` under reduce motion). Does not wait.
  private func startMove(_ node: SKNode, from: CGPoint, to: CGPoint, duration: TimeInterval, spin: Bool = false) {
    node.removeAllActions()
    node.alpha = 1
    if timing.reduceMotion {
      node.position = to
      node.alpha = 0
      start(node, .fadeIn(withDuration: duration))
      return
    }
    let finalAngle = node.zRotation
    node.position = from
    var actions: [SKAction] = [.move(to: to, duration: duration)]
    if spin {
      node.zRotation = finalAngle + .pi * 2
      actions.append(.rotate(toAngle: finalAngle, duration: duration))
    }
    start(node, .group(actions))
  }

  /// Squashes a card to a line, swaps the face and expands it again; instant under reduce motion.
  private func flip(_ sprite: SKSpriteNode, to texture: SKTexture) {
    let half = timing.duration(.flip) / 2
    sprite.removeAllActions()
    if half <= 0 {
      sprite.texture = texture
      return
    }
    start(
      sprite,
      .sequence([.scaleX(to: 0, duration: half), .setTexture(texture), .scaleX(to: 1, duration: half)]))
  }

  private func start(_ node: SKNode, _ action: SKAction) {
    node.run(action)
  }

  private func removeAllActionsRecursively(_ node: SKNode) {
    node.removeAllActions()
    for child in node.children { removeAllActionsRecursively(child) }
  }

  private static func count(_ node: SKNode) -> Int {
    node.children.reduce(1) { $0 + count($1) }
  }
}

extension SeatLayout {
  static var tableCenterWorld: CGPoint {
    CGPoint(x: tableCenter.x * TableScene.baseSize.width, y: (1 - tableCenter.y) * TableScene.baseSize.height)
  }
}
