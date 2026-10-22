import SwiftUI
import CoreLocation

// MARK: - Conditions

/// Conditions on a spot or water page, as Today shows them: four tiles, each
/// saying what the number means for the fishing.
struct ExploreConditions: View {
    let weather: WeatherService.WeatherData?
    var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: DS.Space.s3),
        GridItem(.flexible(), spacing: DS.Space.s3),
    ]

    var body: some View {
        if let w = weather {
            LazyVGrid(columns: columns, spacing: DS.Space.s3) {
                if let water = w.waterTempC {
                    ConditionTile("Water", systemImage: "drop.fill", iconTint: .exploreWater,
                                  value: Units.temperature(water), footnote: Self.waterNote(water))
                } else {
                    ConditionTile("Sky", systemImage: WeatherIcon(condition: w.condition).systemName,
                                  value: "\(w.cloudCoverPct)", unit: "% cloud", footnote: Self.lightNote(w.cloudCoverPct))
                }
                ConditionTile("Air", systemImage: "thermometer.medium",
                              value: Units.temperature(w.temperatureC), footnote: Self.lightNote(w.cloudCoverPct))
                ConditionTile("Wind", systemImage: "wind",
                              value: Units.speed(kmh: w.windSpeedKmh),
                              footnote: Self.windNote(speed: w.windSpeedKmh, from: w.windDirectionDeg))
                ConditionTile("Pressure", systemImage: "gauge.with.dots.needle.33percent",
                              value: "\(Int(w.pressureHpa.rounded()))", unit: "hPa",
                              footnote: Self.pressureNote(w.pressureChange6h))
            }
            .padding(.horizontal, DS.gutter)
        } else if isLoading {
            HStack(spacing: DS.Space.s2) {
                ProgressView()
                Text("Loading conditions")
                    .foregroundStyle(.dsText2)
            }
            .padding(.horizontal, DS.gutter)
        } else {
            Text("No weather yet. It loads next time you are online.")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter)
        }
    }

    static func waterNote(_ c: Double) -> String {
        switch c {
        case ..<10: "Cold. Fish slow and deep."
        case ..<16: "Cool. Slow the retrieve."
        case ..<25: "Prime range for most fish."
        default: "Warm. Fish early and late."
        }
    }

    static func lightNote(_ cloud: Int) -> String {
        if cloud >= 60 { return "Overcast. Fish roam shallower." }
        if cloud <= 25 { return "Bright. Fish hold to cover." }
        return "Broken cloud."
    }

    static func windNote(speed: Double, from degrees: Double) -> String {
        let dir = ExploreFormat.compass(degrees)
        if speed >= 30 { return "From the \(dir). Hard to fish." }
        if speed >= 10 { return "From the \(dir). Fish the windward bank." }
        return "Light, from the \(dir)."
    }

    static func pressureNote(_ change: Double) -> String {
        if change <= -1 { return "Falling. Fish often feed before a front." }
        if change >= 1 { return "Rising. The bite can slow." }
        return "Steady."
    }
}

// MARK: - What to throw

/// The top lure picks for this water right now, from the same engine as
/// Today: water temperature, clarity, light, pressure, your tackle box and
/// what has caught you fish.
struct ExploreThrowSection: View {
    @Environment(AppState.self) private var appState
    let weather: WeatherService.WeatherData?
    let species: Species?
    var limit = 3

    @State private var ownedGear: [OwnedGear] = []
    @State private var history: [CatchDetail] = []

    private var clarity: WaterClarity { WaterClarity.inferred(precipMm: weather?.precipMm) }

    private var picks: [LureEngine.Suggestion] {
        let conditions = LureEngine.Conditions(
            waterTempC: weather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: weather?.cloudCoverPct,
            windSpeedKmh: weather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        return LureEngine.recommend(conditions: conditions, species: species,
                                    ownedGear: ownedGear, history: history, limit: limit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("What to throw", detail: species.map { "for \($0.commonName)" })
            ForEach(picks) { pick in
                pickRow(pick)
            }
            ExploreFootnote(footnote)
        }
        .task {
            ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            history = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []
        }
    }

    private func pickRow(_ pick: LureEngine.Suggestion) -> some View {
        HStack(alignment: .top, spacing: 14) {
            LureArtView(name: pick.lure, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pick.lure)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.dsText)
                    if pick.isOwned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.dsScoreGood)
                            .accessibilityLabel("In your tackle box")
                    }
                }
                Text(pick.color)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                Text(ExploreFormat.sentence(pick.technique))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var footnote: String {
        let temp = weather?.waterTempC.map { "\(Units.temperature($0)) " } ?? ""
        var line = "Picked for \(temp)\(clarity.label.lowercased()) water"
        if let w = weather {
            line += w.pressureChange6h <= -1 ? " and falling pressure" : w.pressureChange6h >= 1 ? " and rising pressure" : " and steady pressure"
        }
        return line + "."
    }
}

// MARK: - Baits

/// A bait the species here take, with who takes it.
struct ExploreBait: Identifiable {
    let name: String
    let takers: [String]
    var id: String { name.lowercased() }
}

/// Bait rows with pictures, best first.
struct ExploreBaitRows: View {
    let baits: [ExploreBait]

    var body: some View {
        ForEach(baits) { bait in
            ArtRow(title: ExploreFormat.sentence(bait.name), subtitle: subtitle(bait)) {
                LureArtView(name: bait.name, size: 56)
            }
        }
    }

    private func subtitle(_ bait: ExploreBait) -> String? {
        guard !bait.takers.isEmpty else { return nil }
        let shown = bait.takers.prefix(2).joined(separator: " and ")
        let extra = bait.takers.count > 2 ? " and \(bait.takers.count - 2) more" : ""
        return "For \(shown)\(extra)"
    }
}

// MARK: - Access and ramps nearby

/// Public fishing access and boat ramps within 5 km, nearest first. Hidden
/// when there are none.
struct ExploreNearbyPlaces: View {
    let coordinate: CLLocationCoordinate2D
    @ObservedObject private var service = BoatRampService.shared
    @State private var selected: BoatRamp?

    private struct Nearby: Identifiable {
        let place: BoatRamp
        let metres: Double
        var id: String { place.id }
    }

    private var nearby: [Nearby] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let all = service.ramps.map {
            Nearby(place: $0, metres: here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon)))
        }
        return Array(all.filter { $0.metres < 5000 }.sorted { $0.metres < $1.metres }.prefix(3))
    }

    var body: some View {
        let list = nearby
        VStack(alignment: .leading, spacing: 0) {
            if !list.isEmpty {
                SectionTitle("Access and ramps")
                ForEach(list) { entry in
                    Button { selected = entry.place } label: {
                        ArtRow(title: entry.place.name,
                               subtitle: "\(entry.place.kind.label), \(Units.distance(m: entry.metres))",
                               chevron: true) {
                            PlaceSnapshotThumb(place: entry.place)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
        .padding(.top, list.isEmpty ? 0 : DS.Space.s8)
        .task {
            // Bundled places load instantly; outside the bundle this waits
            // for the map to have fetched them rather than calling out here.
            let d = 0.05
            if BundledMapData.covers(minLat: coordinate.latitude - d, maxLat: coordinate.latitude + d,
                                     minLon: coordinate.longitude - d, maxLon: coordinate.longitude + d) {
                await service.load(around: coordinate, latSpan: 0.1)
            }
        }
        .sheet(item: $selected) { RampDetailSheet(ramp: $0) }
    }
}
