import Foundation

/// A playing card by raw value. ThemeKit does not import PokerCore; raw values match PokerCore.
public struct CardKey: Sendable, Hashable, Codable {
  /// 0 (two) ... 12 (ace).
  public let rank: UInt8
  /// 0 clubs, 1 diamonds, 2 hearts, 3 spades.
  public let suit: UInt8

  private static let rankSymbols = Array("23456789TJQKA")
  private static let suitSymbols = Array("cdhs")

  public init?(rank: UInt8, suit: UInt8) {
    guard rank < 13, suit < 4 else { return nil }
    self.rank = rank
    self.suit = suit
  }

  /// Parses "As", "Th", "2c".
  public init?(symbol: String) {
    let chars = Array(symbol)
    guard chars.count == 2,
      let r = CardKey.rankSymbols.firstIndex(of: chars[0]),
      let s = CardKey.suitSymbols.firstIndex(of: chars[1])
    else { return nil }
    self.init(rank: UInt8(r), suit: UInt8(s))
  }

  public var symbol: String {
    String([CardKey.rankSymbols[Int(rank)], CardKey.suitSymbols[Int(suit)]])
  }

  /// 52 cards, index order rank * 4 + suit.
  public static let all: [CardKey] = (0..<52).compactMap { CardKey(rank: UInt8($0 / 4), suit: UInt8($0 % 4)) }
}
