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
        let first = try service.upsert(canonicalKey: "one", name: "One", coordinate: .init(longitude: 0, latitude: 0), countryCode: "PE", source: .manual, status: meaningful)
        _ = try service.upsert(canonicalKey: "two", name: "Two", coordinate: .init(longitude: 1, latitude: 1), countryCode: "PE", source: .manual, status: limited)
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
        _ = try service.upsert(canonicalKey: "london", name: "London", coordinate: .init(longitude: 0, latitude: 51),
                               countryCode: "GB", source: .manual, status: status)
        _ = try service.upsert(canonicalKey: "paris", name: "Paris", coordinate: .init(longitude: 2, latitude: 48),
                               countryCode: "FR", source: .manual, status: status)
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.filter { $0.level == .country && $0.isVisited }.count == 2)
        #expect(areas.filter { $0.areaID == "continent:europe" }.count == 1)
    }
}
