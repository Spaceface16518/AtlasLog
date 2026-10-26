import Foundation
import SwiftData
import Testing
@testable import AtlasLog

@MainActor
struct MigrationTests {
    @Test func existingTravelHistorySurvivesV2Migration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("travel.store")
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        try autoreleasepool {
            let schema = Schema(SchemaV1.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            var visited = StatusDraft(); visited.setMeaningful(true)
            context.insert(SchemaV1.PlaceRecord(canonicalKey: "london", name: "London", latitude: 51.5072, longitude: -0.1276,
                                                countryCode: "GB", status: visited, firstVisitedAt: start, lastVisitedAt: end,
                                                notes: "Keep this note", source: .photoImport))
            var wishlist = StatusDraft(); wishlist.setWantToVisit(true)
            context.insert(SchemaV1.PlaceRecord(canonicalKey: "tokyo", name: "Tokyo", latitude: 35.6895, longitude: 139.6917,
                                                countryCode: "JP", status: wishlist))
            try context.save()
        }

        let schema = Schema(SchemaV2.models)
        let container = try ModelContainer(for: schema, migrationPlan: AtlasMigrationPlan.self,
                                           configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let london = try #require(places.first { $0.canonicalKey == "london" })
        let visit = try #require(london.visits.first)
        #expect(london.visits.count == 1)
        #expect(visit.startDate == start && visit.endDate == end)
        #expect(visit.source == .photoImport)
        #expect(london.notes == "Keep this note")
        #expect(london.isMeaningfulVisit)
        let tokyo = try #require(places.first { $0.canonicalKey == "tokyo" })
        #expect(tokyo.isWantToVisit && tokyo.visits.isEmpty)

        try TravelRecordService(context: context).recalculateDerivedAreas()
        try context.save()
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.contains { $0.areaID == "subcontinent:northern-europe" && $0.isMeaningfulVisit })
        #expect(areas.contains { $0.areaID == "continent:europe" && $0.isVisited })
    }
}
