import SwiftData
import SwiftUI

struct PassportPage: View {
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query private var areas: [AreaStatus]
    let nodes: [RegionNode]
    let showPlaceOnMap: (PlaceRecord) -> Void
    let showAreaOnMap: (AreaStatus) -> Void

    private var statistics: PassportStatistics { PassportStatisticsService().calculate(places: places, areas: areas) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    PassportMetricCard(value: statistics.countriesVisited, title: "Countries", symbol: "globe.americas")
                    PassportMetricCard(value: statistics.meaningfulCountries, title: "Meaningful", symbol: "checkmark.seal")
                    PassportMetricCard(value: statistics.citiesVisited, title: "Cities", symbol: "building.2")
                    PassportMetricCard(value: statistics.travelRegionsVisited, title: "Regions", symbol: "square.3.layers.3d")
                    PassportMetricCard(value: statistics.continentsVisited, title: "Continents", symbol: "globe")
                    PassportMetricCard(value: statistics.wantToVisit, title: "Wishlist", symbol: "star")
                    PassportMetricCard(value: statistics.wantToReturn, title: "Return", symbol: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("passport-metrics")

                if statistics == .empty {
                    ContentUnavailableView("Your passport is ready", systemImage: "book.closed",
                                           description: Text("Mark a city visited to begin your private travel summary."))
                        .frame(minHeight: 180)
                } else {
                    ForEach([RegionLevel.continent, .subcontinent, .macroRegion, .travelRegion, .country], id: \.self) { level in
                        areaSection(level)
                    }
                    placeSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private func areaSection(_ level: RegionLevel) -> some View {
        let tracked = areas.filter { $0.level == level && ($0.isVisited || $0.isWantToVisit || $0.isWantToReturn) }
        return Group {
            if !tracked.isEmpty {
                Text(level.title).font(.headline)
                ForEach(tracked) { area in
                    Button { select(area) } label: {
                        PlaceRow(title: name(for: area), subtitle: area.isMeaningfulVisit ? "Meaningful" : "Limited or wishlist",
                                 symbol: area.isMeaningfulVisit ? "checkmark.seal.fill" : "checkmark.circle")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var placeSection: some View {
        let tracked = places.filter { $0.isVisited || $0.isWantToVisit || $0.isWantToReturn }
        if !tracked.isEmpty {
            Text("Cities and places").font(.headline)
            ForEach(tracked) { place in
                Button { showPlaceOnMap(place) } label: {
                    PlaceRow(title: place.name, subtitle: place.countryName,
                             symbol: place.isMeaningfulVisit ? "checkmark.circle.fill" : (place.isWantToVisit ? "star.circle" : "checkmark.circle"))
                }.buttonStyle(.plain)
            }
        }
    }

    private func name(for area: AreaStatus) -> String {
        if let node = nodes.first(where: { $0.id == area.areaID }) { return node.name }
        if area.areaID.hasPrefix("country:") { return Locale.current.localizedString(forRegionCode: String(area.areaID.dropFirst(8))) ?? String(area.areaID.dropFirst(8)) }
        return area.areaID
    }
    private func select(_ area: AreaStatus) {
        showAreaOnMap(area)
    }
}

struct PassportMetricCard: View {
    let value: Int
    let title: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value, format: .number).font(.title2.bold()).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted())
        .accessibilityIdentifier("passport-\(title.lowercased())")
    }
}

#if DEBUG
#Preview("Empty passport") {
    PassportPage(nodes: [], showPlaceOnMap: { _ in }, showAreaOnMap: { _ in })
        .modelContainer(PreviewSupport.container())
}

#Preview("Populated passport") {
    PassportPage(nodes: PreviewSupport.nodes, showPlaceOnMap: { _ in }, showAreaOnMap: { _ in })
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Passport metric card") {
    PassportMetricCard(value: 12, title: "Countries", symbol: "globe.americas")
        .frame(width: 140)
        .padding()
}
#endif
