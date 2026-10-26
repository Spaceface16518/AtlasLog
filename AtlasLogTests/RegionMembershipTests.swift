import Testing
@testable import AtlasLog

struct RegionMembershipTests {
    private func geometry(id: String = "region", membership: RegionMembership = .core, polygons: [[[[Double]]]]) -> RegionGeometry {
        RegionGeometry(id: id, regionID: id, membership: membership, boundaryKind: .administrative,
                       definition: "Test", source: "Test", polygons: polygons)
    }
    private let square = [[[0.0,0.0],[10,0],[10,10],[0,10],[0,0]]]

    @Test func pointInCorePolygon() { #expect(RegionMembershipService().matches(point: .init(longitude: 5, latitude: 5), geometries: [geometry(polygons: [square])]).count == 1) }
    @Test func pointInTransitionPolygon() { #expect(RegionMembershipService().matches(point: .init(longitude: 5, latitude: 5), geometries: [geometry(membership: .transition, polygons: [square])]).first?.membership == .transition) }
    @Test func pointOutside() { #expect(RegionMembershipService().matches(point: .init(longitude: 20, latitude: 20), geometries: [geometry(polygons: [square])]).isEmpty) }
    @Test func pointInMultipolygon() {
        let other = [[[20.0,20.0],[30,20],[30,30],[20,30],[20,20]]]
        #expect(RegionMembershipService().matches(point: .init(longitude: 25, latitude: 25), geometries: [geometry(polygons: [square, other])]).count == 1)
    }
    @Test func pointInHoleIsExcluded() {
        let hole = [[3.0,3.0],[7,3],[7,7],[3,7],[3,3]]
        #expect(RegionMembershipService().matches(point: .init(longitude: 5, latitude: 5), geometries: [geometry(polygons: [[square[0], hole]])]).isEmpty)
    }
    @Test func boundingBoxRejects() { #expect(geometry(polygons: [square]).boundingBox?.contains(.init(longitude: -1, latitude: -1)) == false) }
}
