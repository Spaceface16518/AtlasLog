import Foundation
import OSLog

enum CatalogError: LocalizedError {
    case missingResource(String)
    case invalidResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Missing bundled resource: \(name)."
        case .invalidResource(let name): "The bundled \(name) data is invalid."
        }
    }
}

actor CityCatalog {
    private var cachedCities: [CityRecord]?
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    init(cities: [CityRecord]) {
        bundle = .main
        cachedCities = cities
    }

    func allCities() throws -> [CityRecord] {
        if let cachedCities { return cachedCities }
        guard let url = bundle.url(forResource: "major_cities", withExtension: "json") else {
            throw CatalogError.missingResource("major_cities.json")
        }
        do {
            let cities = try JSONDecoder().decode([CityRecord].self, from: Data(contentsOf: url))
            cachedCities = cities
            return cities
        } catch {
            AppLogger.catalog.error("City catalog decode failed: \(error.localizedDescription, privacy: .public)")
            throw CatalogError.invalidResource("city catalog")
        }
    }

    func search(_ query: String, limit: Int = 12) throws -> [CityRecord] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return [] }
        return try allCities().compactMap { city -> (CityRecord, Int)? in
            let alternate = city.alternateNames.map(Self.normalize)
            let score: Int
            if city.normalizedName == normalized { score = 0 }
            else if city.normalizedName.hasPrefix(normalized) { score = 1 }
            else if alternate.contains(where: { $0.hasPrefix(normalized) }) { score = 2 }
            else if city.normalizedName.split(separator: " ").contains(where: { $0.hasPrefix(normalized) }) { score = 3 }
            else { return nil }
            return (city, score)
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? (lhs.0.population ?? 0) > (rhs.0.population ?? 0) : lhs.1 < rhs.1
        }
        .prefix(limit)
        .map(\.0)
    }

    func nearest(to coordinate: CoordinateValue, thresholdKilometers: Double = 50) throws -> CityMatch? {
        let cities = try allCities()
        var ranked: [(city: CityRecord, distance: Double)] = []
        for city in cities {
            let cityCoordinate = CoordinateValue(longitude: city.longitude, latitude: city.latitude)
            let distance = Self.haversine(from: coordinate, to: cityCoordinate)
            ranked.append((city, distance))
        }
        ranked.sort { lhs, rhs in
            if abs(lhs.distance - rhs.distance) < 0.25 {
                return (lhs.city.population ?? 0) > (rhs.city.population ?? 0)
            }
            return lhs.distance < rhs.distance
        }
        guard let first = ranked.first, first.1 <= thresholdKilometers else { return nil }
        return CityMatch(city: first.0, distanceKilometers: first.1)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    static func haversine(from: CoordinateValue, to: CoordinateValue) -> Double {
        let radius = 6_371.0
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct CityMatch: Sendable, Equatable {
    let city: CityRecord
    let distanceKilometers: Double
}
