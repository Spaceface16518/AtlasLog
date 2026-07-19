import SwiftUI

enum TravelMapStyle: String, CaseIterable {
    case standard, satellite
}

struct MapLevelMenu: View {
    @Binding var level: RegionLevel

    var body: some View {
        Menu {
            ForEach(RegionLevel.allCases, id: \.self) { option in
                Button {
                    level = option
                } label: {
                    if level == option { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            Label(level.title, systemImage: "square.3.layers.3d")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("Map level, \(level.title)")
    }
}

struct PlaceMarker: View {
    let place: PlaceRecord
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(markerForeground)
                .frame(width: 30, height: 30)
                .background(markerBackground, in: Circle())
                .overlay(Circle().stroke(selected ? Color.accentColor : Color.white, lineWidth: selected ? 3 : 1.5))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            if place.isWantToReturn {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.caption2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.orange)
                    .offset(x: 5, y: -4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.name), \(statusText)")
    }

    private var symbol: String {
        if place.isMeaningfulVisit { return "checkmark" }
        if place.isVisited { return "checkmark.circle" }
        if place.isWantToVisit { return "star.fill" }
        return place.kind == .landmark ? "mappin" : "circle"
    }
    private var markerForeground: Color { place.isVisited ? .white : .primary }
    private var markerBackground: Color {
        if place.isMeaningfulVisit { return .accentColor }
        if place.isVisited { return .secondary }
        if place.isWantToVisit { return .yellow }
        return .gray.opacity(0.6)
    }
    private var statusText: String {
        if place.isWantToReturn { return "visited, wants to return" }
        if place.isMeaningfulVisit { return "meaningful visit" }
        if place.isVisited { return "limited visit" }
        if place.isWantToVisit { return "wants to visit" }
        return "tracked"
    }
}
