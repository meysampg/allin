import PokerCore

/// Card masks of the 1326 combos, indexed by `Combo.index` (no allocation per lookup).
enum ComboMasks {
  static let table: [UInt64] = (0..<1326).map { Combo(index: $0).mask.bits }
}

/// Weighted combo sampler: cumulative weights plus binary search.
public struct RangeSampler: Sendable {
  private let ids: [UInt16]
  private let masks: [UInt64]
  private let cumulative: [Double]

  public init(_ range: HandRange, excluding dead: CardSet) {
    let table = ComboMasks.table
    var ids: [UInt16] = []
    var masks: [UInt64] = []
    var cumulative: [Double] = []
    var sum = 0.0
    let deadBits = dead.bits
    range.weights.withUnsafeBufferPointer { w in
      for i in 0..<1326 where w[i] > 0 && table[i] & deadBits == 0 {
        sum += Double(w[i])
        ids.append(UInt16(i))
        masks.append(table[i])
        cumulative.append(sum)
      }
    }
    self.ids = ids
    self.masks = masks
    self.cumulative = cumulative
  }

  /// True when no combo can be drawn.
  public var isEmpty: Bool { ids.isEmpty }

  /// Draws a combo with probability proportional to its weight; nil when empty.
  public func sample(using rng: inout some RandomNumberGenerator) -> Combo? {
    guard !ids.isEmpty else { return nil }
    return Combo(index: Int(ids[position(&rng)]))
  }

  /// Draws a combo's card mask. Precondition: not empty.
  @inline(__always)
  func drawMask<R: RandomNumberGenerator>(_ rng: inout R) -> UInt64 { masks[position(&rng)] }

  @inline(__always)
  private func position<R: RandomNumberGenerator>(_ rng: inout R) -> Int {
    let total = cumulative[cumulative.count - 1]
    let u = Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0) * total
    var lo = 0
    var hi = cumulative.count - 1
    while lo < hi {
      let mid = (lo + hi) >> 1
      if cumulative[mid] > u { hi = mid } else { lo = mid + 1 }
    }
    return lo
  }
}
