import Testing
@testable import AtlasLog

struct CityMatchingTests {
    @Test func exactNearbyCity() async throws {
        let catalog = CityCatalog(cities: [city("1", "Lima", -12.04, -77.03)])
        #expect(try await catalog.nearest(to: .init(longitude: -77.031, latitude: -12.041))?.city.name == "Lima")
    }
    @Test func populationBreaksNearTie() async throws {
        let catalog = CityCatalog(cities: [city("1", "Small", 0, 0, population: 10), city("2", "Large", 0, 0, population: 1_000_000)])
        #expect(try await catalog.nearest(to: .init(longitude: 0, latitude: 0))?.city.name == "Large")
    }
    @Test func noCityInsideThreshold() async throws {
        let catalog = CityCatalog(cities: [city("1", "Far", 20, 20)])
        #expect(try await catalog.nearest(to: .init(longitude: 0, latitude: 0), thresholdKilometers: 10) == nil)
    }
    @Test func internationalDateLineDistance() { #expect(CityCatalog.haversine(from: .init(longitude: 179.9, latitude: 0), to: .init(longitude: -179.9, latitude: 0)) < 25) }
    @Test func hemisphereDistanceIsSymmetric() {
        let north = CoordinateValue(longitude: 20, latitude: 30), south = CoordinateValue(longitude: 20, latitude: -30)
        #expect(CityCatalog.haversine(from: north, to: south) == CityCatalog.haversine(from: south, to: north))
    }
}
