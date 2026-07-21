import SwiftData
import SwiftUI
import OSLog

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var places: [PlaceRecord]
    @Query private var areas: [AreaStatus]
    @Query private var assets: [ImportedAssetRecord]
    @State private var showDeleteConfirmation = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Label("All travel records stay in the local SwiftData store.", systemImage: "lock.shield")
                    Text("Photo import only reads explicitly selected items. Original bytes, full-size copies, captions, faces, and album membership are not retained.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Apple Maps search, reverse lookup, map tiles, and normal device backups are controlled by Apple and may use network services.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Data") {
#if DEBUG
                    Button("Load sample journey", systemImage: "sparkles", action: loadSampleJourney)
#endif
                    Button("Delete all user data", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
                }
                Section("About") {
                    NavigationLink("Data acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Version", value: version)
                    LabeledContent("City coverage", value: AppIdentity.catalogFixtureNotice)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Delete all local travel data?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive, action: deleteAll)
            } message: { Text("This cannot be undone. Bundled catalogs remain available.") }
            .alert("AtlasLog", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func deleteAll() {
        do {
            places.forEach(context.delete); areas.forEach(context.delete); assets.forEach(context.delete)
            try context.save(); message = "All local travel data was deleted."
        } catch {
            AppLogger.persistence.error("Delete all failed: \(error.localizedDescription, privacy: .public)")
            message = "Data could not be deleted. Please try again."
        }
    }

    private func loadSampleJourney() {
        let samples: [(String, String, Double, Double, String, String)] = [
            ("4684888", "Dallas", 32.7831, -96.8067, "US", "United States"),
            ("3936456", "Lima", -12.0432, -77.0282, "PE", "Peru"),
            ("3941584", "Cusco", -13.5226, -71.9673, "PE", "Peru"),
            ("792680", "Belgrade", 44.804, 20.4651, "RS", "Serbia"),
            ("2643743", "London", 51.5085, -0.1257, "GB", "United Kingdom"),
            ("1850147", "Tokyo", 35.6895, 139.6917, "JP", "Japan")
        ]
        do {
            let service = TravelRecordService(context: context)
            for (index, sample) in samples.enumerated() {
                var status = StatusDraft(); status.setVisited(true); status.setMeaningful(index != 0)
                if sample.1 == "London" { status.setWantToReturn(true) }
                _ = try service.addVisit(canonicalKey: "geonames:\(sample.0)", name: sample.1,
                    coordinate: .init(longitude: sample.3, latitude: sample.2), countryCode: sample.4,
                    countryName: sample.5, source: .sample, status: status,
                    startDate: Calendar.current.date(byAdding: .year, value: -index - 1, to: .now) ?? .now)
            }
            message = "Loaded the clearly labeled six-city sample journey."
        } catch { message = "Sample data could not be loaded." }
    }
}

struct AcknowledgementsView: View {
    @State private var text = "Loading acknowledgements…"
    var body: some View {
        ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle("Acknowledgements")
            .task {
                guard let url = Bundle.main.url(forResource: "DataAttributions", withExtension: "md"),
                      let value = try? String(contentsOf: url, encoding: .utf8) else {
                    text = "Acknowledgement information is unavailable."
                    return
                }
                text = value
            }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().modelContainer(PreviewSupport.container(populated: true))
}

#Preview("Acknowledgements") {
    NavigationStack { AcknowledgementsView() }
}
#endif
