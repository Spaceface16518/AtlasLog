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
    @Previewable @State var candidate = PreviewSupport.candidate
    List { ImportCandidateRow(candidate: $candidate, cityCatalog: CityCatalog(cities: [])) }
}

#Preview("Empty passport") {
    PassportPage(navigation: MapNavigationState(), nodes: []).modelContainer(PreviewSupport.container())
}

#Preview("Populated passport") {
    PassportPage(navigation: MapNavigationState(), nodes: PreviewSupport.nodes)
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Map level menu") {
    @Previewable @State var level = RegionLevel.travelRegion
    MapLevelMenu(level: $level).padding()
}

#Preview("Place marker states") {
    HStack(spacing: 24) {
        PlaceMarker(place: PreviewSupport.place, selected: false)
        PlaceMarker(place: PreviewSupport.place, selected: true)
    }
    .padding()
}

#Preview("Travel drawer") {
    TravelDrawer(navigation: MapNavigationState(), nodes: PreviewSupport.nodes,
                 mapCenter: .init(longitude: -71.967, latitude: -13.523))
        .environment(AppDependencies())
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Explore — populated") {
    ExplorePage(navigation: MapNavigationState(), cityCatalog: CityCatalog(cities: []),
                regionNodes: PreviewSupport.nodes,
                mapCenter: .init(longitude: -71.967, latitude: -13.523))
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Area detail") {
    AreaDetailView(node: PreviewSupport.nodes[1])
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Place search") {
    PlaceSearchPreview()
}

#Preview("Place row") {
    VStack(spacing: 12) {
        PlaceRow(title: "Cusco", subtitle: "Peru", symbol: "building.2")
        PlaceRow(title: "Machu Picchu", subtitle: "Resolving with Apple Maps", symbol: "mappin.and.ellipse",
                 trailingProgress: true)
    }
    .padding()
}

#Preview("Photo import — empty") {
    NavigationStack { PhotoImportView() }
        .environment(AppDependencies())
        .modelContainer(PreviewSupport.container())
}

#Preview("Import location search") {
    @Previewable @State var candidate = PreviewSupport.candidate
    NavigationStack {
        ImportLocationSearchView(candidate: $candidate, cityCatalog: CityCatalog(cities: []))
    }
}

#Preview("Passport metric card") {
    PassportMetricCard(value: 12, title: "Countries", symbol: "globe.americas")
        .frame(width: 140)
        .padding()
}

#Preview("Settings") {
    SettingsView().modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Acknowledgements") {
    NavigationStack { AcknowledgementsView() }
}

@MainActor
private struct PlaceSearchPreview: View {
    @State private var state: PlaceSearchState

    init() {
        let cities = [
            CityRecord(id: "3941584", name: "Cusco", normalizedName: "cusco", alternateNames: [],
                       latitude: -13.5226, longitude: -71.9673, countryCode: "PE", countryName: "Peru",
                       administrativeArea: "Cusco", population: 428_450)
        ]
        let state = PlaceSearchState(cityCatalog: CityCatalog(cities: cities))
        state.query = "Cusco"
        _state = State(initialValue: state)
    }

    var body: some View {
        ScrollView { PlaceSearchView(state: state) { _ in }.padding() }
    }
}
#endif
