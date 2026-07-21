import Foundation
import SwiftData

@MainActor
struct TravelRecordService {
    let context: ModelContext

    func apply(_ draft: StatusDraft, to place: PlaceRecord, now: Date = .now) throws {
        var normalized = draft
        normalized.isVisited = !place.visits.isEmpty
        if normalized.isVisited {
            normalized.isWantToVisit = false
        } else {
            normalized.isMeaningfulVisit = false
            normalized.isWantToReturn = false
        }
        place.isVisited = normalized.isVisited
        place.isWantToVisit = normalized.isWantToVisit
        place.isMeaningfulVisit = normalized.isMeaningfulVisit
        place.isWantToReturn = normalized.isWantToReturn
        place.updatedAt = now
        try recalculateDerivedAreas()
        try context.save()
    }

    @discardableResult
    func addVisit(
        canonicalKey: String, name: String, kind: PlaceKind = .city,
        coordinate: CoordinateValue, countryCode: String? = nil, countryName: String? = nil,
        administrativeArea: String? = nil, source: VisitSource, status: StatusDraft,
        startDate: Date, endDate: Date? = nil
    ) throws -> PlaceRecord {
        let place = try upsertPlace(canonicalKey: canonicalKey, name: name, kind: kind,
                                    coordinate: coordinate, countryCode: countryCode,
                                    countryName: countryName, administrativeArea: administrativeArea,
                                    source: source, status: status)
        try addVisit(to: place, startDate: startDate, endDate: endDate, source: source, status: status)
        return place
    }

    @discardableResult
    func upsertPlace(
        canonicalKey: String, name: String, kind: PlaceKind = .city,
        coordinate: CoordinateValue, countryCode: String? = nil, countryName: String? = nil,
        administrativeArea: String? = nil, source: VisitSource, status: StatusDraft = .init()
    ) throws -> PlaceRecord {
        let key = canonicalKey
        let descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.canonicalKey == key })
        let place: PlaceRecord
        if let existing = try context.fetch(descriptor).first {
            place = existing
            place.name = name
            place.latitude = coordinate.latitude
            place.longitude = coordinate.longitude
            place.countryCode = countryCode
            place.countryName = countryName
            place.administrativeArea = administrativeArea
        } else {
            place = PlaceRecord(canonicalKey: canonicalKey, kind: kind, name: name,
                                latitude: coordinate.latitude, longitude: coordinate.longitude,
                                countryCode: countryCode, countryName: countryName,
                                administrativeArea: administrativeArea, locality: name,
                                status: status, source: source)
            context.insert(place)
        }
        try apply(status, to: place)
        return place
    }

    func addVisit(to place: PlaceRecord, startDate: Date, endDate: Date? = nil,
                  source: VisitSource = .manual, status: StatusDraft? = nil) throws {
        guard endDate == nil || endDate! >= startDate else { throw VisitValidationError.endBeforeStart }
        let visit = VisitRecord(startDate: startDate, endDate: endDate, source: source)
        context.insert(visit)
        place.visits.append(visit)
        var updatedStatus = status ?? place.status
        updatedStatus.setVisited(true)
        try apply(updatedStatus, to: place)
    }

    func update(_ visit: VisitRecord, startDate: Date, endDate: Date?) throws {
        guard endDate == nil || endDate! >= startDate else { throw VisitValidationError.endBeforeStart }
        visit.startDate = startDate
        visit.endDate = endDate
        visit.updatedAt = .now
        visit.place?.updatedAt = .now
        try context.save()
    }

    func delete(_ visit: VisitRecord) throws {
        let place = visit.place
        context.delete(visit)
        try context.save()
        if let place { try apply(place.status, to: place) }
    }

    func delete(_ place: PlaceRecord) throws {
        context.delete(place)
        try context.save()
        try recalculateDerivedAreas()
        try context.save()
    }

    func setManualArea(_ node: RegionNode, status: StatusDraft) throws {
        let id = node.id
        let descriptor = FetchDescriptor<AreaStatus>(predicate: #Predicate { $0.areaID == id })
        let area = try context.fetch(descriptor).first ?? AreaStatus(areaID: id, level: node.level)
        if area.modelContext == nil { context.insert(area) }
        area.isVisited = status.isVisited
        area.isWantToVisit = status.isWantToVisit
        area.isMeaningfulVisit = status.isMeaningfulVisit
        area.isWantToReturn = status.isWantToReturn
        area.isManualOverride = true
        area.sourceRawValue = VisitSource.manual.rawValue
        area.updatedAt = .now
        try context.save()
    }

    func recalculateDerivedAreas() throws {
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        var existing = Dictionary(uniqueKeysWithValues: areas.map { ($0.areaID, $0) })
        let visited = places.filter(\.isVisited)
        let countryGroups = Dictionary(grouping: visited.compactMap { place -> (String, PlaceRecord)? in
            guard let code = place.countryCode?.uppercased() else { return nil }
            return (code, place)
        }, by: \.0)

        var derivedIDs = Set<String>()
        var continentChildren: [String: [PlaceRecord]] = [:]
        for (code, pairs) in countryGroups {
            let id = "country:\(code)"
            derivedIDs.insert(id)
            let area = existing[id] ?? AreaStatus(areaID: id, level: .country)
            if area.modelContext == nil { context.insert(area); existing[id] = area }
            guard !area.isManualOverride else { continue }
            let children = pairs.map(\.1)
            area.isVisited = true
            area.isMeaningfulVisit = children.contains(where: \.isMeaningfulVisit)
            area.isWantToReturn = children.contains(where: \.isWantToReturn)
            area.isWantToVisit = false
            area.updatedAt = .now

            if let continent = Self.continentID(for: code) {
                derivedIDs.insert(continent)
                continentChildren[continent, default: []].append(contentsOf: children)
            }
        }
        for (continentID, children) in continentChildren {
            let parent = existing[continentID] ?? AreaStatus(areaID: continentID, level: .continent)
            if parent.modelContext == nil { context.insert(parent); existing[continentID] = parent }
            if !parent.isManualOverride {
                parent.isVisited = true
                parent.isMeaningfulVisit = children.contains(where: \.isMeaningfulVisit)
                parent.isWantToReturn = children.contains(where: \.isWantToReturn)
                parent.isWantToVisit = false
                parent.updatedAt = .now
            }
        }
        for area in areas where !area.isManualOverride && !derivedIDs.contains(area.areaID) && area.level != .travelRegion {
            area.isVisited = false
            area.isMeaningfulVisit = false
            area.isWantToReturn = false
        }
    }

    nonisolated static func customCanonicalKey(name: String, countryCode: String?, coordinate: CoordinateValue) -> String {
        let normalized = CityCatalog.normalize(name)
        return "custom:\(countryCode?.lowercased() ?? "xx"):\(normalized):\(String(format: "%.4f", coordinate.latitude)):\(String(format: "%.4f", coordinate.longitude))"
    }

    static func continentID(for countryCode: String) -> String? {
        let southAmerica = ["AR", "BO", "BR", "CL", "CO", "EC", "GY", "PE", "PY", "SR", "UY", "VE"]
        let northAmerica = ["CA", "US", "MX"]
        let europe = ["BE", "DK", "EE", "ES", "FI", "FR", "GB", "IS", "LT", "LU", "LV", "NL", "NO", "PT", "RS", "SE"]
        let asia = ["CN", "IN", "JP", "RU"]
        let africa = ["EG", "ZA"]
        if southAmerica.contains(countryCode) { return "continent:south-america" }
        if northAmerica.contains(countryCode) { return "continent:north-america" }
        if europe.contains(countryCode) { return "continent:europe" }
        if asia.contains(countryCode) { return "continent:asia" }
        if africa.contains(countryCode) { return "continent:africa" }
        if countryCode == "AU" { return "continent:oceania" }
        return nil
    }
}

enum VisitValidationError: LocalizedError {
    case endBeforeStart

    var errorDescription: String? { "A visit’s end date cannot be before its start date." }
}
