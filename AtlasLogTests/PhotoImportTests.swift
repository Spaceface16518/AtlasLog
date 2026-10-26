import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import Testing
@testable import AtlasLog

private actor NoopMetadataExtractor: PhotoMetadataExtracting {
    func extract(from item: PhotosPickerItem) async throws -> ExtractedPhotoMetadata { throw PhotoImportError.noLocation }
}

private actor NoopGeocoder: Geocoding {
    func reverse(_ coordinate: CoordinateValue) async throws -> ReverseGeocodedPlace? { nil }
}

private actor CountryGeocoder: Geocoding {
    func reverse(_ coordinate: CoordinateValue) async throws -> ReverseGeocodedPlace? {
        ReverseGeocodedPlace(name: "San Francisco", subtitle: "San Francisco, CA",
                            countryCode: "US", countryName: "United States")
    }
}

struct PhotoImportTests {
    @Test @MainActor func washingtonPhotoUsesBundledCityAndRemovableRegionRollups() async throws {
        let processor = PhotoImportProcessor(metadataService: NoopMetadataExtractor(), cityCatalog: CityCatalog(),
            regionCatalog: RegionCatalog(), geocoder: NoopGeocoder())
        let photo = ExtractedPhotoMetadata(assetIdentifier: "dc", coordinate: .init(longitude: -77.0365, latitude: 38.8977), creationDate: .now)
        let geometries = try await RegionCatalog().geometries()
        let candidate = try #require(try await processor.buildCandidates(from: [photo], geometries: geometries).first)
        #expect(candidate.canonicalKey == "geonames:4140963")
        #expect(candidate.matchingMethod == .bundledCity)
        #expect(Set(candidate.suggestedRegionIDs) == ["travel:washington-capital", "travel:us-south-atlantic"])
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = TravelRecordService(context: context)
        var status = StatusDraft(); status.setMeaningful(true)
        let place = try service.addVisit(canonicalKey: candidate.canonicalKey, name: candidate.proposedName,
            coordinate: candidate.coordinate, countryCode: candidate.countryCode, source: .photoImport,
            status: status, startDate: .now)
        try service.confirmPhotoRegions(candidate.suggestedRegionIDs, status: status)
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).allSatisfy { !$0.isManualOverride })
        try service.delete(place)
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).allSatisfy { !$0.isVisited })

        try service.confirmPhotoRegions(["travel:cascadia"], status: status)
        #expect(try context.fetch(FetchDescriptor<AreaStatus>()).contains { $0.areaID == "travel:cascadia" && $0.isManualOverride && $0.isVisited })
    }

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

    @Test func photoSuggestionsDoNotOverrideDerivedAdministrativeAreas() async throws {
        let geometries = ["country:PE", "continent:south-america", "subcontinent:south-america", "travel:test"].map { id in
            RegionGeometry(id: id, regionID: id, membership: .core, boundaryKind: .geographic,
                           definition: id, source: "test", polygons: [[[[-78, -13], [-76, -13], [-76, -11], [-78, -11], [-78, -13]]]])
        }
        let photos = [ExtractedPhotoMetadata(assetIdentifier: "lima", coordinate: .init(longitude: -77.03, latitude: -12.04), creationDate: .now)]
        let candidates = try await processor().buildCandidates(from: photos, geometries: geometries)
        #expect(candidates.first?.suggestedRegionIDs == ["travel:test"])
    }

    @Test func groupedPhotosKeepAllTravelRegionSuggestions() async throws {
        let geometries = [("travel:west", -77.05, -77.035), ("travel:east", -77.035, -77.02)].map { id, west, east in
            RegionGeometry(id: id, regionID: id, membership: .core, boundaryKind: .geographic,
                           definition: id, source: "test", polygons: [[[[west, -12.06], [east, -12.06], [east, -12.03], [west, -12.03], [west, -12.06]]]])
        }
        let photos = [-77.04, -77.03].map { longitude in
            ExtractedPhotoMetadata(assetIdentifier: nil, coordinate: .init(longitude: longitude, latitude: -12.04), creationDate: .now)
        }
        let candidates = try await processor().buildCandidates(from: photos, geometries: geometries)
        #expect(candidates.count == 1)
        #expect(candidates.first?.photoCount == 2)
        #expect(Set(candidates.first?.suggestedRegionIDs ?? []) == ["travel:west", "travel:east"])
    }

    @Test @MainActor func geocodedPhotoPreservesCountryForPassport() async throws {
        let processor = PhotoImportProcessor(metadataService: NoopMetadataExtractor(),
            cityCatalog: CityCatalog(cities: []), regionCatalog: RegionCatalog(), geocoder: CountryGeocoder())
        let photo = ExtractedPhotoMetadata(assetIdentifier: "san-francisco",
            coordinate: .init(longitude: -122.48, latitude: 37.77), creationDate: .now)
        let candidate = try #require(try await processor.buildCandidates(from: [photo]).first)
        #expect(candidate.proposedName == "San Francisco")
        #expect(candidate.countryCode == "US")
        #expect(candidate.proposedCountry == "United States")
        #expect(candidate.matchingMethod == .appleMaps)

        let container = try makeTestContainer()
        let context = container.mainContext
        var status = StatusDraft()
        status.setMeaningful(true)
        let place = try TravelRecordService(context: context).addVisit(
            canonicalKey: candidate.canonicalKey, name: candidate.proposedName,
            coordinate: candidate.coordinate, countryCode: candidate.countryCode,
            countryName: candidate.proposedCountry, source: .photoImport,
            status: status, startDate: .now)
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        let statistics = PassportStatisticsService().calculate(places: [place], areas: areas)
        #expect(statistics.countriesVisited == 1)
        #expect(statistics.meaningfulCountries == 1)
        #expect(areas.contains { $0.areaID == "country:US" && $0.isVisited })
    }
}
