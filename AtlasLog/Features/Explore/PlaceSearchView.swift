import SwiftUI
import OSLog

struct PlaceSearchView: View {
    @Bindable var state: PlaceSearchState
    var onSelect: (PlaceSeed) -> Void
    @State private var resolvingID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search cities and landmarks", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .accessibilityIdentifier("place-search")
            if !state.localResults.isEmpty {
                resultSection("Bundled cities", systemImage: "building.2") {
                    ForEach(state.localResults) { city in
                        Button { onSelect(PlaceSeed(city: city)) } label: {
                            PlaceRow(title: city.name, subtitle: city.countryName, symbol: "building.2")
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !state.appleSuggestions.isEmpty {
                resultSection("Apple Maps", systemImage: "map") {
                    ForEach(state.appleSuggestions) { suggestion in
                        Button { resolve(suggestion) } label: {
                            PlaceRow(title: suggestion.title, subtitle: suggestion.subtitle, symbol: "mappin.and.ellipse",
                                     trailingProgress: resolvingID == suggestion.id)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let message = state.message {
                Label(message, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func resolve(_ suggestion: AppleMapsSuggestion) {
        resolvingID = suggestion.id
        Task {
            defer { resolvingID = nil }
            do { onSelect(try await state.resolve(suggestion)) }
            catch { AppLogger.search.error("Resolution failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

struct PlaceRow: View {
    let title: String
    let subtitle: String?
    let symbol: String
    var trailingProgress = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).frame(width: 28, height: 28).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if trailingProgress { ProgressView().controlSize(.small) }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
