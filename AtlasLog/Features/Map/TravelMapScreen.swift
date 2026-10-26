import MapKit
import OSLog
import SwiftData
import SwiftUI

struct TravelMapScreen: View {
    @Environment(\.appDependencies) private var dependencies
    @Query(sort: \PlaceRecord.name) private var places: [PlaceRecord]
    @Query private var areaStatuses: [AreaStatus]
    @State private var position: MapCameraPosition = .region(
        .init(
            center: .init(latitude: 12, longitude: 0),
            span: .init(latitudeDelta: 145, longitudeDelta: 340)
        )
    )
    @State private var mapCenter = CoordinateValue(longitude: 0, latitude: 12)
    @State private var regionNodes: [RegionNode] = []
    @State private var geometries: [RegionGeometry] = []
    @State private var selectedPlaceID: UUID?
    @State private var selectedRegionID: String?
    @State private var selectedRegionCoordinate: CoordinateValue?
    // Repeated taps should reveal the row even when the region has not changed.
    @State private var regionSelectionRequest = UUID()
    @State private var selectedDrawerPage = DrawerPage.explore
    @State private var showDrawer = true
    @State private var drawerDetent: PresentationDetent = .medium
    @State private var editingPlace: PlaceRecord?
    @State private var showSettings = false
    @State private var resourceMessage: String?
    @AppStorage("mapStyle") private var mapStyle = TravelMapStyle.standard
    @AppStorage("mapLevel") private var mapLevel = RegionLevel.city

    var body: some View {
        MapReader { proxy in
            Map(position: $position, selection: $selectedPlaceID) {
                if [.travelRegion, .macroRegion, .country, .subcontinent, .continent].contains(
                    mapLevel
                ) {
                    ForEach(visibleGeometries) { geometry in
                        ForEach(Array(geometry.polygons.enumerated()), id: \.offset)
                        { _, polygon in
                            if let exterior = polygon.first {
                                let coordinates = exterior.compactMap(clCoordinate)
                                MapPolygon(MKPolygon(
                                    coordinates: coordinates,
                                    count: coordinates.count,
                                    interiorPolygons: polygon.dropFirst().map { ring in
                                        let coordinates = ring.compactMap(clCoordinate)
                                        return MKPolygon(coordinates: coordinates, count: coordinates.count)
                                    }
                                ))
                                .foregroundStyle(fill(for: geometry))
                                .stroke(
                                    stroke(for: geometry),
                                    style: StrokeStyle(
                                        lineWidth: geometry.regionID
                                            == selectedRegionID ? 3 : 1.2,
                                        dash: geometry.boundaryKind
                                            == .administrative ? [] : [5, 4]
                                    )
                                )
                            }
                        }
                    }
                }
                if mapLevel == .city {
                    ForEach(places) { place in
                        Annotation(
                            place.name,
                            coordinate: .init(
                                latitude: place.latitude,
                                longitude: place.longitude
                            ),
                            anchor: .center
                        ) {
                            PlaceMarker(
                                place: place,
                                selected: selectedPlaceID == place.id
                            )
                            .onTapGesture {
                                selectedPlaceID = place.id
                                editingPlace = place
                            }
                        }
                        .tag(place.id)
                    }
                }
                if let selectedRegion = regionNodes.first(where: {
                    $0.id == selectedRegionID && $0.level == mapLevel
                }),
                    let coordinate = selectedRegionCoordinate ?? selectedRegion.coordinate
                {
                    Annotation(
                        selectedRegion.name,
                        coordinate: coordinate.clCoordinate
                    ) {
                        Label(
                            selectedRegion.name,
                            systemImage: "square.3.layers.3d"
                        )
                        .font(.caption.weight(.semibold)).padding(8).background(
                            .regularMaterial,
                            in: Capsule()
                        )
                        .accessibilityIdentifier("selected-region-label")
                    }
                }
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    guard mapLevel != .city,
                          let coordinate = proxy.convert(event.location, from: .local) else { return }
                    selectRegion(at: .init(longitude: coordinate.longitude, latitude: coordinate.latitude))
                },
                isEnabled: mapLevel != .city
            )
        }
        .mapStyle(
            mapStyle == .standard
                ? .standard(elevation: .flat) : .imagery(elevation: .realistic)
        )
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            mapCenter = .init(
                longitude: context.region.center.longitude,
                latitude: context.region.center.latitude
            )
        }
        .onChange(of: mapLevel) { _, level in
            // Passport navigation may select a new region in the same update.
            // Keep that selection only when it belongs to the destination layer.
            if !regionNodes.contains(where: {
                $0.id == selectedRegionID && $0.level == level
            }) {
                selectedRegionID = nil
                selectedRegionCoordinate = nil
            }
            if level != .city { selectedPlaceID = nil }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            mapToolbar.padding(.top, 10).padding(.horizontal)
        }
        .sheet(isPresented: $showDrawer) {
            TravelDrawer(
                mapLevel: $mapLevel,
                selectedPage: $selectedDrawerPage,
                selectedRegionID: selectedRegionID,
                regionSelectionRequest: regionSelectionRequest,
                nodes: regionNodes,
                mapCenter: mapCenter,
                showPlaceOnMap: showPlaceOnMap,
                showRegionOnMap: showRegionOnMap
            )
            .sheet(isPresented: $showSettings) { SettingsView() }
            .presentationDetents(
                [.fraction(1 / 3), .medium, .large],
                selection: $drawerDetent
            )
            .presentationDragIndicator(.hidden)
            .presentationBackground(.regularMaterial)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        .sheet(item: $editingPlace) { PlaceEditorView(place: $0, seed: nil) }
        .alert(
            "Bundled data unavailable",
            isPresented: .init(
                get: { resourceMessage != nil },
                set: { if !$0 { resourceMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { resourceMessage = nil }
        } message: {
            Text(resourceMessage ?? "")
        }
        .task { await loadResources() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
                || ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-expanded"
                )
            {
                drawerDetent = .large
            }
        }
    }

    private var mapToolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            MapLevelMenu(level: $mapLevel)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("map-settings")

                Button {
                    mapStyle = mapStyle == .standard ? .satellite : .standard
                } label: {
                    Image(
                        systemName: mapStyle == .standard
                            ? "globe.americas.fill" : "map.fill"
                    )
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel(
                    mapStyle == .standard
                        ? "Switch to satellite map" : "Switch to standard map"
                )
            }
        }
    }

    private func clCoordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else { return nil }
        return .init(latitude: pair[1], longitude: pair[0])
    }
    private func fill(for geometry: RegionGeometry) -> Color {
        if let status = areaStatuses.first(where: {
            $0.areaID == geometry.regionID
        }) {
            if status.isMeaningfulVisit {
                return Color.accentColor.opacity(0.30)
            }
            if status.isVisited { return Color.secondary.opacity(0.20) }
        }
        return geometry.regionID == selectedRegionID ? Color.accentColor.opacity(0.15) : Color.clear
    }
    private func stroke(for geometry: RegionGeometry) -> Color {
        return geometry.regionID == selectedRegionID
            ? Color.accentColor
            : Color.blue.opacity(geometry.membership == .core ? 0.7 : 0.35)
    }
    private var visibleGeometries: [RegionGeometry] {
        let prefix =
            switch mapLevel {
            case .country: "country:"
            case .travelRegion: "travel:"
            case .macroRegion: "macro:"
            case .subcontinent: "subcontinent:"
            case .continent: "continent:"
            case .city: ""
            }
        return prefix.isEmpty
            ? []
            : geometries.filter { $0.regionID.hasPrefix(prefix) }
    }

    private func selectRegion(at coordinate: CoordinateValue) {
        selectedRegionID = RegionMapSelection().regionID(at: coordinate, geometries: visibleGeometries)
        selectedRegionCoordinate = selectedRegionID == nil ? nil : coordinate
        guard selectedRegionID != nil else { return }
        regionSelectionRequest = UUID()
        selectedPlaceID = nil
        selectedDrawerPage = .explore
        drawerDetent = .medium
    }

    private func showPlaceOnMap(_ place: PlaceRecord) {
        selectedPlaceID = place.id
        selectedRegionID = nil
        selectedRegionCoordinate = nil
        focus(on: .init(longitude: place.longitude, latitude: place.latitude))
    }

    private func showRegionOnMap(
        _ regionID: String,
        coordinate: CoordinateValue?
    ) {
        selectedPlaceID = nil
        selectedRegionID = regionID
        selectedRegionCoordinate = nil
        regionSelectionRequest = UUID()
        let boxes = geometries.filter { $0.regionID == regionID }.compactMap(\.boundingBox)
        if let west = boxes.map(\.minLongitude).min(), let east = boxes.map(\.maxLongitude).max(),
            let south = boxes.map(\.minLatitude).min(), let north = boxes.map(\.maxLatitude).max(),
            east - west < 180 {
            // Fit smaller regions such as Washington instead of using the
            // same 16-degree span as an entire continent.
            withAnimation(.easeInOut(duration: 0.45)) {
                position = .region(.init(
                    center: .init(latitude: (south + north) / 2, longitude: (west + east) / 2),
                    span: .init(latitudeDelta: min(160, max(0.3, (north - south) * 1.5)),
                                longitudeDelta: min(340, max(0.3, (east - west) * 1.5)))
                ))
            }
            return
        }
        if let coordinate { focus(on: coordinate) }
    }

    private func focus(on coordinate: CoordinateValue) {
        let span: MKCoordinateSpan =
            mapLevel == .city
            ? .init(latitudeDelta: 2, longitudeDelta: 2)
            : .init(latitudeDelta: 16, longitudeDelta: 16)
        withAnimation(.easeInOut(duration: 0.45)) {
            position = .region(
                .init(center: coordinate.clCoordinate, span: span)
            )
        }
    }
    private func loadResources() async {
        do {
            async let loadedNodes = dependencies.regionCatalog.nodes()
            async let loadedGeometry = dependencies.regionCatalog.geometries()
            regionNodes = try await loadedNodes
            geometries = try await loadedGeometry
        } catch {
            AppLogger.catalog.error(
                "Resource load failed: \(error.localizedDescription, privacy: .public)"
            )
            resourceMessage =
                "Some bundled regions could not be loaded. Your saved places remain available."
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
