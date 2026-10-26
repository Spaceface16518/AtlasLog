import Foundation
import SwiftData

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PlaceRecord.self, VisitRecord.self, AreaStatus.self, ImportedAssetRecord.self]
    }

    @Model
    final class PlaceRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var canonicalKey: String
        var mapItemIdentifierValue: String?
        var kindRawValue: String
        var name: String
        var subtitle: String?
        var latitude: Double
        var longitude: Double
        var countryCode: String?
        var countryName: String?
        var administrativeArea: String?
        var locality: String?
        var isVisited: Bool
        var isWantToVisit: Bool
        var isMeaningfulVisit: Bool
        var isWantToReturn: Bool
        // Kept only so the V1 migration can turn the old aggregate range into a visit.
        var firstVisitedAt: Date?
        var lastVisitedAt: Date?
        var notes: String?
        var sourceRawValue: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \VisitRecord.place)
        var visits: [VisitRecord] = []

        init(
            id: UUID = UUID(), canonicalKey: String, mapItemIdentifierValue: String? = nil,
            kind: PlaceKind = .city, name: String, subtitle: String? = nil,
            latitude: Double, longitude: Double, countryCode: String? = nil,
            countryName: String? = nil, administrativeArea: String? = nil, locality: String? = nil,
            status: StatusDraft = .init(), notes: String? = nil,
            source: VisitSource = .manual, now: Date = .now
        ) {
            self.id = id
            self.canonicalKey = canonicalKey
            self.mapItemIdentifierValue = mapItemIdentifierValue
            self.kindRawValue = kind.rawValue
            self.name = name
            self.subtitle = subtitle
            self.latitude = latitude
            self.longitude = longitude
            self.countryCode = countryCode
            self.countryName = countryName
            self.administrativeArea = administrativeArea
            self.locality = locality
            self.isVisited = status.isVisited
            self.isWantToVisit = status.isWantToVisit
            self.isMeaningfulVisit = status.isMeaningfulVisit
            self.isWantToReturn = status.isWantToReturn
            self.firstVisitedAt = nil
            self.lastVisitedAt = nil
            self.notes = notes
            self.sourceRawValue = source.rawValue
            self.createdAt = now
            self.updatedAt = now
        }

        var kind: PlaceKind { PlaceKind(rawValue: kindRawValue) ?? .customPoint }
        var coordinate: (latitude: Double, longitude: Double) { (latitude, longitude) }
        var status: StatusDraft {
            StatusDraft(isVisited: isVisited, isWantToVisit: isWantToVisit,
                        isMeaningfulVisit: isMeaningfulVisit, isWantToReturn: isWantToReturn)
        }
        var sortedVisits: [VisitRecord] { visits.sorted { $0.startDate > $1.startDate } }
    }

    @Model
    final class VisitRecord {
        @Attribute(.unique) var id: UUID
        var startDate: Date
        var endDate: Date?
        var sourceRawValue: String
        var createdAt: Date
        var updatedAt: Date
        var place: PlaceRecord?

        init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil,
             source: VisitSource = .manual, place: PlaceRecord? = nil, now: Date = .now) {
            self.id = id
            self.startDate = startDate
            self.endDate = endDate
            self.sourceRawValue = source.rawValue
            self.createdAt = now
            self.updatedAt = now
            self.place = place
        }

        var source: VisitSource { VisitSource(rawValue: sourceRawValue) ?? .manual }
    }

    @Model
    final class AreaStatus {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var areaID: String
        var levelRawValue: String
        var isVisited: Bool
        var isWantToVisit: Bool
        var isMeaningfulVisit: Bool
        var isWantToReturn: Bool
        var isManualOverride: Bool
        var sourceRawValue: String
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), areaID: String, level: RegionLevel, status: StatusDraft = .init(),
             isManualOverride: Bool = false, source: VisitSource = .derived, now: Date = .now) {
            self.id = id
            self.areaID = areaID
            self.levelRawValue = level.rawValue
            self.isVisited = status.isVisited
            self.isWantToVisit = status.isWantToVisit
            self.isMeaningfulVisit = status.isMeaningfulVisit
            self.isWantToReturn = status.isWantToReturn
            self.isManualOverride = isManualOverride
            self.sourceRawValue = source.rawValue
            self.createdAt = now
            self.updatedAt = now
        }

        var level: RegionLevel { RegionLevel(rawValue: levelRawValue) ?? .country }
        var status: StatusDraft {
            StatusDraft(isVisited: isVisited, isWantToVisit: isWantToVisit,
                        isMeaningfulVisit: isMeaningfulVisit, isWantToReturn: isWantToReturn)
        }
    }

    @Model
    final class ImportedAssetRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var assetIdentifier: String
        var importedAt: Date
        var matchedPlaceCanonicalKey: String?

        init(id: UUID = UUID(), assetIdentifier: String, importedAt: Date = .now,
             matchedPlaceCanonicalKey: String? = nil) {
            self.id = id
            self.assetIdentifier = assetIdentifier
            self.importedAt = importedAt
            self.matchedPlaceCanonicalKey = matchedPlaceCanonicalKey
        }
    }
}

typealias PlaceRecord = SchemaV2.PlaceRecord
typealias VisitRecord = SchemaV2.VisitRecord
typealias AreaStatus = SchemaV2.AreaStatus
typealias ImportedAssetRecord = SchemaV2.ImportedAssetRecord
