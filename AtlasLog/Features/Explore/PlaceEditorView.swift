import SwiftData
import SwiftUI
import OSLog

struct PlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let place: PlaceRecord?
    let seed: PlaceSeed?
    var onSaved: ((PlaceRecord) -> Void)?

    @State private var name = ""
    @State private var kind: PlaceKind = .city
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var countryCode = ""
    @State private var countryName = ""
    @State private var status = StatusDraft()
    @State private var includeVisitDates = false
    @State private var firstVisitedAt = Date.now
    @State private var lastVisitedAt = Date.now
    @State private var notes = ""
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("place-name")
                    Picker("Kind", selection: $kind) {
                        ForEach(PlaceKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Country", text: $countryName)
                    TextField("Country code", text: $countryCode)
                        .textInputAutocapitalization(.characters)
                }
                Section("Coordinate") {
                    LabeledContent("Latitude") { TextField("Latitude", value: $latitude, format: .number).multilineTextAlignment(.trailing) }
                    LabeledContent("Longitude") { TextField("Longitude", value: $longitude, format: .number).multilineTextAlignment(.trailing) }
                    if !validCoordinate { Label("Enter a valid latitude and longitude.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section("Travel status") {
                    Toggle("Visited", isOn: visitedBinding)
                        .accessibilityIdentifier("visited-toggle")
                    if status.isVisited {
                        Toggle("This was a meaningful visit", isOn: meaningfulBinding)
                            .accessibilityIdentifier("meaningful-toggle")
                        Text("Meaningful visits exclude airport-only, pass-through, or childhood visits you do not want counted in main totals.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Toggle("Want to return", isOn: returnBinding)
                        Text("Want-to-return places remain counted as visited and appear with future destinations.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Toggle("Want to visit", isOn: wishlistBinding)
                    }
                }
                if status.isVisited {
                    Section("Visit dates") {
                        Toggle("Add visit dates", isOn: $includeVisitDates)
                        if includeVisitDates {
                            DatePicker("First visit", selection: $firstVisitedAt, displayedComponents: .date)
                            DatePicker("Latest visit", selection: $lastVisitedAt, in: firstVisitedAt..., displayedComponents: .date)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional private notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if place != nil {
                    Section {
                        Button("Delete place", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .navigationTitle(place == nil ? "Add place" : "Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !validCoordinate)
                        .accessibilityIdentifier("save-place")
                }
            }
            .confirmationDialog("Delete this place?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .alert("Couldn’t save", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
            .onAppear(perform: load)
        }
    }

    private var validCoordinate: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    private var visitedBinding: Binding<Bool> { .init(get: { status.isVisited }, set: { status.setVisited($0) }) }
    private var meaningfulBinding: Binding<Bool> { .init(get: { status.isMeaningfulVisit }, set: { status.setMeaningful($0) }) }
    private var returnBinding: Binding<Bool> { .init(get: { status.isWantToReturn }, set: { status.setWantToReturn($0) }) }
    private var wishlistBinding: Binding<Bool> { .init(get: { status.isWantToVisit }, set: { status.setWantToVisit($0) }) }

    private func load() {
        if let place {
            name = place.name; kind = place.kind; latitude = place.latitude; longitude = place.longitude
            countryCode = place.countryCode ?? ""; countryName = place.countryName ?? ""; status = place.status
            notes = place.notes ?? ""
            if let date = place.firstVisitedAt { includeVisitDates = true; firstVisitedAt = date }
            if let date = place.lastVisitedAt { includeVisitDates = true; lastVisitedAt = date }
        } else if let seed {
            name = seed.name; kind = seed.kind; latitude = seed.coordinate.latitude; longitude = seed.coordinate.longitude
            countryCode = seed.countryCode ?? ""; countryName = seed.countryName ?? ""
        }
    }

    private func save() {
        do {
            let service = TravelRecordService(context: context)
            let coordinate = CoordinateValue(longitude: longitude, latitude: latitude)
            let saved: PlaceRecord
            if let place {
                place.name = name; place.kindRawValue = kind.rawValue; place.latitude = latitude; place.longitude = longitude
                place.countryCode = countryCode.nilIfEmpty; place.countryName = countryName.nilIfEmpty; place.notes = notes.nilIfEmpty
                place.firstVisitedAt = includeVisitDates ? firstVisitedAt : nil
                place.lastVisitedAt = includeVisitDates ? lastVisitedAt : nil
                try service.apply(status, to: place)
                saved = place
            } else {
                let key = seed?.canonicalKey ?? TravelRecordService.customCanonicalKey(name: name, countryCode: countryCode.nilIfEmpty, coordinate: coordinate)
                saved = try service.upsert(canonicalKey: key, name: name, kind: kind, coordinate: coordinate,
                                           countryCode: countryCode.nilIfEmpty, countryName: countryName.nilIfEmpty,
                                           administrativeArea: seed?.administrativeArea, source: seed?.source ?? .manual,
                                           status: status, firstVisitedAt: includeVisitDates ? firstVisitedAt : nil,
                                           lastVisitedAt: includeVisitDates ? lastVisitedAt : nil)
            }
            onSaved?(saved)
            dismiss()
        } catch {
            AppLogger.persistence.error("Place save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Your place could not be saved. Check the details and try again."
        }
    }

    private func delete() {
        guard let place else { return }
        do { try TravelRecordService(context: context).delete(place); dismiss() }
        catch { errorMessage = "Your place could not be deleted." }
    }
}

private extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

#if DEBUG
#Preview("Place editor — dark, large type") {
    PlaceEditorView(place: nil, seed: PlaceSeed(canonicalKey: nil, mapItemIdentifier: nil, kind: .city,
        name: "Cusco", subtitle: "Peru", coordinate: .init(longitude: -71.967, latitude: -13.523),
        countryCode: "PE", countryName: "Peru", administrativeArea: "Cusco", source: .bundledCatalog))
        .modelContainer(PreviewSupport.container())
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
