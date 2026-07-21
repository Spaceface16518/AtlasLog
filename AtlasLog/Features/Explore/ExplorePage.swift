import SwiftData
import SwiftUI

struct ExplorePage: View {
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query private var areaStatuses: [AreaStatus]
    @State private var searchState: PlaceSearchState
    @State private var filter: StatusFilter = .all
    @State private var newSeed: PlaceSeed?
    @State private var editingPlace: PlaceRecord?
    @State private var editingRegion: RegionNode?

    let mapLevel: RegionLevel
    let regionNodes: [RegionNode]
    let mapCenter: CoordinateValue
    let showPlaceOnMap: (PlaceRecord) -> Void
    let showRegionOnMap: (String, CoordinateValue?) -> Void

    init(mapLevel: RegionLevel, cityCatalog: CityCatalog, regionNodes: [RegionNode],
         mapCenter: CoordinateValue, showPlaceOnMap: @escaping (PlaceRecord) -> Void,
         showRegionOnMap: @escaping (String, CoordinateValue?) -> Void) {
        self.mapLevel = mapLevel
        self.regionNodes = regionNodes
        self.mapCenter = mapCenter
        self.showPlaceOnMap = showPlaceOnMap
        self.showRegionOnMap = showRegionOnMap
        _searchState = State(initialValue: PlaceSearchState(cityCatalog: cityCatalog))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PlaceSearchView(state: searchState) { newSeed = $0 }
                HStack {
                    Picker("Status", selection: $filter) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button { newSeed = manualSeed } label: { Label("Add", systemImage: "plus") }
                        .accessibilityIdentifier("add-place")
                }
                .font(.subheadline.weight(.medium))

                if searchState.query.isEmpty {
                    if mapLevel == .city { placeList }
                    else { areaList }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .sheet(item: $newSeed) { PlaceEditorView(place: nil, seed: $0) { saved in focus(saved) } }
        .sheet(item: $editingPlace) { PlaceEditorView(place: $0, seed: nil) { saved in focus(saved) } }
        .sheet(item: $editingRegion) { AreaDetailView(node: $0) }
    }

    @ViewBuilder private var placeList: some View {
        let filtered = places.filter(matchesFilter)
        if filtered.isEmpty {
            ContentUnavailableView("No places yet", systemImage: "mappin.slash",
                                   description: Text("Search a bundled city, use Apple Maps, or add a point manually."))
                .frame(minHeight: 180)
        } else {
            sectionHeader("Tracked places", count: filtered.count)
            ForEach(filtered) { place in
                Button { editingPlace = place; focus(place) } label: {
                    PlaceRow(title: place.name, subtitle: place.countryName, symbol: statusSymbol(place))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var areaList: some View {
        let nodes = regionNodes.filter { $0.level == mapLevel }
        if nodes.isEmpty {
            ContentUnavailableView("No bundled \(mapLevel.title.lowercased())", systemImage: "square.3.layers.3d",
                                   description: Text("This area remains usable once more catalog coverage is bundled."))
                .frame(minHeight: 180)
        } else {
            sectionHeader(mapLevel.title, count: nodes.count)
            ForEach(nodes) { node in
                Button {
                    showRegionOnMap(node.id, node.coordinate)
                    editingRegion = node
                } label: {
                    let status = areaStatuses.first { $0.areaID == node.id }
                    PlaceRow(title: node.name, subtitle: node.notes, symbol: status?.isVisited == true ? "checkmark.circle.fill" : "circle.dashed")
                }.buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack { Text(title).font(.headline); Spacer(); Text(count, format: .number).foregroundStyle(.secondary) }
    }
    private func matchesFilter(_ place: PlaceRecord) -> Bool {
        switch filter {
        case .all: true
        case .visited: place.isVisited
        case .meaningful: place.isMeaningfulVisit
        case .wantToVisit: place.isWantToVisit
        case .wantToReturn: place.isWantToReturn
        }
    }
    private func statusSymbol(_ place: PlaceRecord) -> String {
        if place.isWantToReturn { return "arrow.uturn.backward.circle.fill" }
        if place.isMeaningfulVisit { return "checkmark.circle.fill" }
        if place.isVisited { return "checkmark.circle" }
        if place.isWantToVisit { return "star.circle.fill" }
        return "mappin.circle"
    }
    private var manualSeed: PlaceSeed {
        PlaceSeed(canonicalKey: nil, mapItemIdentifier: nil, kind: .customPoint, name: "",
                  subtitle: nil, coordinate: mapCenter, countryCode: nil, countryName: nil,
                  administrativeArea: nil, source: .manual)
    }
    private func focus(_ place: PlaceRecord) {
        showPlaceOnMap(place)
    }
}

struct AreaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var areas: [AreaStatus]
    let node: RegionNode
    @State private var status = StatusDraft()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Level", value: node.level.title)
                    if let notes = node.notes { Text(notes).font(.footnote).foregroundStyle(.secondary) }
                    if node.geometryFeatureIDs.isEmpty {
                        Label("No bundled geometry yet; map focus uses the catalog centroid.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                Section("Travel status") {
                    Toggle("Visited", isOn: .init(get: { status.isVisited }, set: { status.setVisited($0) }))
                    if status.isVisited {
                        Toggle("Meaningful visit", isOn: .init(get: { status.isMeaningfulVisit }, set: { status.setMeaningful($0) }))
                        Toggle("Want to return", isOn: .init(get: { status.isWantToReturn }, set: { status.setWantToReturn($0) }))
                    } else {
                        Toggle("Want to visit", isOn: .init(get: { status.isWantToVisit }, set: { status.setWantToVisit($0) }))
                    }
                }
            }
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                if let area = areas.first(where: { $0.areaID == node.id }) {
                    status = .init(isVisited: area.isVisited, isWantToVisit: area.isWantToVisit,
                                   isMeaningfulVisit: area.isMeaningfulVisit, isWantToReturn: area.isWantToReturn)
                }
            }
            .alert("Couldn’t save", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
    private func save() {
        do { try TravelRecordService(context: context).setManualArea(node, status: status); dismiss() }
        catch { errorMessage = "The area status could not be saved." }
    }
}

#if DEBUG
#Preview("Explore — populated") {
    ExplorePage(
        mapLevel: .city,
        cityCatalog: CityCatalog(cities: []),
        regionNodes: PreviewSupport.nodes,
        mapCenter: .init(longitude: -71.967, latitude: -13.523),
        showPlaceOnMap: { _ in },
        showRegionOnMap: { _, _ in }
    )
        .modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Area detail") {
    AreaDetailView(node: PreviewSupport.nodes[1])
        .modelContainer(PreviewSupport.container(populated: true))
}
#endif
