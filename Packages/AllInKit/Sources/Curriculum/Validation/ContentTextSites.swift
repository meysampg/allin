import Foundation

/// A piece of author text with `{placeholders}` and the template whose bindings fill it.
struct TextSite: Sendable {
  let templateID: String
  let method: EvaluationMethod
  let text: String
  let file: String
  let path: String
}

extension ContentValidator {
  /// The prompt, coach and hint of every template, and the coach, hint, thinking and challenge text of every lesson step
  /// (bound by the spot of the step, or of the nearest earlier spot step).
  static func textSites(_ library: ContentLibrary) -> [TextSite] {
    var sites: [TextSite] = []
    for id in library.templates.keys.sorted() {
      guard let template = library.templates[id] else { continue }
      let file = library.fileOf[id] ?? ""
      let method = template.evaluation.method
      sites.append(TextSite(templateID: id, method: method, text: template.prompt, file: file, path: "prompt"))
      if let coach = template.coach {
        sites.append(TextSite(templateID: id, method: method, text: coach, file: file, path: "coach"))
      }
      if let hint = template.hint {
        sites.append(TextSite(templateID: id, method: method, text: hint, file: file, path: "hint"))
      }
    }
    for id in library.lessons.keys.sorted() {
      guard let lesson = library.lessons[id] else { continue }
      let file = library.fileOf[id] ?? ""
      var current: SpotTemplate?
      func add(_ text: String?, _ path: String) {
        guard let text, let template = current else { return }
        sites.append(
          TextSite(templateID: template.id, method: template.evaluation.method, text: text, file: file, path: path))
      }
      for (index, step) in lesson.steps.enumerated() {
        let path = "steps[\(index)]"
        switch step {
        case .hook(let spot), .puzzle(let spot):
          current = library.templates[spot.spot]
          add(spot.coach, "\(path).coach")
          add(spot.hint, "\(path).hint")
        case .apply(let apply):
          current = library.templates[apply.spot]
          add(apply.coach, "\(path).coach")
        case .explain(let explain):
          add(explain.thinking, "\(path).thinking")
        case .sandbox(let sandbox):
          add(sandbox.challenge, "\(path).challenge")
        }
      }
    }
    return sites
  }

  /// `placeholder.unresolved` issues for one text, checked against `keys`.
  static func placeholderIssues(_ site: TextSite, keys: Set<String>) -> [ContentIssue] {
    do {
      return try TextBinder.placeholders(in: site.text).filter { !keys.contains($0) }.map {
        ContentIssue(
          .error, code: "placeholder.unresolved", file: site.file, path: site.path,
          message: "unknown placeholder {\($0)} for \(site.method.rawValue)")
      }
    } catch {
      return [
        ContentIssue(.error, code: "placeholder.unresolved", file: site.file, path: site.path, message: "\(error)")
      ]
    }
  }

  /// Static: template prompt, coach and hint use only the keys of the template's method; lesson text only the keys of
  /// the method of the step's spot.
  public static func placeholders(_ library: ContentLibrary) -> [ContentIssue] {
    var seen = Set<ContentIssue>()
    var issues: [ContentIssue] = []
    for site in textSites(library) {
      for issue in placeholderIssues(site, keys: TextBinder.keys(for: site.method)) where seen.insert(issue).inserted {
        issues.append(issue)
      }
    }
    return issues
  }
}
