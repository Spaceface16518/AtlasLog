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
}
