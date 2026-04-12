import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

struct ProfileTab: View {
    @Environment(AppState.self) private var appState
    @State private var totalCatches = 0
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var mapRegions: [OfflineRegion] = []
    @State private var exportURL: URL?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?
    @State private var showingRestoreConfirm = false
    @State private var lastBackupDate: Date?
    @State private var showingSaveRegion = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        LogoView(style: .horizontal, size: 44)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

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
                Section {
                    Button {
                        showingSaveRegion = true
                    } label: {
                        HStack {
                            Label("Save Map Region", systemImage: "square.and.arrow.down")
                            Spacer()
                            if appState.mapManager.isDownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(appState.mapManager.isDownloading)

                    if mapRegions.isEmpty {
                        Text("No offline regions saved")
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
                        .onDelete { offsets in
                            for i in offsets {
                                appState.mapManager.deleteRegion(mapRegions[i])
                            }
                            mapRegions = appState.mapManager.downloadedRegions
                        }
                    }
                } header: {
                    Text("Offline Maps")
                } footer: {
                    Text("Save satellite snapshots of your fishing areas for offline reference.")
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

                // iCloud Backup
                Section("iCloud Backup") {
                    Button {
                        backupToCloud()
                    } label: {
                        HStack {
                            Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if isBackingUp {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isBackingUp || isRestoring)

                    Button {
                        showingRestoreConfirm = true
                    } label: {
                        HStack {
                            Label("Restore from Backup", systemImage: "icloud.and.arrow.down")
                            Spacer()
                            if isRestoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isBackingUp || isRestoring)

                    if let date = lastBackupDate {
                        HStack {
                            Text("Last backup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let msg = backupMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("Error") ? .red : .green)
                    }
                }

                // Support
                Section {
                    Link(destination: URL(string: "https://buymeacoffee.com/currentsapp")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buy Me a Coffee")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Support Currents development")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Support")
                } footer: {
                    Text("Currents is free and open-source. Tips help cover development costs.")
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
                lastBackupDate = await CloudBackup.shared.lastBackupDate
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(url: url)
            }
            .sheet(isPresented: $showingSaveRegion) {
                SaveRegionSheet {
                    appState.mapManager.refreshDownloadedRegions()
                    mapRegions = appState.mapManager.downloadedRegions
                }
            }
            .alert("Restore from Backup?", isPresented: $showingRestoreConfirm) {
                Button("Restore", role: .destructive) { restoreFromCloud() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace all local data with the iCloud backup. This cannot be undone.")
            }
        }
    }

    private func exportAllData() {
        let exporter = DataExporter(appState: appState)
        exportURL = try? exporter.exportAll()
    }

    private func backupToCloud() {
        isBackingUp = true
        backupMessage = nil
        Task {
            do {
                try await CloudBackup.shared.backup(db: appState.db)
                lastBackupDate = await CloudBackup.shared.lastBackupDate
                backupMessage = "Backup complete"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isBackingUp = false
        }
    }

    private func restoreFromCloud() {
        isRestoring = true
        backupMessage = nil
        Task {
            do {
                try await CloudBackup.shared.restore(db: appState.db)
                backupMessage = "Restore complete — restart app to see changes"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isRestoring = false
        }
    }
}

// MARK: - Save Region Sheet

struct SaveRegionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var regionName = ""
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centerCoord: CLLocationCoordinate2D?
    @State private var isSaving = false
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $cameraPosition)
                    .mapStyle(.hybrid(elevation: .realistic))
                    .mapControls { MapCompass(); MapScaleView() }
                    .frame(height: 300)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        centerCoord = context.camera.centerCoordinate
                    }
                    .overlay {
                        Image(systemName: "viewfinder")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                Form {
                    TextField("Region name (e.g. Vaal Dam)", text: $regionName)
                    if let coord = centerCoord {
                        HStack {
                            Text("Center")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.3f, %.3f", coord.latitude, coord.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Map Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let coord = centerCoord, !regionName.isEmpty else { return }
                        isSaving = true
                        Task {
                            await appState.mapManager.saveRegion(
                                name: regionName,
                                center: coord,
                                spanDegrees: 0.15
                            )
                            onSave()
                            dismiss()
                        }
                    }
                    .disabled(regionName.isEmpty || isSaving)
                }
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
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
                    LogoView(style: .stacked, size: 88, showsTagline: true)
                        .padding(.vertical, 12)
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
