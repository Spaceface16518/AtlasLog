import SwiftData
import SwiftUI

struct TravelDrawer: View {
    @Query private var places: [PlaceRecord]
    @Query private var areas: [AreaStatus]
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var navigation: MapNavigationState
    let nodes: [RegionNode]
    let mapCenter: CoordinateValue

    private var summary: PassportStatistics { PassportStatisticsService().calculate(places: places, areas: areas) }

    var body: some View {
        TabView(selection: $navigation.drawerPage) {
            Tab("Explore", systemImage: "map", value: DrawerPage.explore) {
                VStack(spacing: 10) {
                    drawerHeader
                    ExplorePage(
                        navigation: navigation,
                        cityCatalog: dependencies.cityCatalog,
                        regionNodes: nodes,
                        mapCenter: mapCenter
                    )
                }
            }

            Tab("Passport", systemImage: "book.closed", value: DrawerPage.passport) {
                VStack(spacing: 10) {
                    drawerHeader
                    PassportPage(navigation: navigation, nodes: nodes)
                }
            }
        }
        .padding(.top, 6)
    }

    private var drawerHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.drawerPage.rawValue).font(.headline)
                Text("\(summary.countriesVisited) countries • \(summary.citiesVisited) cities")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MapLevelMenu(level: $navigation.level)
        }
        .padding(.horizontal)
    }
}
