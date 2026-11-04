import Testing

@testable import PokerCore

@Suite struct EventsFormatterTests {
  @Test func goldenScriptedHand() throws {
    var h = try HandScript.start(
      seatCount: 3, button: 0, stacks: [0: 1000, 1: 1000, 2: 1000],
      holes: [0: "AhAd", 1: "KsKd", 2: "7c2d"], board: "As5d9cJh3s")
    try h.act(.raise(to: 300), .call, .fold)
    try h.act(.check, .bet(to: 400), .call)
    try h.act(.check, .check)
    try h.act(.allIn, .call)
    let log = EventLog(handID: 7, steps: [HandStep(state: h.state, records: h.records)])
    let text = HandHistoryFormatter.format(log, viewer: .host, names: [0: "Ana", 1: "Bo", 2: "Cy"])
    #expect(
      text == """
        All-In Hand #7: Hold'em No Limit (50/100)
        Table 3-max. Ana is the button
        Ana (1000 in chips)
        Bo (1000 in chips)
        Cy (1000 in chips)
        Seed: none (scripted deck)
        Bo: posts small blind 50
        Cy: posts big blind 100
        *** HOLE CARDS ***
        Dealt to Bo [Ks Kd]
        Dealt to Cy [7c 2d]
        Dealt to Ana [Ah Ad]
        Ana: raises 200 to 300
        Bo: calls 250
        Cy: folds
        (burn before the flop: 2c)
        *** FLOP *** [As 5d 9c]
        Bo: checks
        Ana: bets 400
        Bo: calls 400
        (burn before the turn: 2h)
        *** TURN *** [As 5d 9c] [Jh]
        Bo: checks
        Ana: checks
        (burn before the river: 2s)
        *** RIVER *** [As 5d 9c Jh] [3s]
        Bo: bets 300 and is all-in
        Ana: calls 300 and is all-in
        *** SHOW DOWN ***
        Bo: shows [Ks Kd] (Pair of Kings)
        Ana: shows [Ah Ad] (Three of a kind, Aces)
        Ana collected 2100 from main pot
        *** SUMMARY ***
        Total pot 2100
        Board [As 5d 9c Jh 3s]
        Ana: showed [Ah Ad] with Three of a kind, Aces collected (2100) net +1100
        Bo: showed [Ks Kd] with Pair of Kings net -1000
        Cy: folded net -100
        """ + "\n")
  }

  @Test func spectatorHistoryHidesHoleCardsUntilShowdown() throws {
    let played = try EventsRandomHands.play(seed: 8)
    let text = HandHistoryFormatter.format(played.log, viewer: .spectator)
    #expect(!text.contains("Dealt to"))
    #expect(!text.contains("Seed"))
    #expect(!text.contains("burn"))
  }

  @Test func seatHistoryShowsOnlyOwnDeal() throws {
    let played = try EventsRandomHands.play(seed: 8)
    let text = HandHistoryFormatter.format(played.log, viewer: .seat(0))
    #expect(text.components(separatedBy: "Dealt to").count == 2)
    #expect(text.contains("Dealt to Seat 0"))
  }

  @Test func formatsEveryRandomHand() throws {
    for seed in UInt64(1)...100 {
      let played = try EventsRandomHands.play(seed: seed)
      let text = HandHistoryFormatter.format(played.log)
      #expect(text.contains("*** SUMMARY ***"))
    }
  }
}
