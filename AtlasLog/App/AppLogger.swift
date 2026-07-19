import OSLog

enum AppLogger {
    static let persistence = Logger(subsystem: "com.grayscale.AtlasLog", category: "Persistence")
    static let catalog = Logger(subsystem: "com.grayscale.AtlasLog", category: "Catalog")
    static let search = Logger(subsystem: "com.grayscale.AtlasLog", category: "Search")
    static let photoImport = Logger(subsystem: "com.grayscale.AtlasLog", category: "PhotoImport")
}
