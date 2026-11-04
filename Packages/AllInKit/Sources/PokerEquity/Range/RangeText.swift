import PokerCore

/// Errors from parsing range text.
public enum RangeParseError: Error, Sendable, Equatable {
  case invalidToken(String)
  case invalidWeight(String)
  case invalidSpan(String)
}

/// A parsed "AKs" / "QQ" / "T9" fragment. `suited` is nil when the suffix is missing.
struct HandPart {
  let high: Rank
  let low: Rank
  let suited: Bool?

  static func parse(_ text: String, token: String) throws -> HandPart {
    let chars = Array(text)
    guard chars.count == 2 || chars.count == 3, let a = Rank(symbol: chars[0]), let b = Rank(symbol: chars[1])
    else { throw RangeParseError.invalidToken(token) }
    var suited: Bool?
    if chars.count == 3 {
      switch chars[2] {
      case "s", "S": suited = true
      case "o", "O": suited = false
      default: throw RangeParseError.invalidToken(token)
      }
    }
    if a == b && suited != nil { throw RangeParseError.invalidToken(token) }
    return HandPart(high: max(a, b), low: min(a, b), suited: suited)
  }
}

extension HandRange {
  /// Parses "22+, A2s+, KTo+, 76s:0.5, AhKh, 77-99, A5s-A2s, KQ". Commas and/or whitespace separate tokens;
  /// later tokens overwrite earlier ones. `KQ` means both KQs and KQo.
  public init(parsing text: String) throws {
    self.init()
    let tokens = text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    for token in tokens { try apply(token: token) }
  }

  private mutating func apply(token: String) throws {
    var body = token
    var weight: Float = 1
    if let colon = token.firstIndex(of: ":") {
      body = String(token[..<colon])
      let wText = String(token[token.index(after: colon)...])
      guard let w = Float(wText), w.isFinite, (0...1).contains(w) else {
        throw RangeParseError.invalidWeight(token)
      }
      weight = w
    }
    guard !body.isEmpty else { throw RangeParseError.invalidToken(token) }
    for c in try HandRange.classes(of: body, token: token) { setClass(c, weight) }
    if let combo = try HandRange.specificCombo(body) {
      weights[combo.index] = weight
    }
  }

  /// A specific combo such as "AhKh", or nil when `body` is not in that form.
  private static func specificCombo(_ body: String) throws -> Combo? {
    let chars = Array(body)
    guard chars.count == 4, Suit(symbol: chars[1]) != nil, Suit(symbol: chars[3]) != nil else { return nil }
    do { return try Combo(body) } catch { throw RangeParseError.invalidToken(body) }
  }

  private static func classes(of body: String, token: String) throws -> [HandClass] {
    let chars = Array(body)
    if chars.count == 4, Suit(symbol: chars[1]) != nil, Suit(symbol: chars[3]) != nil { return [] }
    if let dash = body.firstIndex(of: "-") {
      let a = try HandPart.parse(String(body[..<dash]), token: token)
      let b = try HandPart.parse(String(body[body.index(after: dash)...]), token: token)
      return try span(a, b, token: token)
    }
    if body.hasSuffix("+") {
      let p = try HandPart.parse(String(body.dropLast()), token: token)
      if p.high == p.low { return pairs(from: p.high, to: .ace) }
      return kickers(high: p.high, from: p.low, to: Rank(rawValue: p.high.rawValue - 1)!, suited: p.suited)
    }
    let p = try HandPart.parse(body, token: token)
    if p.high == p.low { return pairs(from: p.high, to: p.high) }
    return kickers(high: p.high, from: p.low, to: p.low, suited: p.suited)
  }

  private static func span(_ a: HandPart, _ b: HandPart, token: String) throws -> [HandClass] {
    if a.high == a.low || b.high == b.low {
      guard a.high == a.low, b.high == b.low else { throw RangeParseError.invalidSpan(token) }
      return pairs(from: min(a.high, b.high), to: max(a.high, b.high))
    }
    guard a.high == b.high, a.suited == b.suited else { throw RangeParseError.invalidSpan(token) }
    return kickers(high: a.high, from: min(a.low, b.low), to: max(a.low, b.low), suited: a.suited)
  }

  private static func pairs(from lo: Rank, to hi: Rank) -> [HandClass] {
    (lo.rawValue...hi.rawValue).map { HandClass(high: Rank(rawValue: $0)!, low: Rank(rawValue: $0)!, suited: false)! }
  }

  private static func kickers(high: Rank, from lo: Rank, to hi: Rank, suited: Bool?) -> [HandClass] {
    var result: [HandClass] = []
    guard lo <= hi else { return [] }
    for raw in lo.rawValue...hi.rawValue {
      let low = Rank(rawValue: raw)!
      if suited != false, let c = HandClass(high: high, low: low, suited: true) { result.append(c) }
      if suited != true, let c = HandClass(high: high, low: low, suited: false) { result.append(c) }
    }
    return result
  }

  // MARK: Formatter

  /// Canonical text; `HandRange(parsing: r.text) == r` for class-uniform ranges with weights k/1000.
  public var text: String {
    var classK = [Int](repeating: 0, count: 169)
    var explicit: [String] = []
    for c in HandClass.all {
      let combos = c.combos
      let first = weights[combos[0].index]
      if combos.allSatisfy({ weights[$0.index] == first }) {
        classK[c.gridIndex] = HandRange.thousandths(first)
      } else {
        for combo in combos where HandRange.thousandths(weights[combo.index]) > 0 {
          explicit.append(combo.description + HandRange.suffix(HandRange.thousandths(weights[combo.index])))
        }
      }
    }
    func k(_ high: Int, _ low: Int, suited: Bool) -> Int {
      let c = HandClass(high: Rank(rawValue: UInt8(high))!, low: Rank(rawValue: UInt8(low))!, suited: suited)!
      return classK[c.gridIndex]
    }
    var tokens: [String] = []
    // Pairs.
    for run in HandRange.runs(of: (0..<13).reversed().map { k($0, $0, suited: false) }) {
      let hi = 12 - run.start
      let lo = 12 - run.end
      let sfx = HandRange.suffix(run.k)
      let l = Rank(rawValue: UInt8(lo))!.symbol
      let h = Rank(rawValue: UInt8(hi))!.symbol
      if hi == 12 {
        tokens.append(lo == 12 ? "AA\(sfx)" : "\(l)\(l)+\(sfx)")
      } else if lo == hi {
        tokens.append("\(l)\(l)\(sfx)")
      } else {
        tokens.append("\(l)\(l)-\(h)\(h)\(sfx)")
      }
    }
    // Non-pairs, per high card.
    for high in (1..<13).reversed() {
      let top = Rank(rawValue: UInt8(high))!.symbol
      let kickers = (0..<high).reversed().map { $0 }
      let ks = kickers.map { k(high, $0, suited: true) }
      let ko = kickers.map { k(high, $0, suited: false) }
      let both = zip(ks, ko).map { $0 == $1 ? $0 : 0 }
      let onlyS = zip(ks, both).map { $1 == 0 ? $0 : 0 }
      let onlyO = zip(ko, both).map { $1 == 0 ? $0 : 0 }
      for (values, kind) in [(both, ""), (onlyS, "s"), (onlyO, "o")] {
        for run in HandRange.runs(of: values) {
          let hiKicker = high - 1 - run.start
          let loKicker = high - 1 - run.end
          let sfx = HandRange.suffix(run.k)
          let hs = Rank(rawValue: UInt8(hiKicker))!.symbol
          let ls = Rank(rawValue: UInt8(loKicker))!.symbol
          if run.start == run.end {
            tokens.append("\(top)\(hs)\(kind)\(sfx)")
          } else if run.start == 0 {
            tokens.append("\(top)\(ls)\(kind)+\(sfx)")
          } else {
            tokens.append("\(top)\(hs)\(kind)-\(top)\(ls)\(kind)\(sfx)")
          }
        }
      }
    }
    return (tokens + explicit).joined(separator: ", ")
  }

  private static func thousandths(_ w: Float) -> Int { Int((Double(w) * 1000).rounded()) }

  /// "" for weight 1, otherwise ":0.5", ":0.125".
  private static func suffix(_ k: Int) -> String {
    guard k < 1000 else { return "" }
    var digits = String(k)
    while digits.count < 3 { digits = "0" + digits }
    while digits.hasSuffix("0") { digits.removeLast() }
    return ":0." + digits
  }

  /// Maximal runs of consecutive equal non-zero values: (first index, last index, value).
  private static func runs(of values: [Int]) -> [(start: Int, end: Int, k: Int)] {
    var result: [(start: Int, end: Int, k: Int)] = []
    var i = 0
    while i < values.count {
      guard values[i] > 0 else {
        i += 1
        continue
      }
      var j = i
      while j + 1 < values.count, values[j + 1] == values[i] { j += 1 }
      result.append((i, j, values[i]))
      i = j + 1
    }
    return result
  }
}
