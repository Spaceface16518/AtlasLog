import Foundation

struct PassportStatistics: Equatable, Sendable {
    var countriesVisited = 0
    var meaningfulCountries = 0
    var citiesVisited = 0
    var travelRegionsVisited = 0
    var continentsVisited = 0
    var wantToVisit = 0
    var wantToReturn = 0

    static let empty = PassportStatistics()
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All tracked"
    case visited = "Visited"
    case meaningful = "Meaningful"
    case wantToVisit = "Want to visit"
    case wantToReturn = "Want to return"
    var id: String { rawValue }
}
