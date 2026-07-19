import Foundation

struct CityRecord: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let normalizedName: String
    let alternateNames: [String]
    let latitude: Double
    let longitude: Double
    let countryCode: String
    let countryName: String
    let administrativeArea: String?
    let population: Int?

    var canonicalKey: String { "geonames:\(id)" }
}

enum RegionLevel: String, Codable, CaseIterable, Sendable {
    case city, country, travelRegion, macroRegion, subcontinent, continent

    var title: String {
        switch self {
        case .city: "Cities"
        case .country: "Countries"
        case .travelRegion: "Travel regions"
        case .macroRegion: "Large regions"
        case .subcontinent: "Subcontinents"
        case .continent: "Continents"
        }
    }
}

enum BoundaryKind: String, Codable, Sendable {
    case administrative, geographic, culturalApproximation, itineraryApproximation
}

struct RegionNode: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let level: RegionLevel
    let parentID: String?
    let centroidLatitude: Double?
    let centroidLongitude: Double?
    let geometryFeatureIDs: [String]
    let boundaryKind: BoundaryKind
    let notes: String?
}

enum RegionMembership: String, Codable, Sendable { case core, transition, associated }
