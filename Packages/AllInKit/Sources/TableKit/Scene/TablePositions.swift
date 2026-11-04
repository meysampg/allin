import Foundation

/// Position names for the seats dealt into a hand.
public enum TablePositions {
  /// Names for `count` players listed clockwise from the button: BTN, SB, BB, then early to late.
  public static func names(count: Int) -> [String] {
    switch count {
    case ..<2: return ["BTN"]
    case 2: return ["BTN", "BB"]
    default:
      let middle: [String]
      switch count - 3 {
      case 0: middle = []
      case 1: middle = ["CO"]
      case 2: middle = ["UTG", "CO"]
      case 3: middle = ["UTG", "HJ", "CO"]
      case 4: middle = ["UTG", "LJ", "HJ", "CO"]
      case 5: middle = ["UTG", "UTG+1", "LJ", "HJ", "CO"]
      default: middle = ["UTG", "UTG+1", "UTG+2", "LJ", "HJ", "CO"]
      }
      return ["BTN", "SB", "BB"] + middle
    }
  }

  /// Seat index to position name. `seats` are the dealt seat indices in any order; the button must be one of them.
  public static func assign(button: Int, seats: [Int]) -> [Int: String] {
    let sorted = seats.sorted()
    guard let start = sorted.firstIndex(of: button) else { return [:] }
    let names = names(count: sorted.count)
    var result: [Int: String] = [:]
    for offset in 0..<sorted.count {
      result[sorted[(start + offset) % sorted.count]] = names[offset]
    }
    return result
  }
}
