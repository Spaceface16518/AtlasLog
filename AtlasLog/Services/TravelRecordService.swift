import Foundation
import OSLog
import SwiftData

@MainActor
struct TravelRecordService {
    let context: ModelContext
    private let aggregateGeometries: [RegionGeometry]
    private let regionNodes: [RegionNode]

    init(
        context: ModelContext,
        aggregateGeometries: [RegionGeometry]? = nil,
        regionNodes: [RegionNode]? = nil
    ) {
        self.context = context
        self.aggregateGeometries =
            aggregateGeometries ?? Self.bundledAggregateGeometries
        self.regionNodes = regionNodes ?? Self.bundledRegionNodes
    }

    private static let bundledAggregateGeometries: [RegionGeometry] = {
        do {
            return try RegionCatalog.loadGeometries(
                named: ["composed_regions", "us_regions"]
            )
        } catch {
            AppLogger.catalog.error(
                "Aggregate region load failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }()

    private static let bundledRegionNodes: [RegionNode] = {
        do {
            return try RegionCatalog.loadHierarchyNodes()
        } catch {
            AppLogger.catalog.error(
                "Region hierarchy load failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }()

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
        guard endDate == nil || endDate! >= startDate else { throw VisitValidationError.endBeforeStart }
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
        try recalculateDerivedAreas()
        try context.save()
    }

    func confirmPhotoRegions(_ regionIDs: [String], status: StatusDraft) throws {
        let derivedIDs = Set(aggregateGeometries.map(\.regionID))
        for id in Set(regionIDs) where !derivedIDs.contains(id) {
            guard let node = regionNodes.first(where: { $0.id == id }) else { continue }
            // Precise bundled regions already follow the saved visit. Only
            // interpretive regions need a separate, confirmed manual status.
            try setManualArea(node, status: status)
        }
    }

    func recalculateDerivedAreas() throws {
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let areas = try context.fetch(FetchDescriptor<AreaStatus>())
        var existing = Dictionary(uniqueKeysWithValues: areas.map { ($0.areaID, $0) })
        let visited = places.filter { !$0.visits.isEmpty }
        let countryGroups = Dictionary(grouping: visited.compactMap { place -> (String, PlaceRecord)? in
            guard let code = place.countryCode?.uppercased() else { return nil }
            return (code, place)
        }, by: \.0)

        var derivedIDs = Set<String>()
        for (code, pairs) in countryGroups {
            let id = "country:\(code)"
            derivedIDs.insert(id)
            let area = existing[id] ?? AreaStatus(areaID: id, level: .country)
            if area.modelContext == nil { context.insert(area); existing[id] = area }
            guard !area.isManualOverride else { continue }
            update(area, from: pairs.map(\.1))
        }

        var aggregateRollups: [String: AreaRollup] = [:]
        for place in visited {
            let matches = RegionMembershipService().matches(
                point: .init(
                    longitude: place.longitude,
                    latitude: place.latitude
                ),
                geometries: aggregateGeometries
            )
            .filter { $0.membership == .core }
            for match in matches {
                aggregateRollups[match.regionID, default: .init()].merge(place)
            }
        }

        let nodesByID = Dictionary(
            uniqueKeysWithValues: regionNodes.map { ($0.id, $0) }
        )
        for area in areas where area.isManualOverride && area.isVisited {
            var parentID = nodesByID[area.areaID]?.parentID
            var visitedParentIDs = Set<String>()
            while let currentID = parentID,
                visitedParentIDs.insert(currentID).inserted
            {
                aggregateRollups[currentID, default: .init()].merge(area)
                parentID = nodesByID[currentID]?.parentID
            }
        }

        for (regionID, rollup) in aggregateRollups {
            guard let level = aggregateLevel(for: regionID) else { continue }
            derivedIDs.insert(regionID)
            let area =
                existing[regionID]
                ?? AreaStatus(areaID: regionID, level: level)
            if area.modelContext == nil {
                context.insert(area)
                existing[regionID] = area
            }
            guard !area.isManualOverride else { continue }
            update(area, from: rollup)
        }

        let spatialRegionIDs = Set(aggregateGeometries.map(\.regionID))
        for area in areas where !area.isManualOverride && !derivedIDs.contains(area.areaID)
            && (area.level != .travelRegion || spatialRegionIDs.contains(area.areaID)) {
            area.isVisited = false
            area.isMeaningfulVisit = false
            area.isWantToReturn = false
        }
    }

    nonisolated static func customCanonicalKey(name: String, countryCode: String?, coordinate: CoordinateValue) -> String {
        let normalized = CityCatalog.normalize(name)
        return "custom:\(countryCode?.lowercased() ?? "xx"):\(normalized):\(String(format: "%.4f", coordinate.latitude)):\(String(format: "%.4f", coordinate.longitude))"
    }

    private func aggregateLevel(for regionID: String) -> RegionLevel? {
        if regionID.hasPrefix("travel:") { return .travelRegion }
        if regionID.hasPrefix("macro:") { return .macroRegion }
        if regionID.hasPrefix("subcontinent:") { return .subcontinent }
        if regionID.hasPrefix("continent:") { return .continent }
        return nil
    }

    private func update(_ area: AreaStatus, from places: [PlaceRecord]) {
        area.isVisited = true
        area.isMeaningfulVisit = places.contains(where: \.isMeaningfulVisit)
        area.isWantToReturn = places.contains(where: \.isWantToReturn)
        area.isWantToVisit = false
        area.updatedAt = .now
    }

    private func update(_ area: AreaStatus, from rollup: AreaRollup) {
        area.isVisited = true
        area.isMeaningfulVisit = rollup.isMeaningfulVisit
        area.isWantToReturn = rollup.isWantToReturn
        area.isWantToVisit = false
        area.updatedAt = .now
    }
}

private struct AreaRollup {
    var isMeaningfulVisit = false
    var isWantToReturn = false

    mutating func merge(_ place: PlaceRecord) {
        isMeaningfulVisit = isMeaningfulVisit || place.isMeaningfulVisit
        isWantToReturn = isWantToReturn || place.isWantToReturn
    }

    mutating func merge(_ area: AreaStatus) {
        isMeaningfulVisit = isMeaningfulVisit || area.isMeaningfulVisit
        isWantToReturn = isWantToReturn || area.isWantToReturn
    }
}

enum VisitValidationError: LocalizedError {
    case endBeforeStart

    var errorDescription: String? { "A visit’s end date cannot be before its start date." }
}
