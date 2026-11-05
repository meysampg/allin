import Foundation
import PokerCore

/// Structural checks of a loaded library: ids, references, graphs and the method/question rules of §1.2.
/// Fast: no spot generation.
public enum ContentValidator {
  public static func structural(_ library: ContentLibrary) -> [ContentIssue] {
    var checker = Checker(library: library)
    checker.run()
    return checker.issues
  }

  /// Ids are lowercase words joined by '-', grouped by '.'.
  public static func isValidID(_ id: String) -> Bool {
    guard !id.isEmpty else { return false }
    for group in id.split(separator: ".", omittingEmptySubsequences: false) {
      guard !group.isEmpty else { return false }
      for word in group.split(separator: "-", omittingEmptySubsequences: false) {
        guard !word.isEmpty, word.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) else { return false }
      }
    }
    return true
  }

  /// An action option of an EV question: fold, check, call, allin, bet:F (0 < F <= 3), raise:X (X >= 2).
  static func isValidActionOption(_ text: String) -> Bool {
    switch text {
    case "fold", "check", "call", "allin": return true
    default:
      let parts = text.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, let value = Double(parts[1]) else { return false }
      if parts[0] == "bet" { return value > 0 && value <= 3 }
      if parts[0] == "raise" { return value >= 2 }
      return false
    }
  }

  fileprivate static let defaultBucketIDs: [String] = ["none", "few", "many"]

  fileprivate struct MethodRule {
    let questions: [QuestionType]
    let streets: [Street]?
  }

  fileprivate static func rule(for method: EvaluationMethod) -> MethodRule {
    switch method {
    case .showdownWinner: MethodRule(questions: [.pickWinner], streets: [.river])
    case .bestFive: MethodRule(questions: [.pickCards], streets: [.turn, .river])
    case .nuts: MethodRule(questions: [.pickCards, .pickHandClass], streets: [.flop, .turn, .river])
    case .outs: MethodRule(questions: [.pickCards, .number], streets: [.flop, .turn])
    case .beatsMeCount: MethodRule(questions: [.choice, .number], streets: [.flop, .turn, .river])
    case .potCount: MethodRule(questions: [.number], streets: nil)
    case .legalSizes: MethodRule(questions: [.number, .sizeChoice, .choice], streets: nil)
    case .nextToAct: MethodRule(questions: [.choice], streets: nil)
    case .closedFormEV, .policyEV, .pushFold: MethodRule(questions: [.action], streets: nil)
    case .rangeMatch: MethodRule(questions: [.rangePaint], streets: [.preflop])
    }
  }

  private struct Checker {
    let library: ContentLibrary
    var issues: [ContentIssue] = []

    init(library: ContentLibrary) { self.library = library }

    mutating func add(
      _ code: String, id: String? = nil, file: String? = nil, _ path: String = "", _ message: String,
      severity: IssueSeverity = .error
    ) {
      let location = file ?? id.flatMap { library.fileOf[$0] } ?? ""
      issues.append(ContentIssue(severity, code: code, file: location, path: path, message: message))
    }

    mutating func unknown(_ kind: String, _ value: String, id: String? = nil, file: String? = nil, path: String) {
      add("ref.unknown", id: id, file: file, path, "unknown \(kind) '\(value)'")
    }

    mutating func run() {
      checkIDs()
      checkRealm()
      checkSkills()
      for venue in library.venues { checkVenue(venue) }
      for id in library.lessons.keys.sorted() { checkLesson(library.lessons[id]!) }
      for id in library.drills.keys.sorted() { checkDrill(library.drills[id]!) }
      for id in library.bosses.keys.sorted() { checkBoss(library.bosses[id]!) }
      for id in library.exams.keys.sorted() { checkExam(library.exams[id]!) }
      for id in library.templates.keys.sorted() { checkTemplate(library.templates[id]!) }
      checkUnusedSkills()
    }

    // MARK: Ids

    mutating func checkIDs() {
      func check(_ kind: String, _ id: String, file: String, path: String, into checker: inout Checker) {
        if !ContentValidator.isValidID(id) {
          checker.add("id.format", file: file, path, "\(kind) id '\(id)' must be lowercase words joined by '-' and '.'")
        }
      }
      for (index, venue) in library.realm.venues.enumerated() {
        check("venue", venue.id, file: "realm.json", path: "venues[\(index)].id", into: &self)
      }
      for (index, axis) in library.skills.axes.enumerated() {
        check("axis", axis.id, file: "skills.json", path: "axes[\(index)].id", into: &self)
      }
      for (index, skill) in library.skills.skills.enumerated() {
        check("skill", skill.id, file: "skills.json", path: "skills[\(index)].id", into: &self)
      }
      for venue in library.venues {
        let file = library.fileOf[venue.id] ?? ""
        check("venue", venue.id, file: file, path: "id", into: &self)
        for (index, meter) in venue.meters.enumerated() {
          check("meter", meter.id, file: file, path: "meters[\(index)].id", into: &self)
        }
        for (index, node) in venue.nodes.enumerated() {
          check("node", node.id, file: file, path: "nodes[\(index)].id", into: &self)
        }
      }
      for id in library.lessons.keys.sorted() {
        check("lesson", id, file: library.fileOf[id] ?? "", path: "id", into: &self)
      }
      for id in library.templates.keys.sorted() {
        check("template", id, file: library.fileOf[id] ?? "", path: "id", into: &self)
      }
      for id in library.drills.keys.sorted() {
        check("drill", id, file: library.fileOf[id] ?? "", path: "id", into: &self)
      }
      for id in library.bosses.keys.sorted() {
        check("boss", id, file: library.fileOf[id] ?? "", path: "id", into: &self)
      }
      for id in library.exams.keys.sorted() {
        check("exam", id, file: library.fileOf[id] ?? "", path: "id", into: &self)
      }
    }

    // MARK: Graphs

    /// Reports cycles (`graph.cycle`) and nodes that can never unlock (`graph.unreachable`).
    mutating func checkGraph(
      kind: String, ids: [String], dependencies: [String: [String]], file: String
    ) {
      var reachable = Set<String>()
      var changed = true
      while changed {
        changed = false
        for id in ids where !reachable.contains(id) {
          if (dependencies[id] ?? []).allSatisfy({ reachable.contains($0) }) {
            reachable.insert(id)
            changed = true
          }
        }
      }
      let blocked = ids.filter { !reachable.contains($0) }
      guard !blocked.isEmpty else { return }
      let blockedSet = Set(blocked)
      var cyclic = Set<String>()
      var finished = Set<String>()
      func visit(_ id: String, _ stack: inout [String], _ found: inout [[String]]) {
        if let at = stack.firstIndex(of: id) {
          found.append(Array(stack[at...]) + [id])
          return
        }
        guard !finished.contains(id) else { return }
        stack.append(id)
        for next in dependencies[id] ?? [] where blockedSet.contains(next) { visit(next, &stack, &found) }
        stack.removeLast()
        finished.insert(id)
      }
      var cycles: [[String]] = []
      for id in blocked {
        var stack: [String] = []
        visit(id, &stack, &cycles)
      }
      for cycle in cycles {
        cyclic.formUnion(cycle)
        add("graph.cycle", file: file, "", "\(kind)s form a cycle: \(cycle.joined(separator: " -> "))")
      }
      for id in blocked where !cyclic.contains(id) {
        add("graph.unreachable", file: file, "", "\(kind) '\(id)' can never unlock")
      }
    }

    mutating func checkRealm() {
      let ids = library.realm.venues.map(\.id)
      var dependencies: [String: [String]] = [:]
      for (index, venue) in library.realm.venues.enumerated() {
        guard let after = venue.unlock?.afterVenue else { continue }
        if ids.contains(after) {
          dependencies[venue.id] = [after]
        } else {
          unknown("venue", after, file: "realm.json", path: "venues[\(index)].unlock.afterVenue")
        }
        if venue.status == .open, library.venue(venue.id) == nil {
          add("realm.missingVenue", file: "realm.json", "venues[\(index)]", "open venue '\(venue.id)' is not loaded")
        }
      }
      for (index, venue) in library.realm.venues.enumerated()
      where venue.unlock == nil && venue.status == .open && library.venue(venue.id) == nil {
        add("realm.missingVenue", file: "realm.json", "venues[\(index)]", "open venue '\(venue.id)' is not loaded")
      }
      checkGraph(kind: "venue", ids: ids, dependencies: dependencies, file: "realm.json")
    }

    mutating func checkSkills() {
      let axisIDs = Set(library.skills.axes.map(\.id))
      for (index, skill) in library.skills.skills.enumerated() {
        for axis in skill.axes.keys.sorted() where !axisIDs.contains(axis) {
          unknown("axis", axis, file: "skills.json", path: "skills[\(index)].axes")
        }
      }
    }

    // MARK: Venues

    mutating func checkVenue(_ venue: Venue) {
      let file = library.fileOf[venue.id] ?? ""
      for (m, meter) in venue.meters.enumerated() {
        for (s, skill) in meter.skills.enumerated() where library.skills.skill(skill) == nil {
          unknown("skill", skill, file: file, path: "meters[\(m)].skills[\(s)]")
        }
      }
      let nodeIDs = venue.nodes.map(\.id)
      var dependencies: [String: [String]] = [:]
      for (index, node) in venue.nodes.enumerated() {
        let path = "nodes[\(index)]"
        if let id = node.lesson, library.lesson(id) == nil { unknown("lesson", id, file: file, path: "\(path).lesson") }
        if let id = node.drill, library.drill(id) == nil { unknown("drill", id, file: file, path: "\(path).drill") }
        if let id = node.boss, library.boss(id) == nil { unknown("boss", id, file: file, path: "\(path).boss") }
        if let table = node.table {
          if table.opponents.count != table.format.opponentCount {
            add(
              "table.opponents", file: file, "\(path).table.opponents",
              "\(table.format.rawValue) needs \(table.format.opponentCount) opponents, got \(table.opponents.count)")
          }
          for (o, opponent) in table.opponents.enumerated() where !library.characters.contains(opponent) {
            unknown("character", opponent, file: file, path: "\(path).table.opponents[\(o)]")
          }
        }
        var after: [String] = []
        for (a, id) in venue.prerequisites(of: node).enumerated() {
          if nodeIDs.contains(id) {
            after.append(id)
          } else {
            unknown("node", id, file: file, path: "\(path).unlock.after[\(a)]")
          }
        }
        dependencies[node.id] = after
      }
      checkGraph(kind: "node", ids: nodeIDs, dependencies: dependencies, file: file)
    }

    // MARK: Lessons, drills, bosses, exams

    mutating func checkExplainer(_ ref: ExplainerRef, id: String, path: String) {
      for key in ref.bind.keys.sorted() where !ref.explainer.bindKeys.contains(key) {
        add("lesson.explainer", id: id, "\(path).bind", "unknown bind key '\(key)' for \(ref.explainer.rawValue)")
      }
    }

    mutating func checkLesson(_ lesson: Lesson) {
      for (index, skill) in lesson.skills.enumerated() where library.skills.skill(skill) == nil {
        unknown("skill", skill, id: lesson.id, path: "skills[\(index)]")
      }
      if lesson.steps.isEmpty { add("lesson.steps", id: lesson.id, "steps", "lesson has no steps") }
      var sawSpot = false
      for (index, step) in lesson.steps.enumerated() {
        let path = "steps[\(index)]"
        if let spot = step.spotID, library.template(spot) == nil {
          unknown("template", spot, id: lesson.id, path: "\(path).spot")
        }
        switch step {
        case .hook, .puzzle:
          sawSpot = true
        case .sandbox:
          if !sawSpot {
            add("lesson.steps", id: lesson.id, path, "sandbox step needs an earlier hook or puzzle step")
          }
        case .explain(let explain):
          if explain.explainers.isEmpty { add("lesson.steps", id: lesson.id, path, "explain step has no explainers") }
          for (e, ref) in explain.explainers.enumerated() {
            checkExplainer(ref, id: lesson.id, path: "\(path).explainers[\(e)]")
          }
        case .apply:
          break
        }
      }
    }

    mutating func checkDrill(_ drill: Drill) {
      for (index, skill) in drill.skills.enumerated() where library.skills.skill(skill) == nil {
        unknown("skill", skill, id: drill.id, path: "skills[\(index)]")
      }
      for (index, spot) in drill.spots.enumerated() where library.template(spot.template) == nil {
        unknown("template", spot.template, id: drill.id, path: "spots[\(index)].template")
      }
    }

    mutating func checkBoss(_ boss: BossSpec) {
      if !library.characters.contains(boss.character) {
        unknown("character", boss.character, id: boss.id, path: "character")
      }
      if library.exam(boss.exam) == nil { unknown("exam", boss.exam, id: boss.id, path: "exam") }
    }

    mutating func checkExam(_ exam: ExamSpec) {
      for (index, draw) in exam.draw.enumerated() where library.template(draw.template) == nil {
        unknown("template", draw.template, id: exam.id, path: "draw[\(index)].template")
      }
      let total = exam.draw.reduce(0) { $0 + $1.count }
      if total != exam.count {
        add("exam.count", id: exam.id, "count", "draws add up to \(total), count is \(exam.count)")
      }
      if exam.pass > exam.count {
        add("exam.count", id: exam.id, "pass", "pass \(exam.pass) is more than count \(exam.count)")
      }
    }

    // MARK: Templates

    mutating func checkTemplate(_ t: SpotTemplate) {
      if library.skills.skill(t.skill) == nil { unknown("skill", t.skill, id: t.id, path: "skill") }
      for (index, ref) in t.explain.enumerated() { checkExplainer(ref, id: t.id, path: "explain[\(index)]") }
      checkPositions(t)
      checkFixed(t)
      checkLine(t)
      checkMethod(t)
    }

    mutating func checkPositions(_ t: SpotTemplate) {
      let valid = SeatPositions.names(count: t.table.players)
      func check(_ names: [SeatPositionName]?, _ path: String, into checker: inout Checker) {
        for name in names ?? [] where !valid.contains(name) {
          checker.add(
            "template.position", id: t.id, path,
            "position '\(name.rawValue)' does not exist at \(t.table.players) players")
        }
      }
      check(t.hero.position, "hero.position", into: &self)
      for (index, villain) in t.villains.enumerated() {
        check(villain.position, "villains[\(index)].position", into: &self)
        for (c, character) in villain.characters.enumerated() where !library.characters.contains(character) {
          unknown("character", character, id: t.id, path: "villains[\(index)].characters[\(c)]")
        }
      }
      if t.villains.count > t.table.players - 1 {
        add(
          "template.position", id: t.id, "villains",
          "\(t.villains.count) villains do not fit at \(t.table.players) players")
      }
    }

    static func boardCount(_ street: Street) -> Int {
      switch street {
      case .preflop: 0
      case .flop: 3
      case .turn: 4
      case .river: 5
      }
    }

    mutating func checkFixed(_ t: SpotTemplate) {
      guard let fixed = t.fixed else { return }
      if let board = fixed.board, board.count != Checker.boardCount(t.board.street) {
        add(
          "template.fixed", id: t.id, "fixed.board",
          "fixed board has \(board.count) cards but street is \(t.board.street.rawValue)")
      }
      if let hero = fixed.hero, hero.count != 2 {
        add("template.fixed", id: t.id, "fixed.hero", "fixed hero has \(hero.count) cards, expected 2")
      }
      for (index, hand) in (fixed.villains ?? []).enumerated() where hand.count != 2 {
        add(
          "template.fixed", id: t.id, "fixed.villains[\(index)]",
          "fixed villain hand has \(hand.count) cards, expected 2")
      }
      if (fixed.villains ?? []).count > t.table.players - 1 {
        add(
          "template.fixed", id: t.id, "fixed.villains", "fixed villain hands do not fit at \(t.table.players) players")
      }
      let all = (fixed.hero ?? []) + (fixed.villains ?? []).flatMap { $0 } + (fixed.board ?? [])
      if Set(all).count != all.count { add("template.fixed", id: t.id, "fixed", "fixed cards contain a duplicate") }
    }

    mutating func checkLine(_ t: SpotTemplate) {
      for street in Street.allCases {
        guard let tokens = t.line.streets[street] else { continue }
        if street > t.board.street {
          add(
            "template.street", id: t.id, "line.\(street.rawValue)",
            "line has \(street.rawValue) actions but the board stops at \(t.board.street.rawValue)")
        }
        for (index, token) in tokens.enumerated() {
          if case .open = token.act, street != .preflop {
            add(
              "template.street", id: t.id, "line.\(street.rawValue)[\(index)]",
              "'\(token)' is only valid on the preflop line")
          }
        }
      }
    }

    mutating func checkMethod(_ t: SpotTemplate) {
      let method = t.evaluation.method
      let rule = ContentValidator.rule(for: method)
      let type = t.question.type
      if !rule.questions.contains(type) {
        add(
          "template.methodQuestion", id: t.id, "question.type",
          "\(method.rawValue) cannot answer a \(type.rawValue) question")
        return
      }
      if let streets = rule.streets, !streets.contains(t.board.street) {
        add(
          "template.street", id: t.id, "board.street",
          "\(method.rawValue) needs street \(streets.map(\.rawValue).joined(separator: "|")), not \(t.board.street.rawValue)"
        )
      }
      let options = t.question.options
      switch method {
      case .closedFormEV, .policyEV:
        checkActionOptions(t, options)
        if method == .policyEV {
          if t.villains.isEmpty || t.villains.contains(where: { $0.characters.isEmpty }) {
            add("template.character", id: t.id, "villains", "policyEV needs a villain character")
          }
        }
      case .pushFold:
        if Set(options ?? []) != ["fold", "allin"] || options?.count != 2 {
          let bad = (options ?? []).first { $0 != "fold" && $0 != "allin" }
          add(
            "template.option", id: t.id, "question.options",
            bad.map { "option '\($0)' is not valid for pushFold" }
              ?? "pushFold needs exactly the options fold and allin")
        }
        if t.table.players != 2 {
          add("template.methodQuestion", id: t.id, "table.players", "pushFold needs exactly 2 players")
        }
        if t.villains.first?.characters.isEmpty ?? true {
          add("template.character", id: t.id, "villains", "pushFold needs a villain character")
        }
      case .rangeMatch:
        if t.line.stopAt != .villain {
          add("template.methodQuestion", id: t.id, "line.stopAt", "rangeMatch needs line.stopAt villain")
        }
        if (t.evaluation.target ?? "policy") == "policy",
          t.villains.isEmpty || t.villains.contains(where: { $0.characters.isEmpty })
        {
          add("template.character", id: t.id, "villains", "rangeMatch with target policy needs a villain character")
        }
      case .legalSizes:
        guard let ask = t.evaluation.ask else {
          add("template.methodQuestion", id: t.id, "evaluation.ask", "legalSizes needs 'ask'")
          break
        }
        let expected: QuestionType = ask == .callCost ? .number : (ask == .minRaise ? .sizeChoice : .choice)
        if type != expected {
          add(
            "template.methodQuestion", id: t.id, "question.type",
            "legalSizes ask \(ask.rawValue) cannot answer a \(type.rawValue) question")
        }
      case .nuts:
        if type == .pickHandClass {
          let names = Set(HandCategoryName.allCases.map(\.rawValue))
          for (index, option) in (options ?? []).enumerated() where !names.contains(option) {
            add("template.option", id: t.id, "question.options[\(index)]", "option '\(option)' is not valid for nuts")
          }
        }
        if type == .pickCards, let pick = t.question.pick, pick != 2 {
          add("template.option", id: t.id, "question.pick", "nuts picks 2 cards, not \(pick)")
        }
      case .bestFive:
        if let pick = t.question.pick, pick != 5 {
          add("template.option", id: t.id, "question.pick", "bestFive picks 5 cards, not \(pick)")
        }
      case .beatsMeCount:
        if type == .choice {
          let ids = t.evaluation.buckets?.map(\.id) ?? ContentValidator.defaultBucketIDs
          if options == nil || options!.isEmpty {
            add("template.option", id: t.id, "question.options", "beatsMeCount choice needs options (bucket ids)")
          }
          for (index, option) in (options ?? []).enumerated() where !ids.contains(option) {
            add("template.option", id: t.id, "question.options[\(index)]", "option '\(option)' is not a bucket id")
          }
        }
      default:
        break
      }
    }

    mutating func checkActionOptions(_ t: SpotTemplate, _ options: [String]?) {
      guard let options, !options.isEmpty else {
        add("template.option", id: t.id, "question.options", "action question needs options")
        return
      }
      var seen = Set<String>()
      for (index, option) in options.enumerated() {
        if !ContentValidator.isValidActionOption(option) {
          add(
            "template.option", id: t.id, "question.options[\(index)]",
            "option '\(option)' is not valid for \(t.evaluation.method.rawValue)")
        } else if !seen.insert(option).inserted {
          add("template.option", id: t.id, "question.options[\(index)]", "duplicate option '\(option)'")
        }
      }
    }

    // MARK: Unused

    mutating func checkUnusedSkills() {
      var used = Set<String>()
      for template in library.templates.values { used.insert(template.skill) }
      for lesson in library.lessons.values { used.formUnion(lesson.skills) }
      for drill in library.drills.values { used.formUnion(drill.skills) }
      for venue in library.venues { for meter in venue.meters { used.formUnion(meter.skills) } }
      for (index, skill) in library.skills.skills.enumerated() where !used.contains(skill.id) {
        add(
          "skill.unused", file: "skills.json", "skills[\(index)]", "skill '\(skill.id)' is not used by any content",
          severity: .warning)
      }
    }
  }
}
