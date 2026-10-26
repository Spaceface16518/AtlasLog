import Testing
@testable import AtlasLog

struct PassportStatisticsTests {
    @Test func emptyStore() { #expect(PassportStatisticsService().calculate(places: [], areas: []) == .empty) }
    @Test func meaningfulLimitedWishlistAndReturn() {
        var meaningful = StatusDraft(); meaningful.setMeaningful(true); meaningful.setWantToReturn(true)
        var wishlist = StatusDraft(); wishlist.setWantToVisit(true)
        let visited = PlaceRecord(canonicalKey: "1", name: "Lima", latitude: 0, longitude: 0, status: meaningful)
        let future = PlaceRecord(canonicalKey: "2", name: "Tokyo", latitude: 0, longitude: 0, status: wishlist)
        let country = AreaStatus(areaID: "country:PE", level: .country, status: meaningful)
        let region = AreaStatus(areaID: "travel:andes", level: .travelRegion, status: meaningful, isManualOverride: true)
        let result = PassportStatisticsService().calculate(places: [visited, future], areas: [country, region])
        #expect(result.citiesVisited == 1); #expect(result.countriesVisited == 1); #expect(result.meaningfulCountries == 1)
        #expect(result.wantToVisit == 1); #expect(result.wantToReturn == 3); #expect(result.travelRegionsVisited == 1)
    }
}
