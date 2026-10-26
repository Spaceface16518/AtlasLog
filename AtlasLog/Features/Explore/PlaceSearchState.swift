import Foundation
import MapKit
import Observation
import OSLog

struct AppleMapsSuggestion: Identifiable {
    let id = UUID()
    let completion: MKLocalSearchCompletion
    var title: String { completion.title }
    var subtitle: String { completion.subtitle }
}

struct PlaceSeed: Identifiable {
    let id = UUID()
    var canonicalKey: String?
    var mapItemIdentifier: String?
    var kind: PlaceKind
    var name: String
    var subtitle: String?
    var coordinate: CoordinateValue
    var countryCode: String?
    var countryName: String?
    var administrativeArea: String?
    var source: VisitSource

    init(canonicalKey: String?, mapItemIdentifier: String?, kind: PlaceKind, name: String,
         subtitle: String?, coordinate: CoordinateValue, countryCode: String?, countryName: String?,
         administrativeArea: String?, source: VisitSource) {
        self.canonicalKey = canonicalKey
        self.mapItemIdentifier = mapItemIdentifier
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.administrativeArea = administrativeArea
        self.source = source
    }

    init(city: CityRecord) {
        canonicalKey = city.canonicalKey
        mapItemIdentifier = nil
        kind = .city
        name = city.name
        subtitle = city.countryName
        coordinate = .init(longitude: city.longitude, latitude: city.latitude)
        countryCode = city.countryCode
        countryName = city.countryName
        administrativeArea = city.administrativeArea
        source = .bundledCatalog
    }

    init(mapItem: MKMapItem) {
        canonicalKey = nil
        mapItemIdentifier = nil
        kind = mapItem.pointOfInterestCategory == nil ? .city : .landmark
        name = mapItem.name ?? "Saved place"
        subtitle = mapItem.address?.shortAddress
        coordinate = .init(longitude: mapItem.location.coordinate.longitude, latitude: mapItem.location.coordinate.latitude)
        countryCode = mapItem.addressRepresentations?.region?.identifier
        countryName = mapItem.addressRepresentations?.regionName
        administrativeArea = nil
        source = .appleMaps
    }
}

@MainActor
@Observable
final class PlaceSearchState: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" { didSet { queryChanged() } }
    private(set) var localResults: [CityRecord] = []
    private(set) var appleSuggestions: [AppleMapsSuggestion] = []
    private(set) var isSearching = false
    private(set) var message: String?

    private let cityCatalog: CityCatalog
    private let completer = MKLocalSearchCompleter()
    private var localTask: Task<Void, Never>?

    init(cityCatalog: CityCatalog) {
        self.cityCatalog = cityCatalog
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appleSuggestions = completer.results.prefix(8).map(AppleMapsSuggestion.init)
        isSearching = false
        message = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appleSuggestions = []
        isSearching = false
        message = "Apple Maps search is unavailable. Bundled city search still works offline."
        AppLogger.search.error("Completer failed: \(error.localizedDescription, privacy: .public)")
    }

    func resolve(_ suggestion: AppleMapsSuggestion) async throws -> PlaceSeed {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw PlaceSearchError.noResolvedPlace
        }
        return PlaceSeed(mapItem: item)
    }

    private func queryChanged() {
        localTask?.cancel()
        message = nil
        let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            isSearching = false
            localResults = []
            appleSuggestions = []
            completer.queryFragment = ""
            completer.cancel()
            return
        }
        isSearching = true
        completer.queryFragment = current
        localTask = Task { [weak self, cityCatalog] in
            do {
                let results = try await cityCatalog.search(current)
                guard !Task.isCancelled else { return }
                self?.localResults = results
            } catch {
                guard !Task.isCancelled else { return }
                self?.message = "Bundled city search could not be loaded."
                AppLogger.search.error("Local search failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum PlaceSearchError: LocalizedError {
    case noResolvedPlace
    var errorDescription: String? { "Apple Maps could not resolve that result." }
}
