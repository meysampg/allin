import Foundation
import Testing

@testable import Curriculum

@Suite struct FixturePackValidationTests {
  @Test func fixturePackIsClean() async {
    var options = ValidationOptions()
    options.instances = 500
    options.evInstances = 2
    // Rollout noise is irrelevant to the checks here and debug builds are slow (EV rollouts); `allin-tool content validate` gates 40 or more in release, with .validation.
    options.budget = .test
    let clock = ContinuousClock()
    let start = clock.now
    let report = await ContentValidator.validate(ContentTestSupport.fixture, options: options)
    print("fixture validation took \(start.duration(to: clock.now))")
    for line in report.lines() { print(line) }
    #expect(report.errors.isEmpty, "\(report.errors.map(\.description))")
    #expect(report.templates.count == ContentTestSupport.fixture.templates.count)
    for template in report.templates { #expect(template.generated == template.requested, "\(template.templateID)") }
  }
}
