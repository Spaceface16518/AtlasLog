#if DEBUG
import SwiftData
import SwiftUI

@MainActor
enum PreviewSupport {
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

#Preview("Main map") {
    TravelMapScreen().environment(AppDependencies()).modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Place editor — dark, large type") {
    PlaceEditorView(place: nil, seed: PlaceSeed(canonicalKey: nil, mapItemIdentifier: nil, kind: .city,
        name: "Cusco", subtitle: "Peru", coordinate: .init(longitude: -71.967, latitude: -13.523),
        countryCode: "PE", countryName: "Peru", administrativeArea: "Cusco", source: .bundledCatalog))
        .modelContainer(PreviewSupport.container())
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Photo review row") {
    @Previewable @State var candidate = PhotoImportCandidate(id: "cusco", canonicalKey: "cusco", proposedName: "Cusco",
        proposedCountry: "Peru", countryCode: "PE", coordinate: .init(longitude: -71.97, latitude: -13.52),
        photoCount: 12, earliestDate: .now.addingTimeInterval(-86_400 * 4), latestDate: .now,
        confidence: .high, matchingMethod: .bundledCity, assetIdentifiers: [], suggestedRegionIDs: [])
    List { ImportCandidateRow(candidate: $candidate, cityCatalog: CityCatalog(cities: [])) }
}

#Preview("Empty passport") {
    PassportPage(navigation: MapNavigationState(), nodes: []).modelContainer(PreviewSupport.container())
}

#Preview("Populated passport") {
    PassportPage(navigation: MapNavigationState(), nodes: []).modelContainer(PreviewSupport.container(populated: true))
}
#endif
