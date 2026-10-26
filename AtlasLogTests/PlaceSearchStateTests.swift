import Foundation
import MapKit
import Testing
@testable import AtlasLog

@MainActor
struct PlaceSearchStateTests {
    @Test func clearingSearchIgnoresLateFailure() {
        let state = PlaceSearchState(cityCatalog: CityCatalog(cities: []))
        state.query = "London"
        #expect(state.isSearching)
        state.query = "   "

        state.completer(MKLocalSearchCompleter(), didFailWithError: URLError(.cancelled))

        #expect(!state.isSearching)
        #expect(state.message == nil)
        #expect(state.appleSuggestions.isEmpty)
        #expect(state.localResults.isEmpty)
    }

    @Test func retryClearsPreviousFailure() {
        let state = PlaceSearchState(cityCatalog: CityCatalog(cities: []))
        state.query = "London"
        state.completer(MKLocalSearchCompleter(), didFailWithError: URLError(.notConnectedToInternet))
        #expect(state.message != nil)

        state.query = "Tokyo"

        #expect(state.message == nil)
        #expect(state.isSearching)
        state.query = ""
    }

    @Test func successfulCompletionClearsFailure() {
        let state = PlaceSearchState(cityCatalog: CityCatalog(cities: []))
        state.query = "London"
        let completer = MKLocalSearchCompleter()
        state.completer(completer, didFailWithError: URLError(.notConnectedToInternet))

        state.completerDidUpdateResults(completer)

        #expect(state.message == nil)
        #expect(!state.isSearching)
        state.query = ""
    }
}
