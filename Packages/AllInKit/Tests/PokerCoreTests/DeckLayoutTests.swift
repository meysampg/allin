import Testing

@testable import PokerCore

@Suite struct DeckLayoutTests {
  private func parse(_ text: String) -> [Card] { try! Card.parseList(text) }

  /// Distinct hole cards per seat taken from the front of the index-ordered deck, skipping `board`.
  private func holes(seats: [Int], board: [Card]) -> [Int: [Card]] {
    var pool = Card.all.filter { !board.contains($0) }.reversed().makeIterator()
    var result: [Int: [Card]] = [:]
    for seat in seats { result[seat] = [pool.next()!, pool.next()!] }
    return result
  }

  @Test(arguments: [2, 6, 9], [true, false])
  func dealsRequestedHolesAndBoard(seatCount: Int, burns: Bool) throws {
    let seats = Array(0..<seatCount)
    let board = parse("Ah Kd 7c 2s 9h")
    let holes = holes(seats: seats, board: board)
    let used = CardSet(board + holes.values.flatMap { $0 })
    let rest = Card.all.filter { !used.contains($0) }
    let button = seatCount - 1
    let deck = try #require(
      DeckLayout.deck(button: button, seats: seats, burnsCards: burns, holes: holes, board: board, rest: rest))
    #expect(deck.count == 52 && CardSet(deck).count == 52)

    let config = try TableConfig(seatCount: seatCount, smallBlind: 1, bigBlind: 2)
    var state = try HandReducer.start(
      config: config, button: button, stacks: seats.map { SeatStack(seat: $0, stack: 100) }, deck: deck,
      burnsCards: burns
    ).state
    for seat in seats { #expect(state.seat(seat)?.holeCards == holes[seat]) }
    var guardCount = 0
    while !state.isComplete && guardCount < 100 {
      guardCount += 1
      let action: Action = state.legalActions?.canCheck == true ? .check : .call
      state = try HandReducer.apply(action, to: state).state
    }
    #expect(state.isComplete)
    #expect(state.board == board)
  }

  @Test func partialBoardLeavesLaterCardsToRest() throws {
    let seats = [0, 1]
    let board = parse("Ah Kd 7c")
    let holes = holes(seats: seats, board: board)
    let used = CardSet(board + holes.values.flatMap { $0 })
    let rest = Card.all.filter { !used.contains($0) }
    let deck = try #require(
      DeckLayout.deck(button: 0, seats: seats, burnsCards: true, holes: holes, board: board, rest: rest))
    // Positions: 4 holes, burn, flop, burn, turn, burn, river.
    #expect(Array(deck[5..<8]) == board)
    #expect(deck[4] == rest[0])
    #expect(deck[8] == rest[1])
  }

  @Test func rejectsDuplicates() {
    let seats = [0, 1]
    let board = parse("Ah Kd 7c")
    var holes = holes(seats: seats, board: board)
    let used = CardSet(board + holes.values.flatMap { $0 })
    let rest = Card.all.filter { !used.contains($0) }
    #expect(DeckLayout.deck(button: 0, seats: seats, burnsCards: true, holes: holes, board: board, rest: rest) != nil)
    // A hole card repeats a board card.
    holes[0] = [board[0], holes[0]![1]]
    #expect(DeckLayout.deck(button: 0, seats: seats, burnsCards: true, holes: holes, board: board, rest: rest) == nil)
    // A seat without two cards, and a rest with the wrong count.
    holes = self.holes(seats: [0], board: board)
    #expect(DeckLayout.deck(button: 0, seats: seats, burnsCards: true, holes: holes, board: board, rest: rest) == nil)
    let good = self.holes(seats: seats, board: board)
    #expect(
      DeckLayout.deck(
        button: 0, seats: seats, burnsCards: true, holes: good, board: board, rest: Array(rest.dropLast()))
        == nil)
  }

  @Test func holeOrderMatchesReducer() throws {
    #expect(DeckLayout.holeDealOrder(button: 2, seats: [0, 1, 2, 3, 4]) == [3, 4, 0, 1, 2])
    #expect(DeckLayout.holeDealOrder(button: 4, seats: [4, 2, 0]) == [0, 2, 4])
    // The first card dealt goes to the seat left of the button.
    let deck = Card.all
    let config = try TableConfig(seatCount: 4, smallBlind: 1, bigBlind: 2)
    let state = try HandReducer.start(
      config: config, button: 1, stacks: (0..<4).map { SeatStack(seat: $0, stack: 50) }, deck: deck
    ).state
    let order = DeckLayout.holeDealOrder(button: 1, seats: [0, 1, 2, 3])
    for (k, seat) in order.enumerated() {
      #expect(state.seat(seat)?.holeCards == [deck[k], deck[4 + k]])
    }
  }
}
