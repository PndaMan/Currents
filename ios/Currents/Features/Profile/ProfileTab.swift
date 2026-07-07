import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ProfileTab: View {
    @Environment(AppState.self) private var appState
    @State private var totalCatches = 0
    @State private var totalSpots = 0
    @State private var catches: [CatchDetail] = []
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var mapRegions: [OfflineRegion] = []
    @State private var previousBadgeCount = 0
    @State private var newBadgeTitle: String?
    @State private var showBadgeToast = false
    @State private var exportURL: URL?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?
    @State private var showingRestoreConfirm = false
    @State private var lastBackupDate: Date?
    @State private var showingSaveRegion = false
    @State private var iCloudAvailable = false
    @State private var dbSize: String?
    @State private var showingCSVImport = false
    @State private var importMessage: String?
    @State private var showingImportAlert = false
    @State private var tileCacheSize = "0 KB"
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true
    @State private var snapshots: [FileBackup.Snapshot] = []
    @State private var restoreSnapshot: FileBackup.Snapshot?

    var body: some View {
        NavigationStack {
            List {
                // Stats overview
                Section("Stats") {
                    HStack {
                        StatCard(value: "\(totalCatches)", label: "Catches", icon: "fish.fill")
                        StatCard(value: "\(speciesCounts.count)", label: "Species", icon: "leaf.fill")
                        StatCard(value: "\(totalSpots)", label: "Spots", icon: "mappin.circle.fill")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Offline maps
                Section {
                    Toggle(isOn: Binding(
                        get: { appState.mapManager.autoCacheEnabled },
                        set: { appState.mapManager.autoCacheEnabled = $0 }
                    )) {
                        Label("Auto-cache maps nearby", systemImage: "square.and.arrow.down.on.square")
                    }

                    HStack {
                        Label("Cached tiles", systemImage: "internaldrive")
                        Spacer()
                        Text(tileCacheSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        appState.mapManager.clearTileCache()
                        tileCacheSize = ByteCountFormatter.string(
                            fromByteCount: appState.mapManager.tileCacheSizeBytes, countStyle: .file
                        )
                    } label: {
                        Label("Clear Tile Cache", systemImage: "trash")
                    }

                    Button {
                        showingSaveRegion = true
                    } label: {
                        HStack {
                            Label("Save Map Snapshot", systemImage: "camera")
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
                                    .foregroundStyle(CurrentsTheme.accent)
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
                    Text("With auto-cache on, satellite tiles around you are saved as you browse so the offline map works without signal. Snapshots capture a fixed area as an image.")
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

                    if FeatureFlags.liveTrips {
                        NavigationLink {
                            TripListView()
                        } label: {
                            Label("Trips", systemImage: "tent.fill")
                        }
                    }

                    NavigationLink {
                        SeasonalCalendarView()
                    } label: {
                        Label("Seasonal Calendar", systemImage: "calendar")
                    }

                    NavigationLink {
                        SpeciesBrowserView()
                    } label: {
                        Label("Species Guide", systemImage: "fish.fill")
                    }

                    NavigationLink {
                        GearTab()
                    } label: {
                        Label("Gear & Tackle", systemImage: "wrench.and.screwdriver.fill")
                    }

                    NavigationLink {
                        KnotLibraryView()
                    } label: {
                        Label("Knots & Rigs", systemImage: "link")
                    }

                    NavigationLink {
                        RegulationsView()
                    } label: {
                        Label("Size & Bag Limits", systemImage: "ruler")
                    }
                }

                // Settings
                Section("Settings") {
                    DisclosureGroup {
                        BadgesGridView(catches: catches)
                            .padding(.vertical, 8)
                    } label: {
                        Label("Achievements & Badges", systemImage: "trophy")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                    NavigationLink {
                        AppIconSelectorView()
                    } label: {
                        Label("App Icon", systemImage: "app.badge")
                    }

                    NavigationLink {
                        UnitsSettingsView()
                    } label: {
                        Label("Units", systemImage: "ruler")
                    }

                    NavigationLink {
                        AlertSettingsView()
                    } label: {
                        Label("Bite Alerts", systemImage: "bell.badge")
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

                // Backup — automatic daily snapshot + iCloud when the
                // entitlement/account allow it.
                backupSection

                // Support
                Section {
                    Link(destination: URL(string: "https://ko-fi.com/aidanmcconnon")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(CurrentsTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Support Currents")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Buy me a coffee on Ko-fi")
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
                        Label("Export All Data (CSV)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingCSVImport = true
                    } label: {
                        Label("Import Data (CSV)", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
                totalCatches = catches.count
                totalSpots = ((try? appState.spotRepository.fetchAll()) ?? []).count
                speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
                appState.mapManager.refreshDownloadedRegions()
                mapRegions = appState.mapManager.downloadedRegions
                tileCacheSize = ByteCountFormatter.string(
                    fromByteCount: appState.mapManager.tileCacheSizeBytes, countStyle: .file
                )
                iCloudAvailable = await CloudBackup.shared.isAvailable
                if iCloudAvailable {
                    lastBackupDate = await CloudBackup.shared.lastBackupDate
                }
                if let localLast = AutoBackup.lastRun {
                    lastBackupDate = max(lastBackupDate ?? .distantPast, localLast)
                }
                dbSize = await FileBackup.shared.databaseSize
                snapshots = await FileBackup.shared.snapshots()

                // Track badge count for new-badge notification
                let streakWeeks = BadgeDefinition.streakWeeks(from: catches)
                let allBadges = BadgeDefinition.compute(from: catches, streakWeeks: streakWeeks)
                let earnedCount = allBadges.filter(\.earned).count
                if previousBadgeCount > 0 && earnedCount > previousBadgeCount {
                    // A new badge was earned
                    if let newest = allBadges.filter(\.earned).last {
                        newBadgeTitle = newest.title
                        showBadgeToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { showBadgeToast = false }
                        }
                    }
                }
                previousBadgeCount = earnedCount
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
            .overlay(alignment: .top) {
                if showBadgeToast, let title = newBadgeTitle {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.title3)
                            .foregroundStyle(CurrentsTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Badge Earned!")
                                .font(.caption.bold())
                            Text(title)
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: showBadgeToast)
                    .onTapGesture {
                        withAnimation { showBadgeToast = false }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingCSVImport,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result)
            }
            .alert("Import Complete", isPresented: $showingImportAlert) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
            .alert("Restore from iCloud?", isPresented: $showingRestoreConfirm) {
                Button("Restore", role: .destructive) { restoreFromCloud() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace all local data with the iCloud backup. This cannot be undone.")
            }
            .alert(
                "Restore this backup?",
                isPresented: Binding(
                    get: { restoreSnapshot != nil },
                    set: { if !$0 { restoreSnapshot = nil } }
                )
            ) {
                Button("Restore", role: .destructive) {
                    if let snap = restoreSnapshot {
                        restoreFromSnapshot(snap)
                    }
                }
                Button("Cancel", role: .cancel) { restoreSnapshot = nil }
            } message: {
                Text("This will replace all current data with the automatic backup from \(restoreSnapshot?.date.formatted(date: .abbreviated, time: .shortened) ?? "this date"). This cannot be undone.")
            }
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        Section {
            Toggle(isOn: $autoBackupEnabled) {
                Label("Automatic Daily Backup", systemImage: "clock.arrow.circlepath")
            }

            Button {
                backUpNow()
            } label: {
                HStack {
                    Label("Back Up Now", systemImage: iCloudAvailable ? "icloud.and.arrow.up" : "arrow.triangle.2.circlepath")
                    Spacer()
                    if let dbSize {
                        Text(dbSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isBackingUp { ProgressView() }
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

            if iCloudAvailable {
                Button {
                    showingRestoreConfirm = true
                } label: {
                    HStack {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isBackingUp || isRestoring)
            }

            if !snapshots.isEmpty {
                DisclosureGroup("Backup History (\(snapshots.count))") {
                    ForEach(snapshots) { snap in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                Text(snap.formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                restoreSnapshot = snap
                            }
                            .font(.caption.bold())
                            .disabled(isBackingUp || isRestoring)
                        }
                    }
                }
            }

            if let msg = backupMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.contains("Error") ? .secondary : CurrentsTheme.accent)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(iCloudAvailable
                 ? "Backs up automatically once a day (locally and to iCloud) when you leave the app."
                 : "Backs up automatically once a day when you leave the app. The snapshots live in the app's documents, which are included in your device's own iCloud/computer backup. Use Export All Data (CSV) below to take your data elsewhere.")
        }
    }

    // MARK: - Helpers


    // MARK: - Actions

    private func exportAllData() {
        let exporter = DataExporter(appState: appState)
        exportURL = try? exporter.exportAll()
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Could not access the selected file."
                showingImportAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let exporter = DataExporter(appState: appState)
                let count = try exporter.importCatches(from: url)
                importMessage = "Successfully imported \(count) catches."
                // Refresh stats
                catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
                totalCatches = catches.count
                speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
            showingImportAlert = true

        case .failure(let error):
            importMessage = "Could not read file: \(error.localizedDescription)"
            showingImportAlert = true
        }
    }

    /// Manual backup: always writes a local snapshot; also pushes to the
    /// iCloud container when available.
    private func backUpNow() {
        isBackingUp = true
        backupMessage = nil
        Task {
            do {
                try await FileBackup.shared.writeSnapshot(db: appState.db)
                if iCloudAvailable {
                    try await CloudBackup.shared.backup(db: appState.db)
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAutoBackupAt")
                lastBackupDate = .now
                snapshots = await FileBackup.shared.snapshots()
                backupMessage = "Backup complete"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isBackingUp = false
        }
    }

    private func restoreFromSnapshot(_ snapshot: FileBackup.Snapshot) {
        isRestoring = true
        backupMessage = nil
        Task {
            do {
                try await FileBackup.shared.importBackup(from: snapshot.url, to: appState.db)
                backupMessage = "Restore complete — restart app to see changes"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isRestoring = false
            restoreSnapshot = nil
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
    @AppStorage("use24HourTime") private var use24HourTime = true

    var body: some View {
        Form {
            Picker("System", selection: $units) {
                Text("Metric (kg, cm, °C)").tag("metric")
                Text("Imperial (lb, in, °F)").tag("imperial")
            }
            .pickerStyle(.inline)

            Section("Time Format") {
                Toggle("24-hour time", isOn: $use24HourTime)
            }
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
