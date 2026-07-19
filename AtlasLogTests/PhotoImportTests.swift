import Foundation
import PhotosUI
import SwiftUI
import Testing
@testable import AtlasLog

private actor NoopMetadataExtractor: PhotoMetadataExtracting {
    func extract(from item: PhotosPickerItem) async throws -> ExtractedPhotoMetadata { throw PhotoImportError.noLocation }
}

private actor NoopGeocoder: Geocoding {
    func reverse(_ coordinate: CoordinateValue) async throws -> ReverseGeocodedPlace? { nil }
}

struct PhotoImportTests {
    private func processor() -> PhotoImportProcessor {
        PhotoImportProcessor(metadataService: NoopMetadataExtractor(),
            cityCatalog: CityCatalog(cities: [city("lima", "Lima", -12.0432, -77.0282)]),
            regionCatalog: RegionCatalog(), geocoder: NoopGeocoder())
    }

    @Test func severalPhotosGroupIntoOneCity() async throws {
        let photos = [
            ExtractedPhotoMetadata(assetIdentifier: "one", coordinate: .init(longitude: -77.03, latitude: -12.04), creationDate: .distantPast),
            ExtractedPhotoMetadata(assetIdentifier: "two", coordinate: .init(longitude: -77.04, latitude: -12.05), creationDate: .now)
        ]
        let candidates = try await processor().buildCandidates(from: photos)
        #expect(candidates.count == 1); #expect(candidates.first?.photoCount == 2)
        #expect(candidates.first?.earliestDate == .distantPast)
    }

    @Test func canceledCandidateBuild() async {
        let task = Task { try await processor().buildCandidates(from: [
            ExtractedPhotoMetadata(assetIdentifier: "one", coordinate: .init(longitude: 0, latitude: 0), creationDate: nil)
        ]) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
