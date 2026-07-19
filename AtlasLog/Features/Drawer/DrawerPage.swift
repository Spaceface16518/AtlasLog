import Foundation

enum DrawerPage: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case passport = "Passport"
    case photoImport = "Import"
    var id: String { rawValue }
}

@MainActor
@Observable
final class MapNavigationState {
    var drawerPage: DrawerPage = .explore
    var level: RegionLevel = .city
    var selectedPlaceID: UUID?
    var selectedRegionID: String?
    var focusCoordinate: CoordinateValue?
}
