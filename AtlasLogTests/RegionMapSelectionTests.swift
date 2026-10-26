import Testing
@testable import AtlasLog

struct RegionMapSelectionTests {
    @Test func selectsTheMostLocalOverlappingRegionRegardlessOfDrawOrder() throws {
        let geometries = try RegionCatalog.loadGeometries(named: ["us_regions"])
            .filter { $0.regionID.hasPrefix("travel:") }
        let washington = CoordinateValue(longitude: -77.0369, latitude: 38.9072)
        let selection = RegionMapSelection()
        let expected = "travel:washington-capital"
        #expect(selection.regionID(at: washington, geometries: geometries) == expected)
        #expect(selection.regionID(at: washington, geometries: geometries.reversed()) == expected)
    }

    @Test func selectsUnvisitedCountryAndOffshorePolygon() throws {
        let geometries = try RegionCatalog.loadGeometries(named: ["country_boundaries"])
        #expect(RegionMapSelection().regionID(at: .init(longitude: 2.35, latitude: 48.86), geometries: geometries) == "country:FR")
        #expect(RegionMapSelection().regionID(at: .init(longitude: -155.5, latitude: 19.6), geometries: geometries) == "country:US")
        #expect(RegionMapSelection().regionID(at: .init(longitude: -30, latitude: 0), geometries: geometries) == nil)
    }

    @Test func polygonHolesDoNotSelectTheirSurroundingRegion() {
        let geometry = RegionGeometry(id: "donut", regionID: "donut", membership: .core,
                                      boundaryKind: .administrative, definition: "", source: "",
                                      polygons: [[[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                                                  [[3, 3], [7, 3], [7, 7], [3, 7], [3, 3]]]])
        #expect(RegionMapSelection().regionID(at: .init(longitude: 5, latitude: 5), geometries: [geometry]) == nil)
        #expect(RegionMapSelection().regionID(at: .init(longitude: 1, latitude: 1), geometries: [geometry]) == "donut")
    }

    @Test func activeLayerRestrictsSelection() throws {
        let geometries = try RegionCatalog.loadGeometries(named: ["composed_regions", "us_regions"])
        let washington = CoordinateValue(longitude: -77.0369, latitude: 38.9072)
        for prefix in ["macro:", "subcontinent:", "continent:"] {
            let layer = geometries.filter { $0.regionID.hasPrefix(prefix) }
            #expect(RegionMapSelection().regionID(at: washington, geometries: layer)?.hasPrefix(prefix) == true)
        }
        #expect(RegionMapSelection().regionID(at: washington, geometries: []) == nil)
    }
}
