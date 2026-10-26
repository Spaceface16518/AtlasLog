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
    case all = "All"
    case visited = "Visited"
    case meaningful = "Meaningful"
    case wantToVisit = "Want to visit"
    case wantToReturn = "Want to return"
    var id: String { rawValue }

    func matches(_ status: StatusDraft?) -> Bool {
        switch self {
        case .all: true
        case .visited: status?.isVisited == true
        case .meaningful: status?.isMeaningfulVisit == true
        case .wantToVisit: status?.isWantToVisit == true
        case .wantToReturn: status?.isWantToReturn == true
        }
    }
}
