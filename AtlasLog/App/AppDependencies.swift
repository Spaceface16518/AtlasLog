import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies {
    let cityCatalog: CityCatalog
    let regionCatalog: RegionCatalog
    let regionMembership = RegionMembershipService()

    init(bundle: Bundle = .main) {
        cityCatalog = CityCatalog(bundle: bundle)
        regionCatalog = RegionCatalog(bundle: bundle)
    }
}
