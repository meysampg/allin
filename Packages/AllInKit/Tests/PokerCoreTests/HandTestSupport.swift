import Testing

@testable import PokerCore

/// A hand being scripted: the latest state plus every record emitted so far.
struct Played {
  var state: HandState
  var records: [HandRecord]
  let totalChips: Int

  /// Applies `actions` in order, checking chip conservation and the pot after every step.
  mutating func act(_ actions: Action...) throws { try act(actions) }

  mutating func act(_ actions: [Action]) throws {
    for a in actions {
      let step = try HandReducer.apply(a, to: state)
      state = step.state
      records += step.records
      try check()
    }
  }

  func check() throws {
    #expect(state.totalChips == totalChips, "chips not conserved")
    #expect(state.seats.allSatisfy { $0.stack >= 0 })
    if !state.isComplete {
      #expect(state.pot == state.seats.reduce(0) { $0 + state.contribution(of: $1.seat) })
    }
  }

  var showdownSeats: [Int]? {
    for case .showdown(let reveals) in records { return reveals.map(\.seat) }
    return nil
  }

  func stack(_ seat: Int) -> Int { state.seat(seat)!.stack }
  var streetsDealt: [Street] {
    records.compactMap { if case .streetDealt(let s, _, _) = $0 { s } else { nil } }
  }
  var requests: [Int] {
    records.compactMap { if case .actionRequested(let s, _) = $0 { s } else { nil } }
  }
  var returns: [SeatChips] {
    records.compactMap {
      if case .uncalledBetReturned(let s, let a) = $0 { SeatChips(seat: s, amount: a) } else { nil }
    }
  }
  var awards: [PotAwardRecord] {
    records.compactMap { if case .potAwarded(let a) = $0 { a } else { nil } }
  }
}

enum HandScript {
  /// Order in which cards are dealt: clockwise starting left of the button (independent of the reducer).
  static func dealOrder(seats: [Int], button: Int) -> [Int] {
    seats.sorted { key($0, button) < key($1, button) }
  }
  private static func key(_ s: Int, _ button: Int) -> Int { s > button ? s - button : s + 100 - button }

  /// A full deck in which the given hole cards and board land where the reducer will deal them
  /// (two rounds of hole cards, then burn + flop, burn + turn, burn + river). Everything else is filler.
  static func deck(seats: [Int], button: Int, holes: [Int: String], board: String) throws -> [Card] {
    var slots = [Card?](repeating: nil, count: 52)
    let order = dealOrder(seats: seats, button: button)
    for (i, seat) in order.enumerated() {
      guard let h = holes[seat] else { continue }
      let cards = try Card.parseList(h)
      slots[i] = cards[0]
      slots[order.count + i] = cards[1]
    }
    let b = try Card.parseList(board)
    let base = order.count * 2
    // burn, f, f, f, burn, t, burn, r
    let positions = [1, 2, 3, 5, 7]
    for (i, c) in b.enumerated() { slots[base + positions[i]] = c }
    var used = CardSet(slots.compactMap { $0 })
    precondition(used.count == slots.compactMap { $0 }.count, "duplicate cards in script")
    var filler = Card.all.filter { !used.contains($0) }.makeIterator()
    return slots.map { c in
      if let c { return c }
      let f = filler.next()!
      used.insert(f)
      return f
    }
  }

  /// Starts a scripted hand. `stacks` maps seat to stack.
  static func start(
    seatCount: Int = 6, sb: Int = 50, bb: Int = 100, ante: Int = 0, anteKind: AnteKind = .perPlayer,
    button: Int, stacks: [Int: Int], holes: [Int: String] = [:], board: String = "",
    burn: Bool = true
  ) throws -> Played {
    let cfg = try TableConfig(
      seatCount: seatCount, smallBlind: sb, bigBlind: bb, ante: ante, anteKind: anteKind)
    let seats = stacks.keys.sorted()
    let deck = try deck(seats: seats, button: button, holes: holes, board: board)
    let step = try HandReducer.start(
      config: cfg, button: button, stacks: seats.map { SeatStack(seat: $0, stack: stacks[$0]!) }, deck: deck,
      burnsCards: burn)
    let played = Played(state: step.state, records: step.records, totalChips: stacks.values.reduce(0, +))
    try played.check()
    return played
  }
}
