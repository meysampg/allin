/// Validation failures for ``TableConfig``.
public enum TableConfigError: Error, Sendable, Equatable {
  case seatCountOutOfRange(Int)
  case nonPositiveChipUnit(Int)
  case nonPositiveSmallBlind(Int)
  case bigBlindBelowSmallBlind(small: Int, big: Int)
  case negativeAnte(Int)
  case notMultipleOfChipUnit(name: String, value: Int, chipUnit: Int)
}

/// Who pays the ante.
public enum AnteKind: String, Codable, Sendable, Hashable {
  /// Every player posts `ante` chips.
  case perPlayer
  /// Only the big blind posts `ante` chips (tournament "BB ante"), on behalf of the table.
  case bigBlind
}

/// Static rules of a table: seat count, blinds, antes and the smallest chip. All amounts are integer chips.
public struct TableConfig: Codable, Sendable, Hashable {
  public let seatCount: Int
  public let smallBlind: Int
  public let bigBlind: Int
  /// Ante amount (0 means no ante). See ``anteKind`` for who pays it.
  public let ante: Int
  public let anteKind: AnteKind
  /// Smallest denomination. Blinds, ante and every non-all-in bet or raise are multiples of it.
  public let chipUnit: Int

  public init(
    seatCount: Int, smallBlind: Int, bigBlind: Int, ante: Int = 0, anteKind: AnteKind = .perPlayer,
    chipUnit: Int = 1
  ) throws {
    guard (2...9).contains(seatCount) else { throw TableConfigError.seatCountOutOfRange(seatCount) }
    guard chipUnit > 0 else { throw TableConfigError.nonPositiveChipUnit(chipUnit) }
    guard smallBlind > 0 else { throw TableConfigError.nonPositiveSmallBlind(smallBlind) }
    guard bigBlind >= smallBlind else {
      throw TableConfigError.bigBlindBelowSmallBlind(small: smallBlind, big: bigBlind)
    }
    guard ante >= 0 else { throw TableConfigError.negativeAnte(ante) }
    for (name, value) in [("smallBlind", smallBlind), ("bigBlind", bigBlind), ("ante", ante)]
    where value % chipUnit != 0 {
      throw TableConfigError.notMultipleOfChipUnit(name: name, value: value, chipUnit: chipUnit)
    }
    self.seatCount = seatCount
    self.smallBlind = smallBlind
    self.bigBlind = bigBlind
    self.ante = ante
    self.anteKind = anteKind
    self.chipUnit = chipUnit
  }
}
