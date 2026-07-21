import Foundation
import SwiftData
@testable import AtlasLog

@MainActor
func makeTestContainer() throws -> ModelContainer {
    let schema = Schema(SchemaV2.models)
    return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
}

func city(_ id: String, _ name: String, _ latitude: Double, _ longitude: Double, population: Int = 1_000) -> CityRecord {
    CityRecord(id: id, name: name, normalizedName: CityCatalog.normalize(name), alternateNames: [],
               latitude: latitude, longitude: longitude, countryCode: "XX", countryName: "Testland",
               administrativeArea: nil, population: population)
}
