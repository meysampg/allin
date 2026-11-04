/// A seat's position relative to the button.
public enum TablePosition: String, Codable, Sendable, CaseIterable {
  case early, middle, cutoff, button, smallBlind, bigBlind

  /// Heads-up: the button (who posts the SB) is `.button`, the other seat `.bigBlind`.
  /// 3+ seats: BTN, SB, BB; then counting back from the button: CO, then the remaining non-blind
  /// seats, the later half (rounded down) `.middle`, the rest `.early`.
  public static func of(seat: Int, button: Int, seats: [Int]) -> TablePosition {
    let order = seats.sorted()
    guard let bi = order.firstIndex(of: button), let si = order.firstIndex(of: seat) else { return .early }
    let n = order.count
    if n == 2 { return seat == button ? .button : .bigBlind }
    // Distance clockwise from the button: 0 button, 1 SB, 2 BB, then the rest.
    let d = (si - bi + n) % n
    switch d {
    case 0: return .button
    case 1: return .smallBlind
    case 2: return .bigBlind
    default:
      // Counting back from the button: 1 = cutoff, 2 = next, ...
      let back = n - d
      if back == 1 { return .cutoff }
      let remaining = n - 4
      let middleCount = remaining / 2
      return back - 1 <= middleCount ? .middle : .early
    }
  }
}
