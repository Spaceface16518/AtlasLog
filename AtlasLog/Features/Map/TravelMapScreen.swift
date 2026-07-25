import MapKit
import SwiftData
import SwiftUI
import OSLog

struct TravelMapScreen: View {
    @Environment(\.appDependencies) private var dependencies
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query private var areaStatuses: [AreaStatus]
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 12, longitude: 0), span: .init(latitudeDelta: 145, longitudeDelta: 340)
    ))
    @State private var mapCenter = CoordinateValue(longitude: 0, latitude: 12)
    @State private var regionNodes: [RegionNode] = []
    @State private var geometries: [RegionGeometry] = []
    @State private var selectedPlaceID: UUID?
    @State private var selectedRegionID: String?
    @State private var showDrawer = true
    @State private var drawerDetent: PresentationDetent = .medium
    @State private var editingPlace: PlaceRecord?
    @State private var showSettings = false
    @State private var resourceMessage: String?
    @AppStorage("mapStyle") private var mapStyle = TravelMapStyle.standard
    @AppStorage("mapLevel") private var mapLevel = RegionLevel.city

    var body: some View {
        Map(position: $position, selection: $selectedPlaceID) {
            if [.travelRegion, .country, .subcontinent, .continent].contains(
                mapLevel
            ) {
                ForEach(visibleGeometries) { geometry in
                    ForEach(Array(geometry.polygons.enumerated()), id: \.offset) { _, polygon in
                        if let exterior = polygon.first {
                            MapPolygon(coordinates: exterior.compactMap(clCoordinate))
                                .foregroundStyle(fill(for: geometry))
                                .stroke(stroke(for: geometry), style: StrokeStyle(lineWidth: geometry.regionID == selectedRegionID ? 3 : 1.2,
                                                                                  dash: geometry.boundaryKind == .administrative ? [] : [5, 4]))
                        }
                    }
                }
            }
            if mapLevel == .city {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude), anchor: .center) {
                        PlaceMarker(place: place, selected: selectedPlaceID == place.id)
                            .onTapGesture { selectedPlaceID = place.id; editingPlace = place }
                    }
                    .tag(place.id)
                }
            }
            if let selectedRegion = regionNodes.first(where: { $0.id == selectedRegionID }),
               let lat = selectedRegion.centroidLatitude, let lon = selectedRegion.centroidLongitude {
                Annotation(selectedRegion.name, coordinate: .init(latitude: lat, longitude: lon)) {
                    Label(selectedRegion.name, systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.semibold)).padding(8).background(.regularMaterial, in: Capsule())
                }
            }
        }
        .mapStyle(mapStyle == .standard ? .standard(elevation: .flat) : .imagery(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            mapCenter = .init(longitude: context.region.center.longitude, latitude: context.region.center.latitude)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { mapToolbar.padding(.top, 10).padding(.horizontal) }
        .sheet(isPresented: $showDrawer) {
            TravelDrawer(
                mapLevel: $mapLevel,
                nodes: regionNodes,
                mapCenter: mapCenter,
                showPlaceOnMap: showPlaceOnMap,
                showRegionOnMap: showRegionOnMap
            )
                .sheet(isPresented: $showSettings) { SettingsView() }
                .presentationDetents([.medium, .large], selection: $drawerDetent)
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .sheet(item: $editingPlace) { PlaceEditorView(place: $0, seed: nil) }
        .alert("Bundled data unavailable", isPresented: .init(get: { resourceMessage != nil }, set: { if !$0 { resourceMessage = nil } })) {
            Button("OK", role: .cancel) { resourceMessage = nil }
        } message: { Text(resourceMessage ?? "") }
        .task { await loadResources() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") || ProcessInfo.processInfo.arguments.contains("--ui-testing-expanded") {
                drawerDetent = .large
            }
        }
    }

    private var mapToolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            MapLevelMenu(level: $mapLevel)
            Spacer()
            VStack(spacing: 10) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("map-settings")

                Button {
                    mapStyle = mapStyle == .standard ? .satellite : .standard
                } label: {
                    Image(systemName: mapStyle == .standard ? "globe.americas.fill" : "map.fill")
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel(mapStyle == .standard ? "Switch to satellite map" : "Switch to standard map")
            }
        }
    }

    private func clCoordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else { return nil }
        return .init(latitude: pair[1], longitude: pair[0])
    }
    private func fill(for geometry: RegionGeometry) -> Color {
        if let status = areaStatuses.first(where: { $0.areaID == geometry.regionID }) {
            if status.isMeaningfulVisit { return Color.accentColor.opacity(0.30) }
            if status.isVisited { return Color.secondary.opacity(0.20) }
            if status.isWantToVisit { return Color.orange.opacity(0.10) }
        }
        switch geometry.membership {
        case .core: return Color.blue.opacity(0.16)
        case .transition: return Color.blue.opacity(0.07)
        case .associated: return Color.clear
        }
    }
    private func stroke(for geometry: RegionGeometry) -> Color {
        if areaStatuses.first(where: { $0.areaID == geometry.regionID })?.isWantToVisit == true { return .orange }
        return geometry.regionID == selectedRegionID ? Color.accentColor : Color.blue.opacity(geometry.membership == .core ? 0.7 : 0.35)
    }
    private var visibleGeometries: [RegionGeometry] {
        let prefix =
            switch mapLevel {
            case .country: "country:"
            case .travelRegion: "travel:"
            case .subcontinent: "subcontinent:"
            case .continent: "continent:"
            case .city, .macroRegion: ""
            }
        return prefix.isEmpty
            ? [] : geometries.filter { $0.regionID.hasPrefix(prefix) }
    }

    private func showPlaceOnMap(_ place: PlaceRecord) {
        selectedPlaceID = place.id
        selectedRegionID = nil
        focus(on: .init(longitude: place.longitude, latitude: place.latitude))
    }

    private func showRegionOnMap(_ regionID: String, coordinate: CoordinateValue?) {
        selectedPlaceID = nil
        selectedRegionID = regionID
        if let coordinate { focus(on: coordinate) }
    }

    private func focus(on coordinate: CoordinateValue) {
        let span: MKCoordinateSpan = mapLevel == .city ? .init(latitudeDelta: 2, longitudeDelta: 2) : .init(latitudeDelta: 16, longitudeDelta: 16)
        withAnimation(.easeInOut(duration: 0.45)) {
            position = .region(.init(center: coordinate.clCoordinate, span: span))
        }
    }
    private func loadResources() async {
        do {
            async let loadedNodes = dependencies.regionCatalog.nodes()
            async let loadedGeometry = dependencies.regionCatalog.geometries()
            regionNodes = try await loadedNodes
            geometries = try await loadedGeometry
        } catch {
            AppLogger.catalog.error("Resource load failed: \(error.localizedDescription, privacy: .public)")
            resourceMessage = "Some bundled regions could not be loaded. Your saved places remain available."
        }
    }
}

#if DEBUG
#Preview("Main map") {
    TravelMapScreen()
        .environment(\.appDependencies, AppDependencies())
        .modelContainer(PreviewSupport.container(populated: true))
}
#endif
