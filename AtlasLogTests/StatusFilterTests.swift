import Foundation
import SwiftData
import Testing
@testable import AtlasLog

@MainActor
struct StatusFilterTests {
    @Test func allIncludesUntrackedRegionsButSpecificFiltersExcludeThem() {
        for status in [nil, StatusDraft()] {
            #expect(StatusFilter.all.matches(status))
            for filter in StatusFilter.allCases where filter != .all {
                #expect(!filter.matches(status))
            }
        }
    }

    @Test func filtersDistinguishLimitedMeaningfulWishlistAndReturnStatuses() {
        let statuses: [StatusDraft] = [
            .init(isVisited: true),
            .init(isVisited: true, isMeaningfulVisit: true),
            .init(isWantToVisit: true),
            .init(isVisited: true, isMeaningfulVisit: true, isWantToReturn: true),
        ]
        let expected: [StatusFilter: [Int]] = [
            .all: [0, 1, 2, 3], .visited: [0, 1, 3], .meaningful: [1, 3],
            .wantToVisit: [2], .wantToReturn: [3],
        ]
        for filter in StatusFilter.allCases {
            #expect(statuses.indices.filter { filter.matches(statuses[$0]) } == expected[filter])
        }
    }

    @Test func cityAndDerivedAreaFiltersFollowSavedStatusChanges() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let service = TravelRecordService(context: context)
        let place = try service.addVisit(canonicalKey: "filter-paris", name: "Paris",
                                         coordinate: .init(longitude: 2.35, latitude: 48.86),
                                         countryCode: "FR", source: .manual,
                                         status: .init(isVisited: true, isMeaningfulVisit: true, isWantToReturn: true),
                                         startDate: .now)
        let area = try #require(context.fetch(FetchDescriptor<AreaStatus>()).first { $0.areaID == "country:FR" })
        for filter in StatusFilter.allCases {
            #expect(filter.matches(place.status) == filter.matches(area.status))
        }
        #expect(StatusFilter.meaningful.matches(area.status))
        #expect(StatusFilter.wantToReturn.matches(area.status))
        try service.apply(.init(isVisited: true), to: place)
        #expect(StatusFilter.visited.matches(area.status))
        #expect(!StatusFilter.meaningful.matches(area.status))
        #expect(!StatusFilter.wantToReturn.matches(area.status))
        try service.delete(place)
        #expect(!StatusFilter.visited.matches(area.status))
        #expect(StatusFilter.all.matches(area.status))
    }
}
