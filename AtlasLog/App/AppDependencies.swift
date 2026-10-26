import Foundation
import SwiftUI

struct AppDependencies: Sendable {
    let cityCatalog: CityCatalog
    let regionCatalog: RegionCatalog
    let regionMembership = RegionMembershipService()

    init(bundle: Bundle = .main) {
        cityCatalog = CityCatalog(bundle: bundle)
        regionCatalog = RegionCatalog(bundle: bundle)
    }
}

extension EnvironmentValues {
    @Entry var appDependencies = AppDependencies()
}
