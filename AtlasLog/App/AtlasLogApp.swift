import SwiftData
import SwiftUI

@main
struct AtlasLogApp: App {
    private let dependencies = AppDependencies()
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema(SchemaV2.models)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, migrationPlan: AtlasMigrationPlan.self, configurations: [configuration])
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
                let context = ModelContext(container)
                // Let SwiftData apply the place-to-visit cascade; batch deletion
                // of visits violates the inverse relationship in a populated store.
                for place in try context.fetch(FetchDescriptor<PlaceRecord>()) {
                    context.delete(place)
                }
                try context.delete(model: AreaStatus.self)
                try context.delete(model: ImportedAssetRecord.self)
                try context.save()
                UserDefaults.standard.removeObject(forKey: "mapLevel")
                UserDefaults.standard.removeObject(forKey: "mapStyle")
            }
            let context = ModelContext(container)
            try TravelRecordService(context: context).recalculateDerivedAreas()
            try context.save()
        } catch {
            fatalError("Could not initialize the local travel store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TravelMapScreen()
                .environment(\.appDependencies, dependencies)
        }
        .modelContainer(container)
    }
}
