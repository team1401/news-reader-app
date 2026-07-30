import Foundation
import SwiftData

/// Singleton row for device-local preferences that must survive relaunch and that
/// belong with the data rather than in `UserDefaults` — so an in-memory test
/// container is a complete, self-contained world.
@Model
public final class StoredPreferences {
    @Attribute(.unique) public var id: String
    /// Set once, the first time starter sources are seeded. It is what makes
    /// seeding idempotent: a reader who deletes BBC News does not get it back.
    public var hasSeededStarterSources: Bool
    /// The demo edition is an explicit, offline-only preview. Off by default.
    public var demoModeEnabled: Bool
    public var lastFullRefreshAt: Date?

    public init(
        id: String = StoredPreferences.singletonID,
        hasSeededStarterSources: Bool = false,
        demoModeEnabled: Bool = false,
        lastFullRefreshAt: Date? = nil
    ) {
        self.id = id
        self.hasSeededStarterSources = hasSeededStarterSources
        self.demoModeEnabled = demoModeEnabled
        self.lastFullRefreshAt = lastFullRefreshAt
    }

    public static let singletonID = "broadsheet.preferences"
}

/// Version 1 of the on-device schema.
///
/// Every future release adds a new `BroadsheetSchemaV<n>` and a stage in
/// ``BroadsheetMigrationPlan``. Naming the version now is what makes that possible
/// without a destructive reset: an unversioned container cannot be migrated later.
public enum BroadsheetSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [StoredSource.self, StoredArticle.self, StoredAnalysis.self, StoredPreferences.self]
    }
}

public enum BroadsheetMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [BroadsheetSchemaV1.self] }

    /// Empty while V1 is the only version. A stage is added here, never a
    /// container reset, when the schema changes.
    public static var stages: [MigrationStage] { [] }
}

public enum PersistenceController {
    public static let schema = Schema(versionedSchema: BroadsheetSchemaV1.self)

    /// The app's durable container.
    ///
    /// The store URL is explicit and its directory is created first: a fresh
    /// container (and a test host) may have no Application Support directory yet,
    /// and SwiftData's default path does not create one.
    public static func makeContainer() throws -> ModelContainer {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = directory.appendingPathComponent("Broadsheet.store")

        return try ModelContainer(
            for: schema,
            migrationPlan: BroadsheetMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    /// A disposable container for tests and for UI-test runs that must not touch
    /// the reader's real library.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: BroadsheetMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
