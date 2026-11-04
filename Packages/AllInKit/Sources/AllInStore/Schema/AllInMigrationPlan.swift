import SwiftData

/// Only V1 exists so far; later versions add stages here.
public enum AllInMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] { [AllInSchemaV1.self] }
  public static var stages: [MigrationStage] { [] }
}
