import SwiftData
import SwiftUI

struct TravelDrawer: View {
    @Query private var places: [PlaceRecord]
    @Query private var areas: [AreaStatus]
    @Environment(\.appDependencies) private var dependencies
    @Binding var mapLevel: RegionLevel
    @State private var selectedPage = DrawerPage.explore
    let nodes: [RegionNode]
    let mapCenter: CoordinateValue
    let showPlaceOnMap: (PlaceRecord) -> Void
    let showRegionOnMap: (String, CoordinateValue?) -> Void

    private var summary: PassportStatistics {
        PassportStatisticsService().calculate(places: places, areas: areas)
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            Tab("Explore", systemImage: "map", value: DrawerPage.explore) {
                VStack(spacing: 10) {
                    drawerHeader
                    ExplorePage(
                        mapLevel: mapLevel,
                        cityCatalog: dependencies.cityCatalog,
                        regionNodes: nodes,
                        mapCenter: mapCenter,
                        showPlaceOnMap: showPlaceOnMap,
                        showRegionOnMap: showRegionOnMap
                    )
                }
            }

            Tab(
                "Passport",
                systemImage: "book.closed",
                value: DrawerPage.passport
            ) {
                VStack(spacing: 10) {
                    drawerHeader
                    PassportPage(
                        nodes: nodes,
                        showPlaceOnMap: showPlaceFromPassport,
                        showAreaOnMap: showAreaFromPassport
                    )
                }
            }

            Tab(
                "Import",
                systemImage: "photo.on.rectangle.angled",
                value: DrawerPage.photoImport
            ) {
                NavigationStack {
                    VStack(spacing: 10) {
                        drawerHeader
                        PhotoImportView()
                    }
                }
            }
        }
    }

    private var drawerHeader: some View {
        let statistics = summary
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedPage.rawValue).font(.headline)
                Text(
                    "\(statistics.countriesVisited) \(statistics.countriesVisited == 1 ? "country" : "countries") • \(statistics.citiesVisited) \(statistics.citiesVisited == 1 ? "city" : "cities")"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MapLevelMenu(level: $mapLevel)
        }
        .padding()
    }

    private func showPlaceFromPassport(_ place: PlaceRecord) {
        selectedPage = .explore
        mapLevel = .city
        showPlaceOnMap(place)
    }

    private func showAreaFromPassport(_ area: AreaStatus) {
        selectedPage = .explore
        mapLevel = area.level
        showRegionOnMap(
            area.areaID,
            nodes.first { $0.id == area.areaID }?.coordinate
        )
    }
}

#if DEBUG
    #Preview("Travel drawer") {
        @Previewable @State var mapLevel = RegionLevel.city
        TravelDrawer(
            mapLevel: $mapLevel,
            nodes: PreviewSupport.nodes,
            mapCenter: .init(longitude: -71.967, latitude: -13.523),
            showPlaceOnMap: { _ in },
            showRegionOnMap: { _, _ in }
        )
        .environment(\.appDependencies, AppDependencies())
        .modelContainer(PreviewSupport.container(populated: true))
    }
#endif
