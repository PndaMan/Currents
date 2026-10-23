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
    @State private var titleShown = false

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Countries and regions",
                             subtitle: "Every country, province and state, with close-ups around water.")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
                PFSearchField(prompt: "Search countries and provinces", text: $query)
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                if let here {
                    Section("Where you are") {
                        regionRow(here, showCountry: true)
                        if let country = OfflineRegionCatalog.country(here.countryId) {
                            countryLink(country)
                        }
                    }
                    .pfRows()
                }
                Section("Countries") {
                    if countries.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                    ForEach(countries) { countryLink($0) }
                }
                .pfRows()
            } else if results.countries.isEmpty && results.regions.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                        .pfBareRow()
                }
            } else {
                if !results.regions.isEmpty {
                    Section("Provinces and states") {
                        ForEach(results.regions) { regionRow($0, showCountry: true) }
                    }
                    .pfRows()
                }
                if !results.countries.isEmpty {
                    Section("Countries") {
                        ForEach(results.countries) { countryLink($0) }
                    }
                    .pfRows()
                }
            }
        }
        .pfGroupedList()
        .detailTint(nil)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Countries and regions", shown: titleShown)
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

    private func countryLink(_ country: OfflineCountry) -> some View {
        NavigationLink(value: OfflineMapsRoute.country(country)) {
            OfflinePlaceRow(title: OfflineRegionCatalog.displayName(country),
                            subtitle: countrySubtitle(country),
                            isDownloaded: isDownloaded(country.id))
        }
    }

    private func regionRow(_ region: OfflineAdminRegion, showCountry: Bool) -> some View {
        Button {
            request = OfflineDownloadRequest(target: .region(region))
        } label: {
            OfflinePlaceRow(title: region.name, subtitle: regionSubtitle(region, showCountry: showCountry),
                            isDownloaded: isDownloaded(region.id))
        }
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
    @State private var titleShown = false

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
        List {
            Section {
                DetailHeader(over: "Country", title: name,
                             subtitle: "\(OfflineFormat.area(country.areaKm2)), \(country.regionCount == 1 ? "1 region" : "\(country.regionCount) regions")")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
                if country.regionCount > 12 {
                    PFSearchField(prompt: "Search \(name)", text: $query)
                        .padding(.bottom, DS.Space.s2)
                        .pfBareRow()
                }
            }

            Section {
                Button {
                    request = OfflineDownloadRequest(target: .country(country))
                } label: {
                    OfflinePlaceRow(title: "All of \(name)",
                                    subtitle: "An overview, with close-ups of its biggest waters",
                                    isDownloaded: isDownloaded(country.id))
                }
            }
            .pfRows()

            if regions.isEmpty, !query.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                        .pfBareRow()
                }
            } else if !regions.isEmpty {
                Section(regionsTitle) {
                    ForEach(regions) { region in
                        Button {
                            request = OfflineDownloadRequest(target: .region(region))
                        } label: {
                            OfflinePlaceRow(title: region.name,
                                            subtitle: "\(OfflineFormat.kind(region)), \(OfflineFormat.area(region.areaKm2))",
                                            isDownloaded: isDownloaded(region.id))
                        }
                    }
                }
                .pfRows()
            }
        }
        .pfGroupedList()
        .detailTint(nil)
        .pfTrackScroll($titleShown)
        .pfScrollTitle(name, shown: titleShown)
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

/// A row in the region lists: name, a detail line, and a tick once downloaded.
struct OfflinePlaceRow: View {
    let title: String
    let subtitle: String
    var isDownloaded = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.dsText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.dsScoreGood)
                    .accessibilityLabel("Downloaded")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
