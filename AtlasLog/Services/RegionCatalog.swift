import Foundation
import OSLog

actor RegionCatalog {
    private let bundle: Bundle
    private var cachedNodes: [RegionNode]?
    private var cachedGeometry: [RegionGeometry]?

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func nodes() throws -> [RegionNode] {
        if let cachedNodes { return cachedNodes }
        var nodes = try Self.loadHierarchyNodes(bundle: bundle)
        let countries = try geometries().filter { $0.regionID.hasPrefix("country:") }
        nodes.append(contentsOf: countries.compactMap { geometry in
            guard let box = geometry.boundingBox else { return nil }
            return RegionNode(id: geometry.regionID, name: geometry.definition, level: .country,
                              parentID: nil,
                              centroidLatitude: (box.minLatitude + box.maxLatitude) / 2,
                              centroidLongitude: (box.minLongitude + box.maxLongitude) / 2,
                              geometryFeatureIDs: [geometry.id], boundaryKind: .administrative, notes: nil)
        })
        cachedNodes = nodes
        return nodes
    }

    func geometries() throws -> [RegionGeometry] {
        if let cachedGeometry { return cachedGeometry }
        let result = try Self.loadGeometries(
            named: [
                "country_boundaries",
                "travel_regions",
                "composed_regions",
                "us_regions",
            ],
            bundle: bundle
        )
        cachedGeometry = result
        return result
    }

    nonisolated static func loadHierarchyNodes(
        bundle: Bundle = .main
    ) throws -> [RegionNode] {
        try decode(
            "region_hierarchy",
            extension: "json",
            bundle: bundle
        )
    }

    nonisolated static func loadGeometries(
        named resourceNames: [String],
        bundle: Bundle = .main
    ) throws -> [RegionGeometry] {
        let features = try resourceNames.flatMap { name in
            let collection: GeoJSONFeatureCollection = try decode(
                name,
                extension: "geojson",
                bundle: bundle
            )
            return collection.features
        }
        return features.compactMap { feature -> RegionGeometry? in
            let depth = feature.geometry.type == "Polygon" ? 3 : 4
            guard let polygons = feature.geometry.coordinates.coordinateArrays(depth: depth) else { return nil }
            return RegionGeometry(id: feature.properties.featureID, regionID: feature.properties.regionID,
                                  membership: feature.properties.membership, boundaryKind: feature.properties.boundaryKind,
                                  definition: feature.properties.definition, source: feature.properties.source,
                                  polygons: polygons)
        }
    }

    func reload() { cachedNodes = nil; cachedGeometry = nil }

    private func decode<T: Decodable>(_ name: String, extension ext: String) throws -> T {
        try Self.decode(name, extension: ext, bundle: bundle)
    }

    nonisolated private static func decode<T: Decodable>(
        _ name: String,
        extension ext: String,
        bundle: Bundle
    ) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw CatalogError.missingResource("\(name).\(ext)")
        }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch {
            AppLogger.catalog.error("Region resource decode failed: \(error.localizedDescription, privacy: .public)")
            throw CatalogError.invalidResource(name)
        }
    }
}
