import Foundation
import SwiftData

/// Builds the `ModelContainer` with the current schema and the migration plan.
public enum AllInPersistence {
  /// - Parameters:
  ///   - url: explicit store file; `nil` uses SwiftData's default location.
  ///   - inMemory: ignores `url` and keeps nothing on disk (tests, demo mode).
  public static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema(versionedSchema: AllInSchemaV1.self)
    if inMemory {
      return try ModelContainer(
        for: schema, migrationPlan: AllInMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    if let url {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      return try ModelContainer(
        for: schema, migrationPlan: AllInMigrationPlan.self,
        configurations: ModelConfiguration(schema: schema, url: url))
    }
    return try ModelContainer(for: schema, migrationPlan: AllInMigrationPlan.self)
  }
}
