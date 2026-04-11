import SwiftUI
import MapKit

struct SpotsListView: View {
    @Environment(AppState.self) private var appState
    @State private var spots: [Spot] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var selectedSpot: Spot?
    @State private var showingAddSpot = false
    @State private var searchText = ""

    var filtered: [Spot] {
        if searchText.isEmpty { return spots }
        return spots.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.notes ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if spots.isEmpty {
                ContentUnavailableView(
                    "No Spots Yet",
                    systemImage: "mappin.slash",
                    description: Text("Add spots from the map or when logging a catch")
                )
            } else {
                List {
                    ForEach(filtered) { spot in
                        Button {
                            selectedSpot = spot
                        } label: {
                            SpotRow(spot: spot, catchCount: catchCounts[spot.id] ?? 0)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { filtered[$0] }
                        for spot in toDelete {
                            try? appState.spotRepository.delete(spot)
                        }
                        Task { await loadData() }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search spots")
            }
        }
        .navigationTitle("Spots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSpot = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailSheet(spot: spot)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingAddSpot) {
            AddSpotSheet()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private func loadData() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = spotCatches.count
        }
    }
}

struct SpotRow: View {
    let spot: Spot
    let catchCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Mini map
            Map(initialPosition: .camera(.init(
                centerCoordinate: CLLocationCoordinate2D(
                    latitude: spot.latitude, longitude: spot.longitude
                ),
                distance: 3000
            ))) {
                Annotation("", coordinate: CLLocationCoordinate2D(
                    latitude: spot.latitude, longitude: spot.longitude
                )) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .mapStyle(.hybrid)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Label("\(catchCount)", systemImage: "fish.fill")
                    if spot.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(spot.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
