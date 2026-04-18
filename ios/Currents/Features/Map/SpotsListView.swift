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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { spot in
                            Button {
                                selectedSpot = spot
                            } label: {
                                SpotCard(spot: spot, catchCount: catchCounts[spot.id] ?? 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
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

struct SpotCard: View {
    let spot: Spot
    let catchCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: .camera(.init(
                centerCoordinate: CLLocationCoordinate2D(
                    latitude: spot.latitude, longitude: spot.longitude
                ),
                distance: 4000
            ))) {
                Annotation("", coordinate: CLLocationCoordinate2D(
                    latitude: spot.latitude, longitude: spot.longitude
                )) {
                    Circle()
                        .fill(CurrentsTheme.accent)
                        .frame(width: 10, height: 10)
                        .shadow(color: CurrentsTheme.accent.opacity(0.6), radius: 6)
                }
            }
            .mapStyle(.hybrid)
            .frame(height: 140)
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Label("\(catchCount) catches", systemImage: "fish.fill")
                        if spot.isPrivate {
                            Label("Private", systemImage: "lock.fill")
                        }
                        Text(spot.createdAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
    }
}
