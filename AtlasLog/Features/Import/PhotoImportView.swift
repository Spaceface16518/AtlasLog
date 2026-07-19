import PhotosUI
import SwiftData
import SwiftUI
import OSLog

struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppDependencies.self) private var dependencies
    @Query private var importedAssets: [ImportedAssetRecord]
    @State private var selections: [PhotosPickerItem] = []
    @State private var candidates: [PhotoImportCandidate] = []
    @State private var isProcessing = false
    @State private var processorTask: Task<Void, Never>?
    @State private var skipped = 0
    @State private var failed = 0
    @State private var duplicateCount = 0
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isProcessing { processingView }
                else if candidates.isEmpty { selectionView }
                else { reviewView }
            }
            .navigationTitle("Import photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { cancel(); dismiss() } }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Import", action: save).disabled(!candidates.contains(where: \.include)) }
                }
            }
            .alert("Photo import", isPresented: .init(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("Done") { dismiss() }
            } message: { Text(resultMessage ?? "") }
            .alert("Couldn’t import", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onChange(of: selections) { _, items in if !items.isEmpty { process(items) } }
        }
    }

    private var selectionView: some View {
        ContentUnavailableView {
            Label("Choose travel photos", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("AtlasLog reads location and date metadata only from photos you select. Photo bytes, captions, faces, and albums are never saved.")
        } actions: {
            PhotosPicker(selection: $selections, maxSelectionCount: 200, matching: .images) {
                Label("Select photos", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            if skipped > 0 { Text("\(skipped) selected photos had no location.").font(.footnote) }
        }
    }

    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Processing \(selections.count) selected photos…").font(.headline)
            Text("Location extraction is limited to four images at a time.").font(.footnote).foregroundStyle(.secondary)
            Button("Cancel", role: .cancel, action: cancel)
        }
        .padding()
    }

    private var reviewView: some View {
        List {
            Section {
                Text("Review every proposed city before saving. Core travel-region matches are suggested; no photo is retained.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Proposed places") {
                ForEach($candidates) { $candidate in
                    ImportCandidateRow(candidate: $candidate, cityCatalog: dependencies.cityCatalog)
                }
            }
            if skipped + failed + duplicateCount > 0 {
                Section("Batch notes") {
                    if skipped > 0 { LabeledContent("No location", value: "\(skipped)") }
                    if duplicateCount > 0 { LabeledContent("Already imported", value: "\(duplicateCount)") }
                    if failed > 0 { LabeledContent("Failed", value: "\(failed)") }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func process(_ items: [PhotosPickerItem]) {
        processorTask?.cancel()
        isProcessing = true
        let known = Set(importedAssets.map(\.assetIdentifier))
        let filtered = items.filter { item in
            guard let id = item.itemIdentifier else { return true }
            return !known.contains(id)
        }
        duplicateCount = items.count - filtered.count
        let processor = PhotoImportProcessor(cityCatalog: dependencies.cityCatalog, regionCatalog: dependencies.regionCatalog)
        processorTask = Task {
            do {
                let batch = try await processor.process(filtered)
                guard !Task.isCancelled else { return }
                candidates = batch.candidates; skipped = batch.skippedWithoutLocation
                duplicateCount += batch.duplicateAssets; failed = batch.failed
            } catch is CancellationError {
                errorMessage = "Import canceled. No travel records were changed."
            } catch {
                AppLogger.photoImport.error("Processing failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = "The selected photos could not be processed."
            }
            isProcessing = false
        }
    }

    private func save() {
        var importedCities = 0
        do {
            let service = TravelRecordService(context: context)
            for candidate in candidates where candidate.include {
                var status = StatusDraft(); status.setVisited(true); status.setMeaningful(candidate.isMeaningfulVisit)
                _ = try service.upsert(canonicalKey: candidate.canonicalKey, name: candidate.proposedName,
                    coordinate: candidate.coordinate, countryCode: candidate.countryCode, countryName: candidate.proposedCountry,
                    source: .photoImport, status: status, firstVisitedAt: candidate.earliestDate, lastVisitedAt: candidate.latestDate)
                for identifier in candidate.assetIdentifiers where !importedAssets.contains(where: { $0.assetIdentifier == identifier }) {
                    context.insert(ImportedAssetRecord(assetIdentifier: identifier, matchedPlaceCanonicalKey: candidate.canonicalKey))
                }
                for regionID in candidate.suggestedRegionIDs {
                    let node = RegionNode(id: regionID, name: regionID, level: .travelRegion, parentID: nil,
                                          centroidLatitude: candidate.coordinate.latitude,
                                          centroidLongitude: candidate.coordinate.longitude,
                                          geometryFeatureIDs: [], boundaryKind: .culturalApproximation,
                                          notes: "Confirmed during photo import")
                    try service.setManualArea(node, status: status)
                }
                try context.save()
                importedCities += 1
            }
            resultMessage = "Imported \(importedCities) places. \(skipped) photos had no location, \(duplicateCount) were duplicates, and \(failed) failed."
        } catch {
            AppLogger.photoImport.error("Save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Some places may have been imported, but the batch could not be completed."
        }
    }

    private func cancel() { processorTask?.cancel(); processorTask = nil; isProcessing = false }
}

struct ImportCandidateRow: View {
    @Binding var candidate: PhotoImportCandidate
    let cityCatalog: CityCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $candidate.include) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Place name", text: $candidate.proposedName).font(.headline)
                    Text([candidate.proposedCountry, "\(candidate.photoCount) photos"].compactMap { $0 }.joined(separator: " • "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if candidate.include {
                HStack {
                    Label(candidate.confidence.rawValue, systemImage: confidenceSymbol).font(.caption.weight(.medium))
                    Spacer()
                    Text(candidate.matchingMethod.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Meaningful visit", isOn: $candidate.isMeaningfulVisit)
                NavigationLink {
                    ImportLocationSearchView(candidate: $candidate, cityCatalog: cityCatalog)
                } label: {
                    Label("Edit location", systemImage: "location.magnifyingglass")
                }
                if let first = candidate.earliestDate {
                    Text(dateRange(first)).font(.caption).foregroundStyle(.secondary)
                }
                if !candidate.suggestedRegionIDs.isEmpty {
                    Text("Suggested: \(candidate.suggestedRegionIDs.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    private var confidenceSymbol: String {
        switch candidate.confidence { case .high: "checkmark.seal.fill"; case .medium: "circle.lefthalf.filled"; case .needsReview: "exclamationmark.triangle" }
    }
    private func dateRange(_ first: Date) -> String {
        guard let last = candidate.latestDate, !Calendar.current.isDate(first, inSameDayAs: last) else { return first.formatted(date: .abbreviated, time: .omitted) }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct ImportLocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var candidate: PhotoImportCandidate
    @State private var searchState: PlaceSearchState

    init(candidate: Binding<PhotoImportCandidate>, cityCatalog: CityCatalog) {
        _candidate = candidate
        _searchState = State(initialValue: PlaceSearchState(cityCatalog: cityCatalog))
    }

    var body: some View {
        ScrollView {
            PlaceSearchView(state: searchState) { seed in
                candidate.canonicalKey = seed.canonicalKey ?? TravelRecordService.customCanonicalKey(
                    name: seed.name, countryCode: seed.countryCode, coordinate: seed.coordinate)
                candidate.proposedName = seed.name
                candidate.proposedCountry = seed.countryName
                candidate.countryCode = seed.countryCode
                candidate.coordinate = seed.coordinate
                candidate.confidence = .high
                candidate.matchingMethod = seed.source == .appleMaps ? .appleMaps : .bundledCity
                dismiss()
            }
            .padding()
        }
        .navigationTitle("Replace location")
        .navigationBarTitleDisplayMode(.inline)
    }
}
