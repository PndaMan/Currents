import SwiftUI
import CoreLocation

// MARK: - Conditions

/// Conditions on a spot or water page, as Today shows them: four tiles, two
/// to a row and one height per row (one to a row at accessibility sizes),
/// each with a value, a small picture of where it sits and a line on what it
/// means for the fishing. The water band is the comfort range of the fish
/// you track, as on Today. The tiles do not open Today's condition pages,
/// which are about where you are, not this place.
struct ExploreConditions: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("units") private var units = "metric"
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @ScaledMetric(relativeTo: .body) private var visualHeight: CGFloat = 36
    let weather: WeatherService.WeatherData?
    var isLoading = false
    @State private var target: Species?

    var body: some View {
        Group {
            if let w = weather {
                grid(w)
            } else if isLoading {
                FishLoader(message: "Loading conditions")
                    .frame(minHeight: 90)
                    .frame(maxWidth: .infinity)
            } else {
                InlineEmpty(systemImage: "cloud.sun",
                            text: "No weather yet. It loads next time you are online.")
            }
        }
        .task(id: targetSpeciesId) {
            let id = Int64(targetSpeciesId)
            target = id == 0 ? nil : (try? appState.speciesRepository.fetch(id: id)) ?? nil
        }
    }

    private func grid(_ w: WeatherService.WeatherData) -> some View {
        // An offline estimate only has a real barometer, so water, sky, air
        // and wind show the missing mark and say so.
        let m = w.measured
        let imperial = units == "imperial"
        let none = "No weather offline"
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return VStack(spacing: 10) {
            pair {
                if let water = m?.waterTempC {
                    ConditionTile("Water", systemImage: "thermometer.medium", iconTint: ForecastCondition.water.tint,
                                  value: ConditionText.temperature(water, imperial: imperial),
                                  footnote: ConditionText.waterMeaning(water, species: target)) {
                        visual {
                            RangeBar(domain: 5...32, band: ConditionText.comfort(for: target),
                                     value: water, tint: ForecastCondition.water.tint)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ConditionTile("Sky", systemImage: WeatherIcon(condition: m?.condition ?? "").systemName,
                                  iconTint: ForecastCondition.sky.tint,
                                  value: m.map { "\($0.cloudCoverPct)" } ?? ConditionText.missing,
                                  unit: "% cloud",
                                  footnote: m.map { Self.skyMeaning($0) } ?? none) {
                        visual {
                            if let m {
                                RangeBar(domain: 0...100, value: Double(m.cloudCoverPct), tint: ForecastCondition.sky.tint)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                ConditionTile("Air", systemImage: "thermometer.sun", iconTint: ForecastCondition.air.tint,
                              value: ConditionText.temperature(m?.temperatureC, imperial: imperial),
                              footnote: m.map { ForecastFormat.condition($0.condition) } ?? none) {
                    visual {
                        if let m {
                            RangeBar(domain: 0...40, value: m.temperatureC, tint: ForecastCondition.air.tint)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            pair {
                let speed = ConditionText.speedParts(m?.windSpeedKmh, imperial: imperial)
                ConditionTile("Wind", systemImage: "wind", iconTint: ForecastCondition.wind.tint,
                              value: speed.value,
                              unit: m.map { speed.unit + " " + ForecastFormat.compass($0.windDirectionDeg) } ?? speed.unit,
                              footnote: m.map { ConditionText.windMeaning($0.windSpeedKmh) } ?? none) {
                    visual {
                        if let m {
                            CompassDial(degrees: m.windDirectionDeg, size: 36, tint: ForecastCondition.wind.ink)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                let pressure = Units.pressureParts(hpa: w.pressureHpa, imperial: imperial)
                ConditionTile("Pressure", systemImage: "gauge.with.dots.needle.33percent",
                              iconTint: ForecastCondition.pressure.tint,
                              value: pressure.0, unit: pressure.1,
                              footnote: ConditionText.pressureMeaning(w)) {
                    visual {
                        RangeBar(domain: 990...1045, band: ConditionText.pressureSweetSpot,
                                 value: w.pressureHpa, tint: ForecastCondition.pressure.tint)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.gutter)
    }

    /// The picture slot, Today's height, sitting just above the line of meaning.
    private func visual<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: visualHeight, alignment: .center)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Today's sky line, from the reading alone (there is no hourly here).
    private static func skyMeaning(_ w: WeatherService.WeatherData) -> String {
        if w.precipMm >= 5 { return "Heavy rain. Water will colour" }
        if w.cloudCoverPct >= 70 { return "Overcast. Fish roam and feed longer" }
        if w.cloudCoverPct <= 25 { return "Bright. Fish hold deep or in shade" }
        return "Some cloud. Good light for fishing"
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
        let species = choice.species(chosen: chosenId)
        VStack(alignment: .leading, spacing: 0) {
            ThrowSpeciesTitle(choice: choice, chosenId: $chosenId)
            ForEach(picks(for: species)) { pick in
                pickRow(pick)
            }
            // A fish caught only on bait has one pick; say why.
            ExploreFootnote(ThrowText.baitOnlyNote(species).map { "\(footnote) \($0)" } ?? footnote)
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
                Text(pick.lure)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                // A lure's colour; bait has none, so its line names the
                // fish's own baits when the record has them.
                if let line = pick.color.isEmpty ? pick.baitLine : Optional(pick.color) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ExploreFormat.sentence(pick.technique))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                // The seal says what it means, rather than leaving it to VoiceOver.
                if pick.isOwned {
                    Label("In your tackle box", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .labelStyle(TintedIconLabelStyle(tint: DS.ink(.dsScoreGood)))
                        .padding(.top, 2)
                }
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
                               subtitle: ExploreFormat.rampLine(entry.place, distance: Units.distance(m: entry.metres),
                                                                side: service.side(of: entry.place)),
                               chevron: true) {
                            ThumbView(place: entry.place)
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
    }
}
