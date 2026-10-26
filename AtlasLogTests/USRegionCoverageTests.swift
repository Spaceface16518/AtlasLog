import Foundation
import SwiftData
import Testing
@testable import AtlasLog

struct USRegionCoverageTests {
    @Test func completeUSPackHasValidHierarchyAndGeometry() async throws {
        let catalog = RegionCatalog()
        let nodes = try await catalog.nodes()
        let geometries = try RegionCatalog.loadGeometries(named: ["us_regions"])
        #expect(geometries.count == 14)
        #expect(geometries.filter { $0.regionID.hasPrefix("macro:") }.count == 4)
        #expect(geometries.filter { $0.regionID.hasPrefix("travel:") }.count == 10)
        #expect(Set(nodes.map(\.id)).count == nodes.count)
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for geometry in geometries {
            let node = try #require(nodesByID[geometry.regionID])
            #expect(node.geometryFeatureIDs == [geometry.id])
            #expect(geometry.membership == .core)
            #expect(geometry.source.contains("2025"))
            var ancestor: RegionNode? = node
            var visited = Set<String>()
            while let current = ancestor {
                #expect(visited.insert(current.id).inserted)
                guard let parentID = current.parentID else { break }
                let parent = try #require(nodesByID[parentID])
                ancestor = parent
                if visited.contains(parentID) { break }
            }
            #expect(visited.contains("continent:north-america"))
            for polygon in geometry.polygons {
                for ring in polygon {
                    #expect(ring.count >= 4 && ring.first == ring.last)
                    #expect(ring.allSatisfy { $0.count == 2 && (-180...180).contains($0[0]) && (-90...90).contains($0[1]) })
                }
            }
        }
    }

    @Test func washingtonAndNearbyCitiesAreSearchableOffline() async throws {
        let catalog = CityCatalog()
        for query in ["Washington", "Washington DC", "Washington, D.C.", "DC", "District of Columbia"] {
            let first = try #require(try await catalog.search(query).first)
            #expect(first.id == "4140963")
            #expect(first.countryCode == "US" && first.countryName == "United States")
        }
        for query in ["Arlington", "Alexandria", "Bethesda", "Silver Spring", "Rockville", "Fairfax", "Leesburg", "Baltimore", "Annapolis", "Frederick", "Richmond"] {
            #expect(try await catalog.search(query).contains { $0.name == query && $0.countryCode == "US" })
        }
        let cities = try await catalog.allCities()
        #expect(Set(cities.map(\.id)).count == cities.count)
    }

    @Test func capitalRegionIncludesDCAndSuburbsButExcludesNearbyCitiesOutsideNCPC() async throws {
        let geometries = try RegionCatalog.loadGeometries(named: ["us_regions"])
        let cities = try await CityCatalog().allCities()
        for name in ["Washington, DC", "Arlington", "Alexandria", "Bethesda", "Silver Spring", "Rockville", "Fairfax", "Leesburg"] {
            let city = try #require(cities.first { $0.name == name })
            let ids = matches(city.longitude, city.latitude, in: geometries)
            #expect(ids == ["travel:washington-capital", "travel:us-south-atlantic", "macro:us-south"])
        }
        // Independent Virginia cities must not become holes in the union.
        for point in [(-77.1711, 38.8823), (-77.4753, 38.7509), (-77.4697, 38.7840)] {
            #expect(matches(point.0, point.1, in: geometries).contains("travel:washington-capital"))
        }
        for name in ["Baltimore", "Annapolis", "Frederick", "Richmond"] {
            let city = try #require(cities.first { $0.name == name })
            #expect(matches(city.longitude, city.latitude, in: geometries) == ["travel:us-south-atlantic", "macro:us-south"])
        }
    }

    @Test func censusDivisionsCoverAllPartsOfTheUS() throws {
        let geometries = try RegionCatalog.loadGeometries(named: ["us_regions"])
        let samples: [(Double, Double, String, String)] = [
            (-71.06, 42.36, "new-england", "northeast"),
            (-73.98, 40.75, "middle-atlantic", "northeast"),
            (-87.63, 41.88, "east-north-central", "midwest"),
            (-94.58, 39.10, "west-north-central", "midwest"),
            (-80.84, 35.23, "south-atlantic", "south"),
            (-86.78, 36.16, "east-south-central", "south"),
            (-96.80, 32.78, "west-south-central", "south"),
            (-104.99, 39.74, "mountain", "west"),
            (-118.24, 34.05, "pacific", "west"),
            (-149.90, 61.22, "pacific", "west"),
            (-157.85, 21.31, "pacific", "west"),
        ]
        for (longitude, latitude, division, region) in samples {
            #expect(matches(longitude, latitude, in: geometries) == ["travel:us-\(division)", "macro:us-\(region)"])
        }
        #expect(matches(-0.1276, 51.5072, in: geometries).isEmpty)
    }

    @Test @MainActor func washingtonVisitRollupsRefreshAndClearAfterLastVisit() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setMeaningful(true); status.setWantToReturn(true)
        let place = try service.addVisit(canonicalKey: "geonames:4140963", name: "Washington, DC",
            coordinate: .init(longitude: -77.03637, latitude: 38.89511), countryCode: "US",
            source: .manual, status: status, startDate: .now)
        try service.addVisit(to: place, startDate: .now)
        // Opening the app refreshes old saved visits with the new catalog, too.
        for area in try context.fetch(FetchDescriptor<AreaStatus>()) { context.delete(area) }
        try context.save()
        try service.recalculateDerivedAreas()
        let expected: Set<String> = ["country:US", "travel:washington-capital", "travel:us-south-atlantic",
                                     "macro:us-south", "subcontinent:northern-america", "continent:north-america"]
        var areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(Set(areas.filter(\.isVisited).map(\.areaID)) == expected)
        #expect(areas.allSatisfy { $0.isMeaningfulVisit && $0.isWantToReturn && !$0.isManualOverride })
        let statistics = PassportStatisticsService().calculate(places: [place], areas: areas)
        #expect(statistics.travelRegionsVisited == 2 && statistics.citiesVisited == 1)
        try service.delete(place.visits[0])
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).allSatisfy(\.isVisited))
        try service.delete(place.visits[0])
        areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.allSatisfy { !$0.isVisited && !$0.isMeaningfulVisit && !$0.isWantToReturn })
    }

    @Test @MainActor func capitalManualStatusRollsUpAndPreservesOverrides() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = TravelRecordService(context: context)
        let nodes = try RegionCatalog.loadHierarchyNodes()
        let capital = try #require(nodes.first { $0.id == "travel:washington-capital" })
        let south = try #require(nodes.first { $0.id == "macro:us-south" })
        var wishlist = StatusDraft(); wishlist.setWantToVisit(true)
        try service.setManualArea(south, status: wishlist)
        var visited = StatusDraft(); visited.setMeaningful(true)
        try service.setManualArea(capital, status: visited)
        var areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.first { $0.areaID == "travel:us-south-atlantic" }?.isMeaningfulVisit == true)
        #expect(areas.first { $0.areaID == south.id }?.isWantToVisit == true)
        #expect(areas.first { $0.areaID == south.id }?.isVisited == false)
        try service.setManualArea(capital, status: .init())
        areas = try context.fetch(FetchDescriptor<AreaStatus>())
        #expect(areas.allSatisfy { !$0.isVisited && !$0.isMeaningfulVisit })
        #expect(areas.first { $0.areaID == south.id }?.isWantToVisit == true)
    }

    private func matches(_ longitude: Double, _ latitude: Double, in geometries: [RegionGeometry]) -> Set<String> {
        Set(RegionMembershipService().matches(point: .init(longitude: longitude, latitude: latitude),
                                             geometries: geometries).map(\.regionID))
    }
}
