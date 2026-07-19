import MapKit
import SwiftData
import SwiftUI
import OSLog

struct TravelMapScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query private var areaStatuses: [AreaStatus]
    @State private var navigation = MapNavigationState()
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 12, longitude: 0), span: .init(latitudeDelta: 145, longitudeDelta: 340)
    ))
    @State private var mapCenter = CoordinateValue(longitude: 0, latitude: 12)
    @State private var regionNodes: [RegionNode] = []
    @State private var geometries: [RegionGeometry] = []
    @State private var showDrawer = false
    @State private var drawerDetent: PresentationDetent = .height(104)
    @State private var editingPlace: PlaceRecord?
    @State private var showSettings = false
    @State private var resourceMessage: String?
    @AppStorage("mapStyle") private var mapStyleRaw = TravelMapStyle.standard.rawValue
    @AppStorage("mapLevel") private var mapLevelRaw = RegionLevel.city.rawValue

    private var mapStyle: TravelMapStyle {
        get { TravelMapStyle(rawValue: mapStyleRaw) ?? .standard }
        nonmutating set { mapStyleRaw = newValue.rawValue }
    }

    var body: some View {
        Map(position: $position, selection: $navigation.selectedPlaceID) {
            if navigation.level == .travelRegion || navigation.level == .country {
                ForEach(visibleGeometries) { geometry in
                    ForEach(Array(geometry.polygons.enumerated()), id: \.offset) { _, polygon in
                        if let exterior = polygon.first {
                            MapPolygon(coordinates: exterior.compactMap(clCoordinate))
                                .foregroundStyle(fill(for: geometry))
                                .stroke(stroke(for: geometry), style: StrokeStyle(lineWidth: geometry.regionID == navigation.selectedRegionID ? 3 : 1.2,
                                                                                  dash: geometry.boundaryKind == .administrative ? [] : [5, 4]))
                        }
                    }
                }
            }
            if navigation.level == .city {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude), anchor: .center) {
                        PlaceMarker(place: place, selected: navigation.selectedPlaceID == place.id)
                            .onTapGesture { navigation.selectedPlaceID = place.id; editingPlace = place }
                    }
                    .tag(place.id)
                }
            }
            if let selectedRegion = regionNodes.first(where: { $0.id == navigation.selectedRegionID }),
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
            NavigationStack {
                TravelDrawer(navigation: navigation, nodes: regionNodes, mapCenter: mapCenter)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gearshape") { showSettings = true } } }
            }
            .presentationDetents([.height(104), .medium, .large], selection: $drawerDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(24)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        .sheet(item: $editingPlace) { PlaceEditorView(place: $0, seed: nil) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Bundled data unavailable", isPresented: .init(get: { resourceMessage != nil }, set: { if !$0 { resourceMessage = nil } })) {
            Button("OK", role: .cancel) { resourceMessage = nil }
        } message: { Text(resourceMessage ?? "") }
        .task { await loadResources() }
        .onAppear {
            navigation.level = RegionLevel(rawValue: mapLevelRaw) ?? .city
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") || ProcessInfo.processInfo.arguments.contains("--ui-testing-expanded") {
                drawerDetent = .large
            }
            showDrawer = true
        }
        .onChange(of: navigation.level) { _, level in mapLevelRaw = level.rawValue }
        .onChange(of: navigation.focusCoordinate) { _, coordinate in focus(coordinate) }
    }

    private var mapToolbar: some View {
        HStack(spacing: 10) {
            MapLevelMenu(level: $navigation.level)
            Spacer()
            Button {
                mapStyle = mapStyle == .standard ? .satellite : .standard
            } label: {
                Image(systemName: mapStyle == .standard ? "globe.americas.fill" : "map.fill")
                    .frame(width: 36, height: 36).background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(mapStyle == .standard ? "Switch to satellite map" : "Switch to standard map")
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
        return geometry.regionID == navigation.selectedRegionID ? Color.accentColor : Color.blue.opacity(geometry.membership == .core ? 0.7 : 0.35)
    }
    private var visibleGeometries: [RegionGeometry] {
        if navigation.level == .country { return geometries.filter { $0.regionID.hasPrefix("country:") } }
        return geometries.filter { $0.regionID.hasPrefix("travel:") }
    }
    private func focus(_ coordinate: CoordinateValue?) {
        guard let coordinate else { return }
        let span: MKCoordinateSpan = navigation.level == .city ? .init(latitudeDelta: 2, longitudeDelta: 2) : .init(latitudeDelta: 16, longitudeDelta: 16)
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
