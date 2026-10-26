import Foundation

/// Resolves taps against the same bundled boundaries drawn by the active layer.
struct RegionMapSelection {
    func regionID(at point: CoordinateValue, geometries: [RegionGeometry]) -> String? {
        let matches = geometries.filter {
            !RegionMembershipService().matches(point: point, geometries: [$0]).isEmpty
        }
        // Prefer a local region when it overlaps a broader region on this layer
        // (for example, Washington Capital Region inside U.S. South Atlantic).
        return matches.min { lhs, rhs in
            let left = footprint(of: lhs)
            let right = footprint(of: rhs)
            return left == right ? lhs.regionID < rhs.regionID : left < right
        }?.regionID
    }

    private func footprint(of geometry: RegionGeometry) -> Double {
        guard let box = geometry.boundingBox else { return .infinity }
        return (box.maxLongitude - box.minLongitude) * (box.maxLatitude - box.minLatitude)
    }
}
