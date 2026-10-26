import Foundation
import ImageIO

enum GPSMetadataError: Error, Equatable {
    case noGPSDictionary
    case missingLatitude
    case missingLongitude
    case missingLatitudeReference
    case missingLongitudeReference
    case malformedValue
    case invalidRange
}

struct GPSMetadataParser: Sendable {
    func parse(_ metadata: [String: Any]) throws -> CoordinateValue {
        guard let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            throw GPSMetadataError.noGPSDictionary
        }
        guard let latitudeValue = gps[kCGImagePropertyGPSLatitude as String] else { throw GPSMetadataError.missingLatitude }
        guard let longitudeValue = gps[kCGImagePropertyGPSLongitude as String] else { throw GPSMetadataError.missingLongitude }
        guard let latitudeReference = gps[kCGImagePropertyGPSLatitudeRef as String] as? String else { throw GPSMetadataError.missingLatitudeReference }
        guard let longitudeReference = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else { throw GPSMetadataError.missingLongitudeReference }
        guard let latitude = number(latitudeValue), let longitude = number(longitudeValue) else { throw GPSMetadataError.malformedValue }
        let signedLatitude = latitudeReference.uppercased() == "S" ? -abs(latitude) : abs(latitude)
        let signedLongitude = longitudeReference.uppercased() == "W" ? -abs(longitude) : abs(longitude)
        guard ["N", "S"].contains(latitudeReference.uppercased()), ["E", "W"].contains(longitudeReference.uppercased()),
              (-90...90).contains(signedLatitude), (-180...180).contains(signedLongitude) else {
            throw GPSMetadataError.invalidRange
        }
        return CoordinateValue(longitude: signedLongitude, latitude: signedLatitude)
    }

    private func number(_ value: Any) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
