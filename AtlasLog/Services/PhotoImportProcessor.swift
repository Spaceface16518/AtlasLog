import Foundation
import PhotosUI
import SwiftUI

enum ImportConfidence: String, Sendable { case high = "High", medium = "Medium", needsReview = "Needs review" }
enum MatchingMethod: String, Sendable { case bundledCity = "Bundled city", appleMaps = "Apple Maps", coordinate = "Photo coordinate" }

struct PhotoImportCandidate: Identifiable, Sendable {
    let id: String
    var canonicalKey: String
    var proposedName: String
    var proposedCountry: String?
    var countryCode: String?
    var coordinate: CoordinateValue
    var photoCount: Int
    var earliestDate: Date?
    var latestDate: Date?
    var confidence: ImportConfidence
    var matchingMethod: MatchingMethod
    var assetIdentifiers: [String]
    var suggestedRegionIDs: [String]
    var include = true
    var isMeaningfulVisit = true
}

struct PhotoImportBatch: Sendable {
    var candidates: [PhotoImportCandidate]
    var skippedWithoutLocation: Int
    var duplicateAssets: Int
    var failed: Int
}

enum PhotoImportError: LocalizedError {
    case noLocation
    case canceled
    var errorDescription: String? {
        switch self {
        case .noLocation: "No GPS metadata was found."
        case .canceled: "Import canceled."
        }
    }
}

actor PhotoImportProcessor {
    private let metadataService: any PhotoMetadataExtracting
    private let cityCatalog: CityCatalog
    private let regionCatalog: RegionCatalog
    private let membershipService: RegionMembershipService
    private let geocoder: any Geocoding

    init(metadataService: any PhotoMetadataExtracting = PhotoMetadataService(), cityCatalog: CityCatalog,
         regionCatalog: RegionCatalog, membershipService: RegionMembershipService = .init(),
         geocoder: any Geocoding = MapKitGeocodingService()) {
        self.metadataService = metadataService
        self.cityCatalog = cityCatalog
        self.regionCatalog = regionCatalog
        self.membershipService = membershipService
        self.geocoder = geocoder
    }

    func process(_ items: [PhotosPickerItem]) async throws -> PhotoImportBatch {
        let geometries = (try? await regionCatalog.geometries()) ?? []
        var extracted: [ExtractedPhotoMetadata] = []
        var skipped = 0
        var failed = 0
        var iterator = items.makeIterator()

        try await withThrowingTaskGroup(of: Result<ExtractedPhotoMetadata, Error>.self) { group in
            for _ in 0..<min(4, items.count) {
                if let item = iterator.next() {
                    group.addTask { [metadataService] in
                        do { return .success(try await metadataService.extract(from: item)) }
                        catch { return .failure(error) }
                    }
                }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                switch result {
                case .success(let metadata): extracted.append(metadata)
                case .failure(let error):
                    if error is CancellationError { throw error }
                    if case PhotoImportError.noLocation = error { skipped += 1 } else { failed += 1 }
                }
                if let item = iterator.next() {
                    group.addTask { [metadataService] in
                        do { return .success(try await metadataService.extract(from: item)) }
                        catch { return .failure(error) }
                    }
                }
            }
        }

        var seenAssetIDs = Set<String>()
        var duplicateAssets = 0
        let unique = extracted.filter { photo in
            guard let identifier = photo.assetIdentifier else { return true }
            if seenAssetIDs.insert(identifier).inserted { return true }
            duplicateAssets += 1
            return false
        }
        let candidates = try await buildCandidates(from: unique, geometries: geometries)
        return PhotoImportBatch(candidates: candidates, skippedWithoutLocation: skipped,
                                duplicateAssets: duplicateAssets, failed: failed)
    }

    func buildCandidates(from extracted: [ExtractedPhotoMetadata], geometries: [RegionGeometry] = []) async throws -> [PhotoImportCandidate] {
        var grouped: [String: PhotoImportCandidate] = [:]
        for photo in extracted {
            try Task.checkCancellation()
            let match = try await cityCatalog.nearest(to: photo.coordinate)
            let key = match?.city.canonicalKey ?? TravelRecordService.customCanonicalKey(name: "Photo location", countryCode: nil, coordinate: photo.coordinate)
            let regionIDs = membershipService.matches(point: photo.coordinate, geometries: geometries)
                .filter { $0.membership == .core && $0.regionID.hasPrefix("travel:") }.map(\.regionID)
            if var candidate = grouped[key] {
                candidate.photoCount += 1
                candidate.assetIdentifiers.append(contentsOf: photo.assetIdentifier.map { [$0] } ?? [])
                candidate.earliestDate = [candidate.earliestDate, photo.creationDate].compactMap { $0 }.min()
                candidate.latestDate = [candidate.latestDate, photo.creationDate].compactMap { $0 }.max()
                candidate.suggestedRegionIDs = Array(Set(candidate.suggestedRegionIDs + regionIDs)).sorted()
                grouped[key] = candidate
            } else if let match {
                grouped[key] = PhotoImportCandidate(id: key, canonicalKey: key, proposedName: match.city.name,
                    proposedCountry: match.city.countryName, countryCode: match.city.countryCode,
                    coordinate: photo.coordinate, photoCount: 1, earliestDate: photo.creationDate,
                    latestDate: photo.creationDate, confidence: match.distanceKilometers <= 25 ? .high : .medium,
                    matchingMethod: .bundledCity, assetIdentifiers: photo.assetIdentifier.map { [$0] } ?? [],
                    suggestedRegionIDs: regionIDs)
            } else {
                let resolved = try? await geocoder.reverse(photo.coordinate)
                grouped[key] = PhotoImportCandidate(id: key, canonicalKey: key, proposedName: resolved?.name ?? "Photo location",
                    proposedCountry: resolved?.countryName, countryCode: resolved?.countryCode,
                    coordinate: photo.coordinate, photoCount: 1,
                    earliestDate: photo.creationDate, latestDate: photo.creationDate,
                    confidence: resolved == nil ? .needsReview : .medium,
                    matchingMethod: resolved == nil ? .coordinate : .appleMaps,
                    assetIdentifiers: photo.assetIdentifier.map { [$0] } ?? [],
                    suggestedRegionIDs: regionIDs)
            }
        }
        return grouped.values.sorted { $0.proposedName < $1.proposedName }
    }
}
