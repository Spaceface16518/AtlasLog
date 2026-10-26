import Foundation
import SwiftData
import Testing
@testable import AtlasLog

@MainActor
struct TravelRecordServiceTests {
    @Test func statusInvariants() {
        var status = StatusDraft(); status.setMeaningful(true)
        #expect(status.isVisited && status.isMeaningfulVisit && !status.isWantToVisit)
        status.setWantToReturn(true); #expect(status.isVisited && status.isWantToReturn)
        status.setVisited(false); #expect(!status.isMeaningfulVisit && !status.isWantToReturn)
        status.setWantToVisit(true); #expect(status.isWantToVisit && !status.isVisited)
    }

    @Test func countryRollupAndRemoval() throws {
        let container = try makeTestContainer(), context = ModelContext(container), service = TravelRecordService(context: context)
        var meaningful = StatusDraft(); meaningful.setMeaningful(true)
        var limited = StatusDraft(); limited.setVisited(true)
        let first = try service.addVisit(canonicalKey: "one", name: "One", coordinate: .init(longitude: 0, latitude: 0), countryCode: "PE", source: .manual, status: meaningful, startDate: .now)
        _ = try service.addVisit(canonicalKey: "two", name: "Two", coordinate: .init(longitude: 1, latitude: 1), countryCode: "PE", source: .manual, status: limited, startDate: .now)
        try service.delete(first)
        let country = try context.fetch(FetchDescriptor<AreaStatus>()).first { $0.areaID == "country:PE" }
        #expect(country?.isVisited == true); #expect(country?.isMeaningfulVisit == false)
    }

    @Test func manualOverrideSurvivesDerivation() throws {
        let container = try makeTestContainer(), context = ModelContext(container), service = TravelRecordService(context: context)
        let node = RegionNode(id: "country:PE", name: "Peru", level: .country, parentID: nil, centroidLatitude: nil,
                              centroidLongitude: nil, geometryFeatureIDs: [], boundaryKind: .administrative, notes: nil)
        var manual = StatusDraft(); manual.setWantToVisit(true)
        try service.setManualArea(node, status: manual)
        try service.recalculateDerivedAreas()
        let area = try context.fetch(FetchDescriptor<AreaStatus>()).first
        #expect(area?.isManualOverride == true); #expect(area?.isWantToVisit == true)
    }

    @Test func severalCountriesShareOneContinent() throws {
        let container = try makeTestContainer(), context = ModelContext(container), service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setMeaningful(true)
        _ = try service.addVisit(canonicalKey: "london", name: "London", coordinate: .init(longitude: 0, latitude: 51),
                                countryCode: "GB", source: .manual, status: status, startDate: .now)
        _ = try service.addVisit(canonicalKey: "paris", name: "Paris", coordinate: .init(longitude: 2, latitude: 48),
                                countryCode: "FR", source: .manual, status: status, startDate: .now)
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.filter { $0.level == .country && $0.isVisited }.count == 2)
        #expect(areas.filter { $0.areaID == "continent:europe" }.count == 1)
    }

    @Test func visitsRollUpToSubcontinentAndContinent() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let service = TravelRecordService(
            context: context,
            aggregateGeometries: [
                aggregateGeometry(id: "subcontinent:test"),
                aggregateGeometry(id: "continent:test"),
            ],
            regionNodes: []
        )
        var status = StatusDraft()
        status.setMeaningful(true)
        let place = try service.addVisit(
            canonicalKey: "inside",
            name: "Inside",
            coordinate: .init(longitude: 5, latitude: 5),
            countryCode: "XX",
            source: .manual,
            status: status,
            startDate: .now
        )

        var areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.first { $0.areaID == "subcontinent:test" }?.isVisited == true)
        #expect(areas.first { $0.areaID == "continent:test" }?.isMeaningfulVisit == true)

        try service.delete(place.visits[0])
        areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.first { $0.areaID == "subcontinent:test" }?.isVisited == false)
        #expect(areas.first { $0.areaID == "continent:test" }?.isVisited == false)
    }

    @Test func visitedTravelRegionRollsUpItsHierarchy() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let continent = RegionNode(
            id: "continent:test",
            name: "Test Continent",
            level: .continent,
            parentID: nil,
            centroidLatitude: nil,
            centroidLongitude: nil,
            geometryFeatureIDs: [],
            boundaryKind: .geographic,
            notes: nil
        )
        let subcontinent = RegionNode(
            id: "subcontinent:test",
            name: "Test Subcontinent",
            level: .subcontinent,
            parentID: continent.id,
            centroidLatitude: nil,
            centroidLongitude: nil,
            geometryFeatureIDs: [],
            boundaryKind: .geographic,
            notes: nil
        )
        let travelRegion = RegionNode(
            id: "travel:test",
            name: "Test Region",
            level: .travelRegion,
            parentID: subcontinent.id,
            centroidLatitude: nil,
            centroidLongitude: nil,
            geometryFeatureIDs: [],
            boundaryKind: .geographic,
            notes: nil
        )
        let service = TravelRecordService(
            context: context,
            aggregateGeometries: [],
            regionNodes: [continent, subcontinent, travelRegion]
        )
        var status = StatusDraft()
        status.setMeaningful(true)
        try service.setManualArea(travelRegion, status: status)

        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.first { $0.areaID == subcontinent.id }?.isMeaningfulVisit == true)
        #expect(areas.first { $0.areaID == continent.id }?.isVisited == true)
    }

    @Test func multipleVisitsBelongToOneCityAndLastDeletionClearsVisited() throws {
        let container = try makeTestContainer(), context = ModelContext(container), service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setMeaningful(true)
        let firstStart = Date(timeIntervalSince1970: 1_000)
        let place = try service.addVisit(canonicalKey: "cusco", name: "Cusco", coordinate: .init(longitude: -71, latitude: -13),
                                         countryCode: "PE", source: .manual, status: status, startDate: firstStart)
        _ = try service.addVisit(canonicalKey: "cusco", name: "Cusco", coordinate: .init(longitude: -71, latitude: -13),
                                 countryCode: "PE", source: .manual, status: status,
                                 startDate: firstStart.addingTimeInterval(86_400), endDate: firstStart.addingTimeInterval(172_800))

        #expect(try context.fetch(FetchDescriptor<PlaceRecord>()).count == 1)
        #expect(place.visits.count == 2)
        try service.delete(place.visits[0])
        try service.delete(place.visits[0])
        #expect(place.visits.isEmpty)
        #expect(place.isVisited == false)
        #expect(place.isMeaningfulVisit == false)
    }

    @Test func invalidVisitDoesNotCreateOrModifyAPlace() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let service = TravelRecordService(context: context)
        let start = Date(timeIntervalSince1970: 1_000)
        var status = StatusDraft(); status.setMeaningful(true)
        #expect(throws: VisitValidationError.self) {
            try service.addVisit(canonicalKey: "invalid", name: "Invalid", coordinate: .init(longitude: 0, latitude: 0),
                                 source: .manual, status: status, startDate: start, endDate: start.addingTimeInterval(-1))
        }
        #expect(try context.fetch(FetchDescriptor<PlaceRecord>()).isEmpty)

        let place = try service.addVisit(canonicalKey: "london", name: "London", coordinate: .init(longitude: -0.1276, latitude: 51.5072),
                                         countryCode: "GB", source: .manual, status: status, startDate: start)
        #expect(throws: VisitValidationError.self) {
            try service.addVisit(canonicalKey: "london", name: "Changed", coordinate: .init(longitude: 0, latitude: 0),
                                 source: .manual, status: .init(), startDate: start, endDate: start.addingTimeInterval(-1))
        }
        #expect(place.name == "London")
        #expect(place.countryCode == "GB")
        #expect(place.isMeaningfulVisit)
        #expect(place.visits.count == 1)
    }

    @Test func wishlistDoesNotCountAsAVisit() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setWantToVisit(true)
        let place = try service.upsertPlace(canonicalKey: "tokyo", name: "Tokyo", coordinate: .init(longitude: 139.6917, latitude: 35.6895),
                                            countryCode: "JP", source: .manual, status: status)
        #expect(place.isWantToVisit && !place.isVisited)
        #expect(place.visits.isEmpty)
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).isEmpty)
        try service.addVisit(to: place, startDate: .now)
        #expect(place.isVisited && !place.isWantToVisit)
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).contains { $0.areaID == "continent:asia" && $0.isVisited })
    }

    @Test func removingManualRegionClearsItsDerivedAncestors() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let nodes = try RegionCatalog.loadHierarchyNodes()
        let node = try #require(nodes.first { $0.id == "travel:iberia" })
        let service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setMeaningful(true); status.setWantToReturn(true)
        try service.setManualArea(node, status: status)
        var areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.first { $0.areaID == "continent:europe" }?.isWantToReturn == true)
        #expect(areas.first { $0.areaID == "subcontinent:southern-europe" }?.isMeaningfulVisit == true)
        try service.setManualArea(node, status: .init())
        areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.allSatisfy { !$0.isVisited && !$0.isMeaningfulVisit && !$0.isWantToReturn })
    }
}

private func aggregateGeometry(id: String) -> RegionGeometry {
    RegionGeometry(
        id: "\(id)-geometry",
        regionID: id,
        membership: .core,
        boundaryKind: .geographic,
        definition: id,
        source: "test",
        polygons: [
            [
                [
                    [0, 0],
                    [10, 0],
                    [10, 10],
                    [0, 10],
                    [0, 0],
                ],
            ],
        ]
    )
}
