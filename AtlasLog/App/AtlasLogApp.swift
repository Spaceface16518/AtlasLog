import SwiftData
import SwiftUI

@main
struct AtlasLogApp: App {
    private let dependencies = AppDependencies()
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema(SchemaV1.models)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, migrationPlan: AtlasMigrationPlan.self, configurations: [configuration])
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
                let context = ModelContext(container)
                try context.delete(model: PlaceRecord.self)
                try context.delete(model: AreaStatus.self)
                try context.delete(model: ImportedAssetRecord.self)
                try context.save()
            }
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
