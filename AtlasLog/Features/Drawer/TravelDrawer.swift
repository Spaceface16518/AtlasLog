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
        VStack(spacing: 10) {
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
            Picker("Page", selection: $navigation.drawerPage) {
                ForEach(DrawerPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if navigation.drawerPage == .explore {
                ExplorePage(navigation: navigation, cityCatalog: dependencies.cityCatalog, regionNodes: nodes, mapCenter: mapCenter)
            } else {
                PassportPage(navigation: navigation, nodes: nodes)
            }
        }
        .padding(.top, 6)
    }
}
