import Foundation

/// Hand-written allowed keys per file kind and nested type. Unknown keys are errors.
indirect enum KeySchema: Sendable {
  /// Not checked below this point (scalars, free-form dictionaries).
  case leaf
  case object([String: KeySchema])
  case array(KeySchema)
  /// An object whose allowed keys depend on the string stored under `tag`.
  case tagged(tag: String, variants: [String: [String: KeySchema]])

  static func object(_ keys: [String], _ nested: [String: KeySchema] = [:]) -> KeySchema {
    var all: [String: KeySchema] = [:]
    for key in keys { all[key] = .leaf }
    for (key, schema) in nested { all[key] = schema }
    return .object(all)
  }

  /// Unknown keys under `value`: (JSON path, message).
  func unknownKeys(in value: Any, path: String = "") -> [(path: String, message: String)] {
    switch self {
    case .leaf:
      return []
    case .array(let element):
      guard let items = value as? [Any] else { return [] }
      return items.enumerated().flatMap { element.unknownKeys(in: $0.element, path: "\(path)[\($0.offset)]") }
    case .object(let keys):
      guard let dictionary = value as? [String: Any] else { return [] }
      return check(dictionary, allowed: keys, path: path)
    case .tagged(let tag, let variants):
      guard let dictionary = value as? [String: Any] else { return [] }
      guard let name = dictionary[tag] as? String, let keys = variants[name] else {
        // An unknown tag is a decode error; check against the union so misspellings still show.
        var union: [String: KeySchema] = [tag: .leaf]
        for keys in variants.values { union.merge(keys) { first, _ in first } }
        return check(dictionary, allowed: union, path: path)
      }
      var allowed = keys
      allowed[tag] = .leaf
      return check(dictionary, allowed: allowed, path: path)
    }
  }

  private func check(
    _ dictionary: [String: Any], allowed: [String: KeySchema], path: String
  ) -> [(path: String, message: String)] {
    var found: [(path: String, message: String)] = []
    for key in dictionary.keys.sorted() {
      let childPath = path.isEmpty ? key : "\(path).\(key)"
      guard let child = allowed[key] else {
        var message = "unknown key '\(key)'"
        if let near = nearest(to: key, in: Array(allowed.keys)) { message += " (did you mean '\(near)'?)" }
        found.append((childPath, message))
        continue
      }
      found += child.unknownKeys(in: dictionary[key]!, path: childPath)
    }
    return found
  }

  private func nearest(to key: String, in candidates: [String]) -> String? {
    var best: (String, Int)?
    for candidate in candidates.sorted() {
      let distance = KeySchema.editDistance(key.lowercased(), candidate.lowercased())
      if distance <= 2, best == nil || distance < best!.1 { best = (candidate, distance) }
    }
    return best?.0
  }

  /// Levenshtein distance.
  static func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a)
    let b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var previous = Array(0...b.count)
    for i in 1...a.count {
      var current = [i] + Array(repeating: 0, count: b.count)
      for j in 1...b.count {
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
      }
      previous = current
    }
    return previous[b.count]
  }
}

/// The content file kinds.
enum ContentFileKind {
  case realm, skills, venue, lesson, spot, drill, boss, exam

  var schema: KeySchema {
    switch self {
    case .realm: KeySchema.realm
    case .skills: KeySchema.skills
    case .venue: KeySchema.venue
    case .lesson: KeySchema.lesson
    case .spot: KeySchema.spot
    case .drill: KeySchema.drill
    case .boss: KeySchema.boss
    case .exam: KeySchema.exam
    }
  }
}

extension KeySchema {
  static let realm = object(
    ["schemaVersion"],
    [
      "venues": .array(
        object(
          ["id", "name", "icon", "status", "teaches", "lockedText"], ["unlock": object(["afterVenue"])]))
    ])

  static let skills = object(
    ["schemaVersion"],
    [
      "axes": .array(object(["id", "name"])),
      "skills": .array(object(["id", "name", "axes", "baseDifficulty"])),
    ])

  static let venue = object(
    ["schemaVersion", "id", "name", "place", "chapter"],
    [
      "host": object(["name", "line", "artKey"]),
      "meters": .array(object(["id", "name", "skills"])),
      "nodes": .array(
        object(
          ["id", "kind", "title", "lesson", "drill", "boss"],
          [
            "table": object(["format", "opponents", "hands", "blinds", "stackBB", "coach"]),
            "unlock": object(["after"]),
          ])),
    ])

  private static let explainerRef = object(["explainer", "bind", "caption"])

  static let lesson = object(
    ["schemaVersion", "id", "title", "skills"],
    [
      "steps": .array(
        .tagged(
          tag: "kind",
          variants: [
            "hook": spotStepKeys, "puzzle": spotStepKeys,
            "explain": ["title": .leaf, "explainers": .array(explainerRef), "thinking": .leaf],
            "sandbox": [
              "title": .leaf, "controls": .leaf, "meters": .leaf, "explainer": .leaf, "challenge": .leaf,
            ],
            "apply": ["spot": .leaf, "count": .leaf, "freshSeeds": .leaf, "coach": .leaf],
          ])),
      "stars": object(
        ["hintCost"],
        [
          "three": object(["puzzleGood", "applyGood"]),
          "two": object(["puzzleGood", "applyGood"]),
        ]),
    ])

  private static let spotStepKeys: [String: KeySchema] = ["spot": .leaf, "coach": .leaf, "hint": .leaf]

  private static let handPredicate = object(
    ["madeHand", "bucket", "draws", "categories", "range", "pocketPair", "suited", "outs"])

  private static let villain = object(["character", "characters", "names", "position"], ["hand": handPredicate])

  private static let lineToken = object(["role", "act"])

  static let spot = object(
    [
      "schemaVersion", "id", "skill", "difficulty", "potBB", "prompt", "coach", "hint", "variation", "reveal",
    ],
    [
      "table": object(["players", "stacksBB", "blinds", "fillerNames"]),
      "hero": object(["position"], ["hand": handPredicate]),
      "villain": villain,
      "villains": .array(villain),
      "fixed": object(["hero", "villains", "board"]),
      "line": object(
        ["stopAt", "consistent"],
        [
          "preflop": .array(lineToken), "flop": .array(lineToken), "turn": .array(lineToken),
          "river": .array(lineToken), "random": object(["actions"]),
        ]),
      "board": object(["street", "require", "exclude", "highCard"]),
      "situation": object(["facingBet", "heroInPosition", "spr"]),
      "question": object(["type", "options", "tolerance", "pick"]),
      "evaluation": object(
        ["method", "ask", "vsRange", "target", "equitySamples"],
        ["buckets": .array(object(["id", "label", "range"]))]),
      "quality": object(["minGapBB", "answerBalance", "maxRetries"]),
      "explain": .array(explainerRef),
    ])

  static let drill = object(
    ["schemaVersion", "id", "title", "skills", "reps", "timerSeconds", "gym"],
    ["spots": .array(object(["template", "weight"]))])

  static let boss = object(
    [
      "schemaVersion", "id", "character", "title", "quote", "format", "hands", "blinds", "stackBB", "coach",
      "minDecisions", "minScore", "requirements", "exam",
    ],
    ["stars": object([], ["two": object(["score", "exam"]), "three": object(["score", "exam"])])])

  static let exam = object(
    ["schemaVersion", "id", "title", "count", "pass"], ["draw": .array(object(["template", "count"]))])
}
