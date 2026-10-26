import Foundation
import CoreLocation

struct CoordinateValue: Codable, Hashable, Sendable {
    let longitude: Double
    let latitude: Double
    var clCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct BoundingBox: Hashable, Sendable {
    let minLongitude: Double
    let minLatitude: Double
    let maxLongitude: Double
    let maxLatitude: Double

    func contains(_ point: CoordinateValue) -> Bool {
        point.longitude >= minLongitude && point.longitude <= maxLongitude &&
        point.latitude >= minLatitude && point.latitude <= maxLatitude
    }
}

struct RegionGeometry: Identifiable, Hashable, Sendable {
    let id: String
    let regionID: String
    let membership: RegionMembership
    let boundaryKind: BoundaryKind
    let definition: String
    let source: String
    let polygons: [[[[Double]]]]

    var boundingBox: BoundingBox? {
        let points = polygons.flatMap { $0 }.flatMap { $0 }
        guard let first = points.first, first.count >= 2 else { return nil }
        return points.dropFirst().reduce(
            BoundingBox(minLongitude: first[0], minLatitude: first[1], maxLongitude: first[0], maxLatitude: first[1])
        ) { box, point in
            guard point.count >= 2 else { return box }
            return BoundingBox(minLongitude: min(box.minLongitude, point[0]), minLatitude: min(box.minLatitude, point[1]),
                               maxLongitude: max(box.maxLongitude, point[0]), maxLatitude: max(box.maxLatitude, point[1]))
        }
    }
}

struct GeoJSONFeatureCollection: Decodable, Sendable {
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Decodable, Sendable {
    struct Properties: Decodable, Sendable {
        let featureID: String
        let regionID: String
        let membership: RegionMembership
        let boundaryKind: BoundaryKind
        let definition: String
        let source: String
    }
    struct Geometry: Decodable, Sendable {
        let type: String
        let coordinates: JSONValue
    }
    let properties: Properties
    let geometry: Geometry
}

indirect enum JSONValue: Decodable, Sendable {
    case number(Double)
    case array([JSONValue])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .other }
    }

    func coordinateArrays(depth: Int) -> [[[[Double]]]]? {
        guard case let .array(level1) = self else { return nil }
        func pair(_ value: JSONValue) -> [Double]? {
            guard case let .array(values) = value, values.count >= 2,
                  case let .number(x) = values[0], case let .number(y) = values[1] else { return nil }
            return [x, y]
        }
        func ring(_ value: JSONValue) -> [[Double]]? {
            guard case let .array(values) = value else { return nil }
            let pairs = values.compactMap(pair)
            return pairs.count == values.count ? pairs : nil
        }
        func polygon(_ value: JSONValue) -> [[[Double]]]? {
            guard case let .array(values) = value else { return nil }
            let rings = values.compactMap(ring)
            return rings.count == values.count ? rings : nil
        }
        if depth == 3 {
            let rings = level1.compactMap(ring)
            return rings.count == level1.count ? [rings] : nil
        }
        let polygons = level1.compactMap(polygon)
        return polygons.count == level1.count ? polygons : nil
    }
}
