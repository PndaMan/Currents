import SwiftUI
import MapKit

/// A saved spot, pushed on the Explore stack: satellite cover, title block
/// with today's bite ring, Plan / Directions / Saved, then the bite by hour,
/// species and catches here, conditions, regulations and the spot itself.
struct SpotDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use24HourTime") private var use24HourTime = true
    @State private var spot: Spot
    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var bite: BiteSnapshot?
    @State private var isSaved = true
    @State private var showingPlan = false
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var confirmingUnsave = false
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingShare = false
    @State private var savedTick = 0

    init(spot: Spot) {
        _spot = State(initialValue: spot)
    }

    private var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    /// Species caught here, most caught first.
    private var speciesHere: [(species: Species, count: Int)] {
        let grouped = Dictionary(grouping: catches.compactMap(\.species), by: \.id)
        return grouped.values
            .compactMap { list in list.first.map { (species: $0, count: list.count) } }
            .sorted { $0.count > $1.count }
    }

    private var tint: Color { speciesHere.first?.species.artTint ?? DS.accent }

    private var overLine: String {
        let type = ExploreFormat.spotType(spot)
        if let d = ExploreFormat.distance(from: appState.locationManager.currentLocation?.coordinate, to: coord) {
            return "\(type), \(d) away"
        }
        return type
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapCover(coordinate: coord, distance: 2500)
                    .padding(.top, DS.Space.s2)

                HStack(alignment: .center, spacing: DS.Space.s3) {
                    DetailHeader(
                        over: overLine,
                        title: spot.name,
                        subtitle: bite.map { "\(ExploreFormat.verdict($0.day)), best \(ExploreFormat.window($0.best, use24Hour: use24HourTime))" }
                    )
                    if let bite {
                        ScoreRing(score: bite.day, size: 88, caption: "today")
                            .padding(.trailing, DS.gutter)
                    }
                }
                .padding(.top, DS.Space.s5)

                ActionTriple {
                    Button { showingPlan = true } label: { Label("Plan a session", systemImage: "calendar.badge.plus") }
                        .buttonStyle(ActionTileStyle(.primary))
                    DirectionsMenu(coordinate: coord, name: spot.name) {
                        ActionTileLabel("Directions", systemImage: "location.north.line")
                    }
                    Button {
                        if isSaved { confirmingUnsave = true } else { resave() }
                    } label: {
                        Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(ActionTileStyle())
                    .symbolEffect(.bounce, value: savedTick)
                }
                .padding(.top, DS.Space.s5)

                if let bite {
                    section {
                        SectionTitle("Bite today")
                        BiteStrip(bite: bite)
                    }
                }

                if !speciesHere.isEmpty {
                    section {
                        SectionTitle("Species here")
                        ForEach(speciesHere, id: \.species.id) { entry in
                            NavigationLink(value: ExploreRoute.species(entry.species)) {
                                ArtRow(title: entry.species.commonName,
                                       subtitle: "\(entry.count) caught here",
                                       chevron: true) {
                                    ThumbView(species: entry.species)
                                }
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                }

                section {
                    SectionTitle("Your catches here", detail: catches.isEmpty ? nil : "\(catches.count)")
                    if catches.isEmpty {
                        ContentUnavailableView {
                            Label("No catches here yet", systemImage: "fish")
                        } description: {
                            Text("Log your first catch at this spot and it shows up here and on the map.")
                        } actions: {
                            Button("Log catch") { AppState.shared?.pendingDeepLink = URL(string: "currents://log") }
                                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                        }
                    } else {
                        catchStats
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            NavigationLink(value: ExploreRoute.catchDetail(CatchRef(detail))) {
                                catchRow(detail)
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                }

                section {
                    SectionTitle("Conditions now")
                    if let weather {
                        KVRow("Air", Units.temperature(weather.temperatureC))
                        if let wt = weather.waterTempC { KVRow("Water", Units.temperature(wt)) }
                        KVRow("Wind", Units.speed(kmh: weather.windSpeedKmh))
                        KVRow("Pressure", pressureText(weather), divider: false)
                        if let reason = bite?.reasons.first {
                            ExploreFootnote(reason)
                        }
                    } else {
                        HStack(spacing: DS.Space.s2) {
                            ProgressView()
                            Text("Loading weather").foregroundStyle(.dsText2)
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                }

                section {
                    SectionTitle("Regulations")
                    NavigationLink(value: ExploreRoute.regulations) {
                        ExploreActionRow(title: "Size and bag limits", systemImage: "ruler", showsDivider: false)
                    }
                    .buttonStyle(.dsRow)
                    ExploreFootnote("Limits come from the bundled regulations. Check before you keep a fish.")
                }

                section {
                    SectionTitle("About this spot")
                    KVRow("Type", ExploreFormat.spotType(spot))
                    KVRow("Location", ExploreFormat.coords(coord))
                    if FeatureFlags.spotPrivacy {
                        KVRow("Visibility", spot.isPrivate ? "Private" : "Shared")
                    }
                    KVRow("Added", spot.createdAt.formatted(.dateTime.day().month(.wide).year()), divider: spot.notes?.isEmpty == false)
                    if let notes = spot.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.dsText)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s3)
                    }
                }

                section {
                    Button { showingEdit = true } label: {
                        ExploreActionRow(title: "Edit spot", systemImage: "pencil")
                    }
                    .buttonStyle(.dsRow)
                    Button { generateShareCard() } label: {
                        ExploreActionRow(title: isGeneratingShare ? "Preparing" : "Share spot", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dsRow)
                    .disabled(isGeneratingShare)
                    Button { confirmingDelete = true } label: {
                        ExploreActionRow(title: "Delete spot", systemImage: "trash", isDestructive: true, chevron: false, showsDivider: false)
                    }
                    .buttonStyle(.dsRow)
                    ExploreFootnote("Spots stay on this phone. Exact locations are never shared unless you share them.")
                }
            }
            .padding(.bottom, 40)
        }
        .detailTint(tint)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { generateShareCard() } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share spot")
                    .disabled(isGeneratingShare)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingPlan) { PlanSessionSheet() }
        .sheet(isPresented: $showingEdit) {
            EditSpotSheet(spot: spot) { updated in
                var record = updated
                try? appState.spotRepository.save(&record)
                ToastCenter.shared.show("Spot updated")
                spot = record
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ImageShareSheet(image: shareImage, filename: "Currents-\(spot.name)",
                                caption: SpotShareCard.caption(for: spot))
            }
        }
        .confirmationDialog("Delete \(spot.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete spot", role: .destructive) {
                try? appState.spotRepository.delete(spot)
                ToastCenter.shared.show("Spot deleted", style: .info, icon: "trash")
                dismiss()
            }
        } message: {
            Text("This removes the spot but keeps any catches you logged here.")
        }
        .confirmationDialog("Remove \(spot.name) from your spots?", isPresented: $confirmingUnsave, titleVisibility: .visible) {
            Button("Remove spot", role: .destructive) { unsave() }
        } message: {
            Text("Catches logged here stay in your Logbook.")
        }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    // MARK: Pieces

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, DS.Space.s8)
    }

    private var catchStats: some View {
        let released = catches.filter { $0.catchRecord.released }.count
        let best = catches.compactMap(\.catchRecord.weightKg).max()
        let species = Set(catches.compactMap { $0.species?.id }).count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatTile("Caught", systemImage: "fish", value: "\(catches.count)",
                         footnote: "\(species) species")
                if let best {
                    let parts = Units.weightParts(kg: best)
                    StatTile("Best", systemImage: "trophy", tint: .dsScoreFair, value: parts.0, unit: parts.1)
                }
                StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreGood,
                         value: "\(Int((Double(released) / Double(max(catches.count, 1)) * 100).rounded()))",
                         unit: "%", footnote: "\(released) of \(catches.count)")
            }
            .padding(.horizontal, DS.gutter)
        }
        .padding(.bottom, DS.Space.s2)
    }

    private func catchRow(_ detail: CatchDetail) -> some View {
        let name = detail.species?.commonName ?? "Catch"
        let length = detail.catchRecord.lengthCm.map { ", \(Units.length(cm: $0))" } ?? ""
        return ArtRow(title: name + length,
                      subtitle: ExploreFormat.shortDate(detail.catchRecord.caughtAt),
                      chevron: true) {
            if let sp = detail.species {
                ThumbView(species: sp)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent)
            }
        }
    }

    private func pressureText(_ w: WeatherService.WeatherData) -> String {
        let base = "\(Int(w.pressureHpa.rounded())) hPa"
        if w.pressureChange6h > 0.5 { return "\(base), rising" }
        if w.pressureChange6h < -0.5 { return "\(base), falling" }
        return "\(base), steady"
    }

    // MARK: Actions

    private func load() async {
        catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
        let (b, w) = await BiteSnapshot.load(at: coord)
        bite = b
        weather = w
    }

    private func unsave() {
        try? appState.spotRepository.delete(spot)
        isSaved = false
        ToastCenter.shared.show("Removed from your spots", style: .info, icon: "bookmark")
    }

    private func resave() {
        var record = spot
        do {
            try appState.spotRepository.save(&record)
            spot = record
            isSaved = true
            savedTick += 1
            ToastCenter.shared.show("\(spot.name) saved", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
        }
    }

    private func generateShareCard() {
        isGeneratingShare = true
        Task {
            let card = await SpotShareCard.render(spot: spot, catchCount: catches.count, biteScore: bite?.now)
            isGeneratingShare = false
            if let card {
                shareImage = card
                showingShareSheet = true
            }
        }
    }
}
