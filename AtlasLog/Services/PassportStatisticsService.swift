import Foundation

struct PassportStatisticsService: Sendable {
    func calculate(places: [PlaceRecord], areas: [AreaStatus]) -> PassportStatistics {
        let visitedPlaces = places.filter(\.isVisited)
        let countries = areas.filter { $0.level == .country && $0.isVisited }
        return PassportStatistics(
            countriesVisited: countries.count,
            meaningfulCountries: countries.filter(\.isMeaningfulVisit).count,
            citiesVisited: visitedPlaces.filter { $0.kind == .city }.count,
            travelRegionsVisited: areas.filter { $0.level == .travelRegion && $0.isVisited }.count,
            continentsVisited: areas.filter { $0.level == .continent && $0.isVisited }.count,
            wantToVisit: places.filter(\.isWantToVisit).count + areas.filter(\.isWantToVisit).count,
            wantToReturn: places.filter(\.isWantToReturn).count + areas.filter(\.isWantToReturn).count
        )
    }
}
