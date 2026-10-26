import Foundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI

struct ExtractedPhotoMetadata: Sendable {
    let assetIdentifier: String?
    let coordinate: CoordinateValue
    let creationDate: Date?
}

protocol PhotoMetadataExtracting: Sendable {
    func extract(from item: PhotosPickerItem) async throws -> ExtractedPhotoMetadata
}

actor PhotoMetadataService: PhotoMetadataExtracting {
    private let parser = GPSMetadataParser()

    func extract(from item: PhotosPickerItem) async throws -> ExtractedPhotoMetadata {
        let identifier = item.itemIdentifier
        if let identifier {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = result.firstObject, let location = asset.location {
                return ExtractedPhotoMetadata(assetIdentifier: identifier,
                                              coordinate: .init(longitude: location.coordinate.longitude, latitude: location.coordinate.latitude),
                                              creationDate: asset.creationDate)
            }
        }
        guard let data = try await item.loadTransferable(type: Data.self),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw PhotoImportError.noLocation
        }
        do {
            let coordinate = try parser.parse(properties)
            return ExtractedPhotoMetadata(assetIdentifier: identifier, coordinate: coordinate, creationDate: imageDate(properties))
        } catch {
            throw PhotoImportError.noLocation
        }
    }

    private func imageDate(_ properties: [String: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let value = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
