import Foundation
import Testing
@testable import AtlasLog

struct CatalogDecodingTests {
    @Test func bundledCatalogsDecode() async throws {
        let cities = try await CityCatalog().allCities()
        let catalog = RegionCatalog()
        let nodes = try await catalog.nodes()
        let geometries = try await catalog.geometries()
        #expect(cities.count >= 20)
        #expect(nodes.contains { $0.id == "travel:cascadia" })
        #expect(geometries.contains { $0.membership == .transition })
        #expect(geometries.filter { $0.regionID.hasPrefix("country:") }.count >= 170)
        #expect(geometries.filter { $0.regionID.hasPrefix("continent:") }.count == 6)
        #expect(geometries.filter { $0.regionID.hasPrefix("subcontinent:") }.count >= 20)
        #expect(nodes.filter { $0.level == .continent }.allSatisfy { !$0.geometryFeatureIDs.isEmpty })
        #expect(nodes.filter { $0.level == .subcontinent }.allSatisfy { !$0.geometryFeatureIDs.isEmpty })
        let southernAfrica = try #require(
            geometries.first { $0.regionID == "subcontinent:southern-africa" }
        )
        #expect(southernAfrica.definition.contains("dissolved"))
        #expect(southernAfrica.polygons.count == 1)
    }
}
