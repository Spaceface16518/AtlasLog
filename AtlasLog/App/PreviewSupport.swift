#if DEBUG
import SwiftData
import SwiftUI

@MainActor
enum PreviewSupport {
    static let nodes = [
        RegionNode(id: "continent:SA", name: "South America", level: .continent, parentID: nil,
                   centroidLatitude: -15, centroidLongitude: -60, geometryFeatureIDs: [],
                   boundaryKind: .geographic, notes: "A continent preview fixture."),
        RegionNode(id: "country:PE", name: "Peru", level: .country, parentID: "continent:SA",
                   centroidLatitude: -9.19, centroidLongitude: -75.02, geometryFeatureIDs: [],
                   boundaryKind: .administrative, notes: "Pacific coast, Andes, and Amazon basin.")
    ]

    static var place: PlaceRecord {
        var status = StatusDraft()
        status.setMeaningful(true)
        status.setWantToReturn(true)
        return PlaceRecord(canonicalKey: "preview:cusco", name: "Cusco", latitude: -13.523, longitude: -71.967,
                           countryCode: "PE", countryName: "Peru", status: status,
                           notes: "A favorite high-altitude stop.", source: .sample)
    }

    static var candidate: PhotoImportCandidate {
        PhotoImportCandidate(id: "cusco", canonicalKey: "cusco", proposedName: "Cusco",
            proposedCountry: "Peru", countryCode: "PE", coordinate: .init(longitude: -71.97, latitude: -13.52),
            photoCount: 12, earliestDate: .now.addingTimeInterval(-86_400 * 4), latestDate: .now,
            confidence: .high, matchingMethod: .bundledCity, assetIdentifiers: [],
            suggestedRegionIDs: ["travel:andes"])
    }

    static func container(populated: Bool = false) -> ModelContainer {
        do {
            let schema = Schema(SchemaV1.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            if populated {
                let context = ModelContext(container)
                var status = StatusDraft(); status.setMeaningful(true); status.setWantToReturn(true)
                context.insert(PlaceRecord(canonicalKey: "preview:lima", name: "Lima", latitude: -12.04, longitude: -77.03,
                                           countryCode: "PE", countryName: "Peru", status: status, source: .sample))
                context.insert(AreaStatus(areaID: "country:PE", level: .country, status: status))
                try context.save()
            }
            return container
        } catch { fatalError("Preview container failed: \(error)") }
    }
}

#endif
