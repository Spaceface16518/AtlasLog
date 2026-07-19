import CoreLocation
import Foundation
import MapKit

struct ReverseGeocodedPlace: Sendable {
    let name: String
    let subtitle: String?
}

protocol Geocoding: Sendable {
    func reverse(_ coordinate: CoordinateValue) async throws -> ReverseGeocodedPlace?
}

actor MapKitGeocodingService: Geocoding {
    func reverse(_ coordinate: CoordinateValue) async throws -> ReverseGeocodedPlace? {
        try Task.checkCancellation()
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
            return nil
        }
        let items = try await request.mapItems
        guard let item = items.first else { return nil }
        return ReverseGeocodedPlace(name: item.name ?? item.address?.shortAddress ?? "Photo location",
                                   subtitle: item.address?.shortAddress)
    }
}
