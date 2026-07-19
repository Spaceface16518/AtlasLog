import Foundation

enum TravelStatus: String, Codable, CaseIterable, Sendable {
    case untracked
    case visited
    case meaningful
    case wantToVisit
    case wantToReturn
}

enum VisitSource: String, Codable, CaseIterable, Sendable {
    case manual
    case bundledCatalog
    case appleMaps
    case photoImport
    case derived
    case sample
}

enum PlaceKind: String, Codable, CaseIterable, Sendable {
    case city
    case landmark
    case customPoint

    var title: String {
        switch self {
        case .city: "City"
        case .landmark: "Landmark"
        case .customPoint: "Custom point"
        }
    }
}

struct StatusDraft: Equatable, Sendable {
    var isVisited = false
    var isWantToVisit = false
    var isMeaningfulVisit = false
    var isWantToReturn = false

    mutating func setVisited(_ value: Bool) {
        isVisited = value
        if value { isWantToVisit = false }
        else {
            isMeaningfulVisit = false
            isWantToReturn = false
        }
    }

    mutating func setMeaningful(_ value: Bool) {
        isMeaningfulVisit = value
        if value { setVisited(true) }
    }

    mutating func setWantToReturn(_ value: Bool) {
        isWantToReturn = value
        if value { setVisited(true) }
    }

    mutating func setWantToVisit(_ value: Bool) {
        isWantToVisit = value
        if value { setVisited(false); isWantToVisit = true }
    }
}
