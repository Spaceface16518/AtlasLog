import Foundation

struct RegionMatch: Equatable, Sendable {
    let regionID: String
    let membership: RegionMembership
}

struct RegionMembershipService: Sendable {
    func matches(point: CoordinateValue, geometries: [RegionGeometry]) -> [RegionMatch] {
        geometries.compactMap { geometry in
            guard geometry.boundingBox?.contains(point) == true else { return nil }
            let inside = geometry.polygons.contains { polygon in
                guard let exterior = polygon.first, pointInRing(point, ring: exterior) else { return false }
                return !polygon.dropFirst().contains { pointInRing(point, ring: $0) }
            }
            return inside ? RegionMatch(regionID: geometry.regionID, membership: geometry.membership) : nil
        }
    }

    private func pointInRing(_ point: CoordinateValue, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentPoint = ring[index]
            let previousPoint = ring[previous]
            guard currentPoint.count >= 2, previousPoint.count >= 2 else { continue }
            let crosses = ((currentPoint[1] > point.latitude) != (previousPoint[1] > point.latitude)) &&
                (point.longitude < (previousPoint[0] - currentPoint[0]) * (point.latitude - currentPoint[1]) /
                    ((previousPoint[1] - currentPoint[1]) == 0 ? .leastNonzeroMagnitude : previousPoint[1] - currentPoint[1]) + currentPoint[0])
            if crosses { inside.toggle() }
            previous = index
        }
        return inside
    }
}
