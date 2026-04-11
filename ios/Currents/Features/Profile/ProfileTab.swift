import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ProfileTab: View {
    @Environment(AppState.self) private var appState
    @State private var totalCatches = 0
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var mapRegions: [OfflineRegion] = []
    @State private var showingExport = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                // Stats overview
                Section("Stats") {
                    HStack {
                        StatCard(value: "\(totalCatches)", label: "Catches", icon: "fish.fill")
                        StatCard(value: "\(speciesCounts.count)", label: "Species", icon: "leaf.fill")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Species breakdown chart
                if !speciesCounts.isEmpty {
                    Section("Species Breakdown") {
                        Chart(speciesCounts.prefix(8), id: \.speciesId) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Species", item.commonName)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: CGFloat(min(speciesCounts.count, 8)) * 36)
                    }
                }

                // Offline maps
                Section("Offline Maps") {
                    if mapRegions.isEmpty {
                        Text("No offline regions downloaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mapRegions) { region in
                            HStack {
                                Image(systemName: "map.fill")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text(region.name)
                                    Text(region.formattedSize)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(region.downloadedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Browse & Analytics
                Section("Explore") {
                    NavigationLink {
                        AnalyticsView()
                    } label: {
                        Label("Analytics & Personal Bests", systemImage: "chart.xyaxis.line")
                    }

                    NavigationLink {
                        SpotsListView()
                    } label: {
                        Label("My Spots", systemImage: "mappin.circle.fill")
                    }

                    NavigationLink {
                        TripListView()
                    } label: {
                        Label("Trips", systemImage: "tent.fill")
                    }

                    NavigationLink {
                        PhotoGalleryView()
                    } label: {
                        Label("Photo Gallery", systemImage: "photo.on.rectangle.angled")
                    }

                    NavigationLink {
                        SpeciesBrowserView()
                    } label: {
                        Label("Species Guide", systemImage: "fish.fill")
                    }
                }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        UnitsSettingsView()
                    } label: {
                        Label("Units", systemImage: "ruler")
                    }

                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Currents", systemImage: "info.circle")
                    }
                }

                // Data
                Section("Data") {
                    Button {
                        exportAllData()
                    } label: {
                        Label("Export All Data", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                totalCatches = (try? appState.catchRepository.totalCount()) ?? 0
                speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
                appState.mapManager.refreshDownloadedRegions()
                mapRegions = appState.mapManager.downloadedRegions
            }
            .sheet(isPresented: $showingExport) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
        }
    }

    private func exportAllData() {
        let exporter = DataExporter(appState: appState)
        if let url = try? exporter.exportAll() {
            exportURL = url
            showingExport = true
        }
    }
}

// MARK: - Settings Screens

struct UnitsSettingsView: View {
    @AppStorage("units") private var units = "metric"

    var body: some View {
        Form {
            Picker("System", selection: $units) {
                Text("Metric (kg, cm, °C)").tag("metric")
                Text("Imperial (lb, in, °F)").tag("imperial")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Units")
    }
}

struct PrivacySettingsView: View {
    @AppStorage("privacyRadiusKm") private var privacyRadius = 7.0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Honey Hole Obfuscation: \(Int(privacyRadius)) km")
                    Slider(value: $privacyRadius, in: 1...20, step: 1)
                }
            } footer: {
                Text("When you share a catch publicly, the location is randomly offset by this distance to protect your spots.")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("Currents")
                            .font(.title.bold())
                        Text("Offline-First Fishing Companion")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            Section("Features") {
                Label("Fully offline catch logging", systemImage: "wifi.slash")
                Label("On-device fish identification", systemImage: "brain")
                Label("Physics-based bite forecasting", systemImage: "cloud.sun")
                Label("Honey-hole privacy", systemImage: "lock.shield")
                Label("Gear effectiveness tracking", systemImage: "chart.bar")
                Label("Offline maps with bathymetry", systemImage: "map")
            }
        }
        .navigationTitle("About")
    }
}
