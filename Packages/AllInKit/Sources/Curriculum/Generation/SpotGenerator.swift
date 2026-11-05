import Foundation
import PokerAI
import PokerCore
import PokerEquity

/// Builds `SpotInstance`s from templates by rejection sampling. Same template and seed give the same instance.
public struct SpotGenerator: Sendable {
  public static let maxTries = 2_000
  static let defaultFillers = ["Tom", "Wren", "Edda", "Pell", "Corin", "Ilsa", "Brann", "Odo"]

  let characters: CharacterCatalog

  public init(characters: CharacterCatalog) { self.characters = characters }

  public func generate(_ template: SpotTemplate, seed: UInt64, avoid: Set<String> = []) throws -> SpotInstance {
    try validate(template)
    var reasons: [String: Int] = [:]
    for attempt in 0..<Self.maxTries {
      switch self.attempt(template, seed: seed, attempt: attempt, avoid: avoid) {
      case .success(let instance): return instance
      case .failure(let reject): reasons[reject.reason, default: 0] += 1
      }
    }
    throw SpotGenerationError.exhausted(templateID: template.id, tries: Self.maxTries, reasons: reasons)
  }

  // MARK: Validation

  private func validate(_ template: SpotTemplate) throws {
    let n = template.table.players
    guard (2...9).contains(n) else { throw SpotGenerationError.invalidTemplate("players must be 2...9") }
    guard template.villains.count <= n - 1 else {
      throw SpotGenerationError.invalidTemplate("\(template.villains.count) villains at a \(n)-player table")
    }
    guard template.table.stacksBB.lo >= 1 else { throw SpotGenerationError.invalidTemplate("stacksBB below 1") }
    for villain in template.villains {
      for id in villain.characters where !characters.contains(id) {
        throw SpotGenerationError.invalidTemplate("unknown character '\(id)'")
      }
    }
    let positions = SeatPositions.names(count: n)
    if let wanted = template.hero.position, !wanted.contains(where: positions.contains) {
      throw SpotGenerationError.invalidTemplate("hero position is not used at \(n) players")
    }
    for villain in template.villains {
      if let wanted = villain.position, !wanted.contains(where: positions.contains) {
        throw SpotGenerationError.invalidTemplate("a villain position is not used at \(n) players")
      }
    }
    var fixed = CardSet()
    var count = 0
    for cards in [template.fixed?.hero, template.fixed?.board].compactMap({ $0 }) + (template.fixed?.villains ?? []) {
      count += cards.count
      for card in cards { _ = fixed.insert(card) }
    }
    guard fixed.count == count else { throw SpotGenerationError.invalidTemplate("fixed cards repeat") }
    if let board = template.fixed?.board, board.count > template.board.street.boardCount {
      throw SpotGenerationError.invalidTemplate("fixed board is longer than the \(template.board.street) board")
    }
  }

  // MARK: One attempt

  /// One rejection-sampling attempt; the failure carries the reason ("seats", "board", "hero hand",
  /// "villain hand", "line", "consistency", "situation", "pot", "duplicate").
  func attempt(
    _ template: SpotTemplate, seed: UInt64, attempt: Int, avoid: Set<String> = []
  ) -> Result<SpotInstance, LineReject> {
    var rng = SeededRNG(seed: StableSeed.mix(seed, UInt64(attempt)))
    let n = template.table.players
    let variation = template.variation
    let seats = Array(0..<n)

    // 1. Seats.
    let button = variation.contains(.seats) ? Int.random(in: 0..<n, using: &rng) : 0
    let positions = SeatPositions.assign(button: button, seatCount: n)
    var taken = Set<Int>()
    func pickSeat(_ wanted: [SeatPositionName]?) -> Int? {
      let options: [Int]
      if let wanted {
        options = wanted.compactMap { SeatPositions.seat(of: $0, button: button, seatCount: n) }.filter {
          !taken.contains($0)
        }
      } else {
        options = seats.filter { !taken.contains($0) }
      }
      guard !options.isEmpty else { return nil }
      return options[Int.random(in: 0..<options.count, using: &rng)]
    }
    guard let heroSeat = pickSeat(template.hero.position) else { return .failure(LineReject("seats")) }
    taken.insert(heroSeat)
    var villainSeatOf = [Int?](repeating: nil, count: template.villains.count)
    for (index, villain) in template.villains.enumerated() where villain.position != nil {
      guard let seat = pickSeat(villain.position) else { return .failure(LineReject("seats")) }
      taken.insert(seat)
      villainSeatOf[index] = seat
    }
    for index in template.villains.indices where template.villains[index].position == nil {
      guard let seat = pickSeat(nil) else { return .failure(LineReject("seats")) }
      taken.insert(seat)
      villainSeatOf[index] = seat
    }
    var villainSeats = villainSeatOf.map { $0! }
    // Without villain specs, or in a random line, every other seat plays too.
    if template.villains.isEmpty || template.line.random != nil {
      villainSeats += seats.filter { !taken.contains($0) }
    }
    let involved = Set(villainSeats).union([heroSeat])

    // Characters and names.
    var seatCharacters: [Int: String] = [:]
    var seatNames: [Int: String] = [heroSeat: "You"]
    var named = Set<String>(["You"])
    for (index, villain) in template.villains.enumerated() {
      let seat = villainSeats[index]
      var name: String?
      if !villain.characters.isEmpty {
        let id =
          villain.characters.count == 1
          ? villain.characters[0] : villain.characters[Int.random(in: 0..<villain.characters.count, using: &rng)]
        seatCharacters[seat] = id
        if variation.contains(.villainName) {
          let pool = villain.names ?? characters.names(id)
          name = pool[Int.random(in: 0..<pool.count, using: &rng)]
        } else {
          name = characters.name(id)
        }
      } else if variation.contains(.villainName), let pool = villain.names, !pool.isEmpty {
        name = pool[Int.random(in: 0..<pool.count, using: &rng)]
      }
      if let name, !named.contains(name) {
        seatNames[seat] = name
        named.insert(name)
      }
    }
    var fillers = (template.table.fillerNames ?? Self.defaultFillers).filter { !named.contains($0) }
      .shuffled(using: &rng)
    for seat in seats where seatNames[seat] == nil {
      seatNames[seat] = fillers.isEmpty ? "Seat \(seat + 1)" : fillers.removeFirst()
    }

    // 2. Stacks.
    let blinds = template.table.blinds
    var stackOf: [Int: Int] = [:]
    for seat in seats {
      let range = template.table.stacksBB
      let bbs = variation.contains(.stacks) ? Int.random(in: range.range, using: &rng) : range.lo
      stackOf[seat] = bbs * blinds.big
    }

    // 3. Cards.
    var fixedHero = template.fixed?.hero
    var fixedVillains = template.fixed?.villains ?? []
    var fixedBoard = template.fixed?.board ?? []
    if variation.contains(.suits) {
      var all = (fixedHero ?? []) + fixedBoard
      for cards in fixedVillains { all += cards }
      if !all.isEmpty {
        let suits = Suit.allCases.shuffled(using: &rng)
        func permute(_ cards: [Card]) -> [Card] {
          cards.map { Card(rank: $0.rank, suit: suits[Int($0.suit.rawValue)]) }
        }
        fixedHero = fixedHero.map(permute)
        fixedVillains = fixedVillains.map(permute)
        fixedBoard = permute(fixedBoard)
      }
    }
    var fixedDead = CardSet(fixedBoard)
    for card in fixedHero ?? [] { _ = fixedDead.insert(card) }
    for cards in fixedVillains { for card in cards { _ = fixedDead.insert(card) } }

    guard
      let targetBoard = CardSampler.board(
        matching: template.board, prefix: fixedBoard,
        live: CardSampler.live(excluding: fixedDead), using: &rng)
    else { return .failure(LineReject("board")) }
    var dead = fixedDead.union(CardSet(targetBoard))
    var holes: [Int: [Card]] = [:]

    func deal(_ seat: Int, fixed: [Card]?, predicate: HandPredicate?) -> Bool {
      if let fixed, fixed.count == 2 {
        guard predicate?.matches(hole: fixed, board: targetBoard) ?? true else { return false }
        holes[seat] = fixed
        return true
      }
      let live = CardSampler.live(excluding: dead)
      let combo = CardSampler.pickCombo(from: live, using: &rng) { combo in
        predicate?.matches(hole: combo.cards, board: targetBoard) ?? true
      }
      guard let combo else { return false }
      holes[seat] = combo.cards
      for card in combo.cards { _ = dead.insert(card) }
      return true
    }
    guard deal(heroSeat, fixed: fixedHero, predicate: template.hero.hand) else {
      return .failure(LineReject("hero hand"))
    }
    for (index, villain) in template.villains.enumerated() {
      let fixed = index < fixedVillains.count ? fixedVillains[index] : nil
      guard deal(villainSeats[index], fixed: fixed, predicate: villain.hand) else {
        return .failure(LineReject("villain hand"))
      }
    }
    for seat in seats where holes[seat] == nil {
      guard deal(seat, fixed: nil, predicate: nil) else { return .failure(LineReject("seats")) }
    }
    var allDead = CardSet(targetBoard)
    for seat in seats { for card in holes[seat]! { _ = allDead.insert(card) } }
    var restPool = CardSampler.live(excluding: allDead).shuffled(using: &rng)
    var fullBoard = targetBoard
    while fullBoard.count < 5 { fullBoard.append(restPool.removeFirst()) }

    guard
      let deck = DeckLayout.deck(
        button: button, seats: seats, burnsCards: true, holes: holes, board: fullBoard, rest: restPool),
      let config = try? TableConfig(seatCount: n, smallBlind: blinds.small, bigBlind: blinds.big, ante: blinds.ante),
      let start = try? HandReducer.start(
        config: config, button: button, stacks: seats.map { SeatStack(seat: $0, stack: stackOf[$0]!) }, deck: deck)
    else { return .failure(LineReject("deal")) }

    // 4. Line.
    var strategies: [Int: any StrategyProvider] = [:]
    let baseline = BaselineStrategy()
    for seat in seats {
      strategies[seat] = seatCharacters[seat].flatMap { characters.strategy($0) } ?? baseline
    }
    let plan = LinePlan(
      template: template, heroSeat: heroSeat, villainSeats: villainSeats, involved: involved,
      strategies: strategies, characterSeats: Set(seatCharacters.keys), bigBlind: blinds.big)
    let line: LineResult
    switch LineBuilder.build(plan: plan, start: start, using: &rng) {
    case .success(let built): line = built
    case .failure(let reject): return .failure(reject)
    }

    // 5. Checks.
    let state = line.state
    if let situation = template.situation {
      guard let actor = state.seatToAct,
        let context = DecisionContext.make(from: state, for: actor, history: line.history),
        situation.matches(context)
      else { return .failure(LineReject("situation")) }
    }
    if let potBB = template.potBB {
      guard potBB.range.contains(Double(state.pot) / Double(blinds.big)) else { return .failure(LineReject("pot")) }
    }
    let hash = Self.canonicalHash(
      id: template.id, n: n, button: button, hero: heroSeat, stacks: stackOf, holes: holes, board: fullBoard,
      actions: line.actions)
    if avoid.contains(hash) { return .failure(LineReject("duplicate")) }

    var reveal: Set<Int> = [heroSeat]
    if template.reveal == .all || template.evaluation.method == .showdownWinner { reveal.formUnion(involved) }
    return .success(
      SpotInstance(
        templateID: template.id, seed: seed, attempt: attempt, config: config, button: button, heroSeat: heroSeat,
        villainSeats: villainSeats, seatNames: seatNames, seatCharacters: seatCharacters, positions: positions,
        holeCards: holes, fullBoard: fullBoard, actions: line.actions, state: state,
        log: EventLog(handID: HandID(seed), steps: line.steps), history: line.history, reveal: reveal,
        instanceHash: hash))
  }

  static func canonicalHash(
    id: String, n: Int, button: Int, hero: Int, stacks: [Int: Int], holes: [Int: [Card]], board: [Card],
    actions: [Action]
  ) -> String {
    let seatList = stacks.keys.sorted()
    let stackText = seatList.map { "\($0)=\(stacks[$0]!)" }.joined(separator: ",")
    let cardText = holes.keys.sorted().map { "\($0)=\(Card.format(holes[$0]!))" }.joined(separator: ",")
    let text =
      "\(id)|n\(n)|b\(button)|h\(hero)|s:\(stackText)|c:\(cardText)|B:\(Card.format(board))|a:"
      + actions.map(actionText).joined(separator: ",")
    return InstanceHash.hex(text)
  }
}
