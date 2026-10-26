import ImageIO
import Testing
@testable import AtlasLog

struct GPSMetadataParserTests {
    private let parser = GPSMetadataParser()

    @Test func northernEasternCoordinate() throws {
        let value = try parser.parse(metadata(latitude: 12.5, latRef: "N", longitude: 77.2, lonRef: "E"))
        #expect(value == CoordinateValue(longitude: 77.2, latitude: 12.5))
    }
    @Test func southernCoordinate() throws { #expect(try parser.parse(metadata(latitude: 13, latRef: "S", longitude: 71, lonRef: "W")).latitude == -13) }
    @Test func westernCoordinate() throws { #expect(try parser.parse(metadata(latitude: 40, latRef: "N", longitude: 74, lonRef: "W")).longitude == -74) }
    @Test func missingLatitudeReference() { #expect(throws: GPSMetadataError.missingLatitudeReference) { try parser.parse(metadata(latitude: 1, latRef: nil, longitude: 1, lonRef: "E")) } }
    @Test func missingLongitude() { #expect(throws: GPSMetadataError.missingLongitude) { try parser.parse([kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 1, kCGImagePropertyGPSLatitudeRef as String: "N"]]) } }
    @Test func invalidRange() { #expect(throws: GPSMetadataError.invalidRange) { try parser.parse(metadata(latitude: 91, latRef: "N", longitude: 1, lonRef: "E")) } }
    @Test func malformedDictionary() { #expect(throws: GPSMetadataError.malformedValue) { try parser.parse(metadata(latitude: "x", latRef: "N", longitude: 1, lonRef: "E")) } }
    @Test func noGPSDictionary() { #expect(throws: GPSMetadataError.noGPSDictionary) { try parser.parse([:]) } }

    private func metadata(latitude: Any, latRef: String?, longitude: Any, lonRef: String?) -> [String: Any] {
        var gps: [String: Any] = [kCGImagePropertyGPSLatitude as String: latitude,
                                  kCGImagePropertyGPSLongitude as String: longitude]
        gps[kCGImagePropertyGPSLatitudeRef as String] = latRef
        gps[kCGImagePropertyGPSLongitudeRef as String] = lonRef
        return [kCGImagePropertyGPSDictionary as String: gps]
    }
}
