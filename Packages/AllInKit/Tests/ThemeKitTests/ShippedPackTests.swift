import Testing

@testable import ThemeKit

@Suite struct ShippedPackTests {
  @Test func everyShippedPackIsValid() {
    let reports = ThemeValidator.validateAll(in: ThemeLibrary.sourceTreeThemesDirectory)
    #expect(!reports.isEmpty)
    for report in reports {
      #expect(report.isValid, "\(report.packID ?? report.url.lastPathComponent): \(report.errors)")
    }
    #expect(reports.contains { $0.packID == "hearthwood" })
  }
}
