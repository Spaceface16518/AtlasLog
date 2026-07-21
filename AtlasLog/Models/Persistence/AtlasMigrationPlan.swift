import SwiftData

enum AtlasMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil
    ) { context in
        let places = try context.fetch(FetchDescriptor<SchemaV2.PlaceRecord>())
        for place in places where place.isVisited && place.visits.isEmpty {
            let start = place.firstVisitedAt ?? place.lastVisitedAt ?? place.createdAt
            let end = place.lastVisitedAt.flatMap { $0 > start ? $0 : nil }
            context.insert(SchemaV2.VisitRecord(
                startDate: start,
                endDate: end,
                source: VisitSource(rawValue: place.sourceRawValue) ?? .manual,
                place: place
            ))
            place.firstVisitedAt = nil
            place.lastVisitedAt = nil
        }
        try context.save()
    }
}
