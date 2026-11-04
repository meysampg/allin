/// Plain-text hand history in the style of common online sites, built from a log as one viewer sees it.
///
/// Hole cards appear only when the viewer may see them (a seat sees its own; the host sees all; a spectator sees
/// those shown at showdown). Hands that mucked appear as "mucks" with cards for the host only.
public enum HandHistoryFormatter {
  /// Formats the log. `names` maps seats to display names; others read "Seat N".
  public static func format(_ log: EventLog, viewer: Viewer = .host, names: [Int: String] = [:]) -> String {
    var lines: [String] = []
    func name(_ seat: Int) -> String { names[seat] ?? "Seat \(seat)" }
    func cards(_ list: [Card]) -> String { "[" + list.map(\.description).joined(separator: " ") + "]" }

    var board: [Card] = []
    var streetBet = 0
    var totalPot = 0
    var shown: [Int: Reveal] = [:]
    var collected: [Int: Int] = [:]
    var folded: Set<Int> = []
    var summaryHeaderDone = false
    var holeHeader = false
    var potTotals = 0

    for logged in log.filtered(for: viewer) {
      switch logged.event {
      case .handStarted(let s):
        let c = s.config
        var stakes = "\(c.smallBlind)/\(c.bigBlind)"
        if c.ante > 0 { stakes += c.anteKind == .bigBlind ? ", big blind ante \(c.ante)" : ", ante \(c.ante)" }
        lines.append("All-In Hand #\(log.handID): Hold'em No Limit (\(stakes))")
        lines.append("Table \(c.seatCount)-max. \(name(s.button)) is the button")
        for seat in s.seats { lines.append("\(name(seat.seat)) (\(seat.stack) in chips)") }
      case .deckSetup(let seed, _):
        lines.append("Seed: \(seed.map(String.init) ?? "none (scripted deck)")")
      case .blindPosted(let p):
        switch p.kind {
        case .ante: lines.append("\(name(p.seat)): posts the ante \(p.amount)")
        case .smallBlind: lines.append("\(name(p.seat)): posts small blind \(p.amount)")
        case .bigBlind: lines.append("\(name(p.seat)): posts big blind \(p.amount)")
        }
        if p.kind == .bigBlind { streetBet = max(streetBet, p.amount) }
        if p.kind == .smallBlind { streetBet = max(streetBet, p.amount) }
        totalPot += p.amount
      case .holeCardsDealt(let seat, let hole):
        if !holeHeader {
          holeHeader = true
          lines.append("*** HOLE CARDS ***")
        }
        lines.append("Dealt to \(name(seat)) \(cards(hole))")
      case .actionRequested:
        break
      case .actionTaken(let t):
        lines.append("\(name(t.seat)): " + describe(t, streetBet: streetBet) + (t.isAllIn ? " and is all-in" : ""))
        if t.action == .fold { folded.insert(t.seat) }
        streetBet = max(streetBet, t.committedAfter)
        totalPot = t.potAfter
      case .uncalledBetReturned(let seat, let amount):
        lines.append("Uncalled bet (\(amount)) returned to \(name(seat))")
        totalPot -= amount
      case .burned(let street, let card):
        lines.append("(burn before the \(street.rawValue): \(card))")
      case .streetDealt(let street, let dealt):
        let old = board
        board += dealt
        streetBet = 0
        switch street {
        case .preflop: break
        case .flop: lines.append("*** FLOP *** \(cards(board))")
        case .turn, .river: lines.append("*** \(street.rawValue.uppercased()) *** \(cards(old)) \(cards(dealt))")
        }
      case .potsUpdated(let pots):
        potTotals = pots.reduce(0) { $0 + $1.amount }
      case .showdown(let reveals):
        lines.append("*** SHOW DOWN ***")
        for r in reveals {
          shown[r.seat] = r
          lines.append("\(name(r.seat)): shows \(cards(r.holeCards)) (\(r.value))")
        }
      case .mucked(let reveals):
        for r in reveals {
          lines.append("\(name(r.seat)): mucks hand \(cards(r.holeCards)) (\(r.value))")
        }
      case .potAwarded(let a):
        let label = a.potIndex == 0 ? "main pot" : "side pot-\(a.potIndex)"
        for share in a.shares {
          collected[share.seat, default: 0] += share.amount
          lines.append("\(name(share.seat)) collected \(share.amount) from \(label)")
        }
      case .handEnded(let r):
        if !summaryHeaderDone {
          summaryHeaderDone = true
          lines.append("*** SUMMARY ***")
          lines.append("Total pot \(potTotals > 0 ? potTotals : max(totalPot, 0))")
          lines.append("Board \(cards(r.board))")
          for seat in r.finalStacks.map(\.seat) {
            var text = "\(name(seat)):"
            if folded.contains(seat) { text += " folded" }
            if let reveal = shown[seat] { text += " showed \(cards(reveal.holeCards)) with \(reveal.value)" }
            if let won = collected[seat] { text += " collected (\(won))" }
            let net = r.netChips(of: seat) ?? 0
            text += " net \(net >= 0 ? "+" : "")\(net)"
            lines.append(text)
          }
        }
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func describe(_ t: ActionTaken, streetBet: Int) -> String {
    switch t.action {
    case .fold: return "folds"
    case .check: return "checks"
    case .call: return "calls \(t.chipsAdded)"
    case .bet: return "bets \(t.committedAfter)"
    case .raise: return "raises \(t.committedAfter - streetBet) to \(t.committedAfter)"
    case .allIn:
      if t.committedAfter > streetBet {
        return streetBet == 0
          ? "bets \(t.committedAfter)" : "raises \(t.committedAfter - streetBet) to \(t.committedAfter)"
      }
      return t.chipsAdded == 0 ? "checks" : "calls \(t.chipsAdded)"
    }
  }
}
