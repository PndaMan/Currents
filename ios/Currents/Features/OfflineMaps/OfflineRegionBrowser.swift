import SwiftUI
import CoreLocation

/// Every country in the world, searchable with its provinces and states.
/// A country opens its regions; a region opens the download sheet.
struct OfflineRegionBrowser: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var countries: [OfflineCountry] = []
    @State private var results: (countries: [OfflineCountry], regions: [OfflineAdminRegion]) = ([], [])
    @State private var here: OfflineAdminRegion?
    @State private var request: OfflineDownloadRequest?

    var body: some View {
        TodayPage("Countries and regions",
                  subtitle: "Every country, province and state, with close-ups around water.") {
            PFSearchField(prompt: "Search countries and provinces", text: $query)
            content
        }
        .scrollDismissesKeyboard(.immediately)
        .task {
            // The bundled list decodes off the main thread the first time.
            let location = appState.locationManager.currentLocation?.coordinate
            let loaded = await Task.detached(priority: .userInitiated) { () -> ([OfflineCountry], OfflineAdminRegion?) in
                (OfflineRegionCatalog.countries, location.flatMap { OfflineRegionCatalog.region(containing: $0) })
            }.value
            countries = loaded.0
            here = loaded.1
        }
        .task(id: query) {
            let text = query
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { results = ([], []); return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) { OfflineRegionCatalog.search(text) }.value
            guard !Task.isCancelled else { return }
            results = found
        }
        .sheet(item: $request) { OfflineDownloadSheet(target: $0.target) }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            if let here {
                CardSection("Where you are") {
                    regionRow(here, showCountry: true)
                    if let country = OfflineRegionCatalog.country(here.countryId) {
                        countryLink(country)
                    }
                }
            }
            if countries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Countries")
                    FishLoader(message: "Loading countries")
                        .frame(minHeight: 90)
                        .frame(maxWidth: .infinity)
                }
            } else {
                CardSection("Countries") {
                    ForEach(countries) { countryLink($0) }
                }
            }
        } else if results.countries.isEmpty && results.regions.isEmpty {
            InlineEmpty(systemImage: "magnifyingglass",
                        text: "Nothing found for \(query). Try another spelling.")
        } else {
            if !results.regions.isEmpty {
                CardSection("Provinces and states") {
                    ForEach(results.regions) { regionRow($0, showCountry: true) }
                }
            }
            if !results.countries.isEmpty {
                CardSection("Countries") {
                    ForEach(results.countries) { countryLink($0) }
                }
            }
        }
    }

    private func countryLink(_ country: OfflineCountry) -> some View {
        NavigationLink(value: OfflineMapsRoute.country(country)) {
            OfflinePlaceRow(title: OfflineRegionCatalog.displayName(country),
                            subtitle: countrySubtitle(country),
                            isDownloaded: isDownloaded(country.id), chevron: true)
        }
        .buttonStyle(.dsCardRow)
    }

    private func regionRow(_ region: OfflineAdminRegion, showCountry: Bool) -> some View {
        Button {
            request = OfflineDownloadRequest(target: .region(region))
        } label: {
            OfflinePlaceRow(title: region.name, subtitle: regionSubtitle(region, showCountry: showCountry),
                            systemImage: "map.fill", tint: .teal,
                            isDownloaded: isDownloaded(region.id))
        }
        .buttonStyle(.dsCardRow)
        .accessibilityHint("Opens the download options")
    }

    private func countrySubtitle(_ c: OfflineCountry) -> String {
        c.regionCount > 1 ? "\(c.regionCount) regions" : OfflineFormat.area(c.areaKm2)
    }

    private func regionSubtitle(_ r: OfflineAdminRegion, showCountry: Bool) -> String {
        let country = showCountry ? OfflineRegionCatalog.country(r.countryId).map(OfflineRegionCatalog.displayName) : nil
        return [OfflineFormat.kind(r), country].compactMap { $0 }.joined(separator: ", ")
    }

    private func isDownloaded(_ id: String) -> Bool {
        appState.mapManager.packs.contains { $0.regionId == id }
    }
}

/// A country's provinces or states, with the whole country first.
struct OfflineCountryView: View {
    let country: OfflineCountry
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var request: OfflineDownloadRequest?

    private var regions: [OfflineAdminRegion] {
        let all = OfflineRegionCatalog.regions(in: country.id)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedStandardContains(q) || ($0.localName?.localizedStandardContains(q) ?? false)
        }
    }

    private var name: String { OfflineRegionCatalog.displayName(country) }

    var body: some View {
        TodayPage(name, subtitle: "\(OfflineFormat.area(country.areaKm2)), \(country.regionCount == 1 ? "1 region" : "\(country.regionCount) regions")") {
            if country.regionCount > 12 {
                PFSearchField(prompt: "Search \(name)", text: $query)
            }
            CardGroup {
                Button {
                    request = OfflineDownloadRequest(target: .country(country))
                } label: {
                    OfflinePlaceRow(title: "All of \(name)",
                                    subtitle: "An overview, with close-ups of its biggest waters",
                                    isDownloaded: isDownloaded(country.id))
                }
                .buttonStyle(.dsCardRow)
                .accessibilityHint("Opens the download options")
            }
            if regions.isEmpty, !query.isEmpty {
                InlineEmpty(systemImage: "magnifyingglass",
                            text: "Nothing in \(name) matches \(query).")
            } else if !regions.isEmpty {
                CardSection(regionsTitle) {
                    ForEach(regions) { region in
                        Button {
                            request = OfflineDownloadRequest(target: .region(region))
                        } label: {
                            OfflinePlaceRow(title: region.name,
                                            subtitle: "\(OfflineFormat.kind(region)), \(OfflineFormat.area(region.areaKm2))",
                                            systemImage: "map.fill", tint: .teal,
                                            isDownloaded: isDownloaded(region.id))
                        }
                        .buttonStyle(.dsCardRow)
                        .accessibilityHint("Opens the download options")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet(item: $request) { OfflineDownloadSheet(target: $0.target) }
    }

    /// "Provinces" when every region is one, otherwise "Regions".
    private var regionsTitle: String {
        let kinds = Set(OfflineRegionCatalog.regions(in: country.id).map { $0.kind.lowercased() })
        if kinds.count == 1, let kind = kinds.first, !kind.isEmpty {
            let plural: String
            if kind.hasSuffix("y") { plural = String(kind.dropLast()) + "ies" }
            else if ["s", "sh", "ch", "x"].contains(where: { kind.hasSuffix($0) }) { plural = kind + "es" }
            else { plural = kind + "s" }
            return plural.prefix(1).uppercased() + plural.dropFirst()
        }
        return "Regions"
    }

    private func isDownloaded(_ id: String) -> Bool {
        appState.mapManager.packs.contains { $0.regionId == id }
    }
}

/// A row in the region lists: an icon tile, name, a detail line, and a
/// tick once downloaded.
struct OfflinePlaceRow: View {
    let title: String
    let subtitle: String
    var systemImage = "globe.europe.africa.fill"
    var tint: Color = .blue
    var isDownloaded = false
    var chevron = false

    var body: some View {
        CardRow(title, subtitle: subtitle, systemImage: systemImage, tint: tint, chevron: chevron) {
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.dsScoreGood)
                    .accessibilityLabel("Downloaded")
            }
        }
    }
}
