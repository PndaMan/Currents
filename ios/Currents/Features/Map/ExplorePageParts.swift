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
            // Today's tiles: a value and a small picture of where it sits,
            // no sentence under each one. An offline estimate only has a
            // real barometer, so sky, air and wind show the missing mark.
            let m = w.measured
            LazyVGrid(columns: columns, spacing: DS.Space.s3) {
                if let water = m?.waterTempC {
                    ConditionTile("Water", systemImage: "drop.fill", iconTint: ForecastCondition.water.tint,
                                  value: Units.temperature(water)) {
                        visual { RangeBar(domain: 5...32, band: 16...25, value: water, tint: ForecastCondition.water.ink) }
                    }
                } else {
                    ConditionTile("Sky", systemImage: WeatherIcon(condition: m?.condition ?? "").systemName,
                                  iconTint: ForecastCondition.sky.tint,
                                  value: m.map { "\($0.cloudCoverPct)" } ?? ConditionText.missing,
                                  unit: m == nil ? nil : "% cloud") {
                        visual {
                            if let m {
                                RangeBar(domain: 0...100, value: Double(m.cloudCoverPct), tint: ForecastCondition.sky.ink)
                            }
                        }
                    }
                }
                ConditionTile("Air", systemImage: "thermometer.medium", iconTint: ForecastCondition.air.tint,
                              value: m.map { Units.temperature($0.temperatureC) } ?? ConditionText.missing) {
                    visual {
                        if let m {
                            RangeBar(domain: 0...40, value: m.temperatureC, tint: ForecastCondition.air.ink)
                        }
                    }
                }
                ConditionTile("Wind", systemImage: "wind", iconTint: ForecastCondition.wind.tint,
                              value: m.map { Units.speed(kmh: $0.windSpeedKmh) } ?? ConditionText.missing,
                              unit: m.map { ExploreFormat.compass($0.windDirectionDeg) }) {
                    visual {
                        if let m {
                            CompassDial(degrees: m.windDirectionDeg, size: 36)
                        }
                    }
                }
                let pressure = Units.pressureParts(hpa: w.pressureHpa)
                ConditionTile("Pressure", systemImage: "gauge.with.dots.needle.33percent",
                              iconTint: ForecastCondition.pressure.tint,
                              value: pressure.0, unit: pressure.1) {
                    visual {
                        RangeBar(domain: 990...1045, band: ConditionText.pressureSweetSpot,
                                 value: w.pressureHpa, tint: ForecastCondition.pressure.tint)
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
        } else if isLoading {
            FishLoader(message: "Loading conditions")
                .frame(minHeight: 90)
                .frame(maxWidth: .infinity)
        } else {
            InlineEmpty(systemImage: "cloud.sun",
                        text: "No weather yet. It loads next time you are online.")
        }
    }

    /// The picture slot, the same height as Today's, sitting at the foot.
    private func visual<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 36)
            .padding(.top, DS.Space.s3)
            .frame(maxHeight: .infinity, alignment: .bottom)
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

/// The top lure picks for this water at this hour, from the same engine as
/// Today: water temperature, clarity, light, pressure, your tackle box and
/// what has caught you fish. Picked for the fish you track when it belongs
/// here; the menu by the title switches fish while the page is open.
struct ExploreThrowSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    let weather: WeatherService.WeatherData?
    /// Fish caught here, most caught first.
    var caught: [Species] = []
    /// Fish the water is known to hold that have bait records.
    var inWater: [Species] = []
    /// Fresh or salt water; nil when the place does not say.
    var freshwater: Bool? = nil
    var limit = 3

    @State private var ownedGear: [OwnedGear] = []
    @State private var history: [CatchDetail] = []
    @State private var tracked: Species?
    /// The fish picked from the menu. Not saved: next time the page opens
    /// on the fish you track again.
    @State private var chosenId: Int64?

    /// The reading when it is real. An offline estimate only has a real
    /// barometer, so the picks go without the rest, as on Today.
    private var measured: WeatherService.WeatherData? { weather?.measured }

    private var clarity: WaterClarity { WaterClarity.inferred(precipMm: measured?.precipMm) }

    private var choice: ThrowSpeciesChoice {
        ThrowSpeciesChoice(tracked: tracked, caught: caught, inWater: inWater, freshwater: freshwater)
    }

    private func picks(for species: Species?) -> [LureEngine.Suggestion] {
        let conditions = LureEngine.Conditions(
            waterTempC: measured?.waterTempC,
            clarity: clarity,
            cloudCoverPct: measured?.cloudCoverPct,
            windSpeedKmh: measured?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        return LureEngine.recommend(conditions: conditions, species: species,
                                    ownedGear: ownedGear, history: history, limit: limit)
    }

    var body: some View {
        let choice = self.choice
        VStack(alignment: .leading, spacing: 0) {
            ThrowSpeciesTitle(choice: choice, chosenId: $chosenId)
            ForEach(picks(for: choice.species(chosen: chosenId))) { pick in
                pickRow(pick)
            }
            ExploreFootnote(footnote)
        }
        .task {
            ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            history = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []
        }
        .task(id: targetSpeciesId) {
            let id = Int64(targetSpeciesId)
            tracked = id == 0 ? nil : (try? appState.speciesRepository.fetch(id: id)) ?? nil
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
        let temp = measured?.waterTempC.map { "\(Units.temperature($0)) " } ?? ""
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

// MARK: - Ramps and access nearby

/// Public fishing access and boat ramps within 5 km, nearest first. Hidden
/// when there are none. Each opens on the map in its sheet.
struct ExploreNearbyPlaces: View {
    let coordinate: CLLocationCoordinate2D
    @Environment(AppState.self) private var appState
    @ObservedObject private var service = BoatRampService.shared

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
                SectionTitle("Ramps and access")
                ForEach(list) { entry in
                    Button { appState.pendingDeepLink = MapLink.ramp(entry.place) } label: {
                        ArtRow(title: entry.place.name,
                               subtitle: ExploreFormat.rampLine(entry.place, distance: Units.distance(m: entry.metres)),
                               chevron: true) {
                            PlaceSnapshotThumb(place: entry.place)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
        .padding(.top, list.isEmpty ? 0 : DS.Space.s8)
        .placeThumbsTogether()
        .task {
            // Bundled places load instantly; outside the bundle this waits
            // for the map to have fetched them rather than calling out here.
            let d = 0.05
            if BundledMapData.covers(minLat: coordinate.latitude - d, maxLat: coordinate.latitude + d,
                                     minLon: coordinate.longitude - d, maxLon: coordinate.longitude + d) {
                await service.load(around: coordinate, latSpan: 0.1)
            }
        }
    }
}
