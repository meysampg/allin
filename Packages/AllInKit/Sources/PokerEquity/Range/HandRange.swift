import PokerCore

/// A weighted set of the 1326 starting combos. Each weight is in 0...1 (the share of the combo kept).
public struct HandRange: Sendable, Hashable {
  public static let empty = HandRange()
  public static let full = HandRange(weights: [Float](repeating: 1, count: 1326))

  /// Count 1326, each in 0...1, indexed by `Combo.index`.
  public internal(set) var weights: [Float]

  public init() { weights = [Float](repeating: 0, count: 1326) }

  /// Precondition: `weights.count == 1326`. Values are clamped to 0...1.
  public init(weights: [Float]) {
    precondition(weights.count == 1326, "A range needs 1326 weights")
    self.weights = weights.map { HandRange.clamp($0) }
  }

  public init(combo: Combo) {
    self.init()
    weights[combo.index] = 1
  }

  public init(classWeights: [HandClass: Float]) {
    self.init()
    for (c, w) in classWeights { setClass(c, w) }
  }

  /// A range from a 13x13 grid of class weights (see ``grid``).
  public init(grid: [[Float]]) {
    precondition(grid.count == 13 && grid.allSatisfy { $0.count == 13 }, "Grid must be 13x13")
    self.init()
    for c in HandClass.all { setClass(c, grid[c.gridRow][c.gridColumn]) }
  }

  static func clamp(_ w: Float) -> Float { min(max(w, 0), 1) }

  mutating func setClass(_ c: HandClass, _ w: Float) {
    let v = HandRange.clamp(w)
    for combo in c.combos { weights[combo.index] = v }
  }

  public subscript(combo: Combo) -> Float {
    get { weights[combo.index] }
    set { weights[combo.index] = HandRange.clamp(newValue) }
  }

  /// Mean weight over the class's combos.
  public func weight(of handClass: HandClass) -> Float {
    let combos = handClass.combos
    var sum: Float = 0
    for c in combos { sum += weights[c.index] }
    return sum / Float(combos.count)
  }

  /// 13x13 class weights; row/column 0 is the Ace, suited above the diagonal, offsuit below.
  public var grid: [[Float]] {
    var g = [[Float]](repeating: [Float](repeating: 0, count: 13), count: 13)
    for c in HandClass.all { g[c.gridRow][c.gridColumn] = weight(of: c) }
    return g
  }

  /// Sum of weights, in combo units.
  public var totalWeight: Double { weights.reduce(0.0) { $0 + Double($1) } }

  public var nonZeroCombos: [Combo] { Combo.all.filter { weights[$0.index] > 0 } }

  /// The range without combos that use a dead card.
  public func removing(_ dead: CardSet) -> HandRange {
    guard !dead.isEmpty else { return self }
    var r = self
    for combo in Combo.all where !combo.mask.isDisjoint(with: dead) { r.weights[combo.index] = 0 }
    return r
  }

  public func scaled(by f: Float) -> HandRange {
    HandRange(weights: weights.map { $0 * f })
  }

  public func multiplied(by other: HandRange) -> HandRange {
    var r = self
    for i in 0..<1326 { r.weights[i] = HandRange.clamp(weights[i] * other.weights[i]) }
    return r
  }

  /// `(1 - t) * self + t * other`, after scaling both to the same total weight (the total of `self`, or of
  /// `other` when `self` is empty). The result is clamped to 0...1.
  public func blended(with other: HandRange, t: Double) -> HandRange {
    let tt = min(max(t, 0), 1)
    let a = totalWeight
    let b = other.totalWeight
    let target = a > 0 ? a : b
    guard target > 0 else { return .empty }
    let fa = a > 0 ? target / a : 0
    let fb = b > 0 ? target / b : 0
    var r = HandRange()
    for i in 0..<1326 {
      let v = (1 - tt) * Double(weights[i]) * fa + tt * Double(other.weights[i]) * fb
      r.weights[i] = HandRange.clamp(Float(v))
    }
    return r
  }

  /// The strongest `fraction` of all combos by `ordering`; the boundary class gets a fractional weight.
  public static func top(_ fraction: Double, ordering: PreflopOrdering = .standard) -> HandRange {
    var r = HandRange()
    let budget = min(max(fraction, 0), 1) * 1326
    var used = 0.0
    for c in ordering.classes {
      let n = Double(c.comboCount)
      if used + n <= budget + 1e-9 {
        r.setClass(c, 1)
        used += n
      } else {
        let remaining = budget - used
        if remaining > 1e-9 { r.setClass(c, Float(remaining / n)) }
        break
      }
    }
    return r
  }

  /// Combos whose ordering percentile is in `[from, to)`; boundary classes get fractional weight.
  public static func band(from: Double, to: Double, ordering: PreflopOrdering = .standard) -> HandRange {
    let outer = top(to, ordering: ordering)
    let inner = top(from, ordering: ordering)
    var r = HandRange()
    for i in 0..<1326 { r.weights[i] = max(0, outer.weights[i] - inner.weights[i]) }
    return r
  }
}
