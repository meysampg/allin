import Foundation
import Testing

@testable import Curriculum

@Suite struct ShippedContentValidationTests {
  /// Skipped while `Content/` has no realm.json (M6 ships the real curriculum; then this is the gate).
  @Test func shippedContentValidates() async throws {
    let root = ContentLibrary.sourceTreeRoot
    guard ContentLibrary.hasCurriculum(at: root) else {
      print("skipped: no realm.json in \(root.path) yet")
      return
    }
    let library = try ContentLibrary.load(root: root)
    let report = await ContentValidator.validate(library)
    for line in report.lines() { print(line) }
    #expect(report.errors.isEmpty, "\(report.errors.map(\.description))")
  }
}
