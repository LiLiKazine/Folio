import SwiftData

/// The first shipped shape of the Library store: the baseline every later schema
/// migrates from. When a model changes, freeze copies of these models inside this
/// enum, add `FolioSchemaV2` with the new shapes, and add a stage to
/// `FolioMigrationPlan`.
enum FolioSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookModel.self, ImportModel.self] }
}

/// Migrations between the Library store's schemas; none yet.
enum FolioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FolioSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
