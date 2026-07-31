import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// Everything that used to be dumped in the "More" tab. It's now a sheet
/// behind the gear icon on Today: the things anglers use *while fishing* moved
/// out to the tabs they belong to (spots → Map, sessions & analytics →
/// Catches, species guide & calendar → Fish), leaving genuine settings, kit
/// and reference here.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    /// Set when a deep link wants a specific screen (gear, licences, …).
    var initialDestination: AppState.MoreDestination? = nil
    @State private var totalCatches = 0
    @State private var totalSpots = 0
    @State private var catches: [CatchDetail] = []
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var exportURL: URL?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?
    @State private var showingRestoreConfirm = false
    @State private var lastBackupDate: Date?
    @State private var iCloudAvailable = false
    @State private var dbSize: String?
    @State private var showingCSVImport = false
    @State private var importMessage: String?
    @State private var showingImportAlert = false
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true
    @State private var snapshots: [FileBackup.Snapshot] = []
    @State private var restoreSnapshot: FileBackup.Snapshot?
    /// Programmatic destination pushed by a notification/Live Activity tap.
    @State private var moreDest: AppState.MoreDestination?

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

                // Spots now live on the Map, analytics and sessions on Catches,
                // and the species guide and calendar on Fish — so only the
                // community entry point remains here.
                Section("Community") {
                    NavigationLink { CommunityView() } label: {
                        Label("Community & Friends", systemImage: "person.3.fill")
                    }
                }

                // Your kit and the field reference that goes with it.
                Section("Kit & Reference") {
                    NavigationLink { GearTab() } label: {
                        Label("Gear & Tackle", systemImage: "wrench.and.screwdriver.fill")
                    }
                    NavigationLink { KnotLibraryView() } label: {
                        Label("Knots & Rigs", systemImage: "link")
                    }
                    NavigationLink { RegulationsView() } label: {
                        Label("Size & Bag Limits", systemImage: "ruler")
                    }
                    NavigationLink { LicenseWalletView() } label: {
                        Label("Licences & Permits", systemImage: "doc.text.image")
                    }
                }

                // Settings (Support/Ko-fi now lives inside About).
                Section("Settings") {
                    NavigationLink { AppearanceSettingsView() } label: {
                        Label("Appearance & Icon", systemImage: "paintbrush")
                    }
                    NavigationLink { UnitsSettingsView() } label: {
                        Label("Units", systemImage: "ruler")
                    }
                    NavigationLink { AlertSettingsView() } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    NavigationLink { PrivacySettingsView() } label: {
                        Label("Privacy", systemImage: "lock.shield")
                    }
                    NavigationLink { AboutView() } label: {
                        Label("About & Support", systemImage: "info.circle")
                    }
                }

                // Everything storage-related folded into one screen: offline
                // maps, backup & restore, and CSV import/export.
                Section {
                    NavigationLink {
                        List {
                            Section {
                                NavigationLink { OfflineMapsView() } label: {
                                    Label("Offline Maps", systemImage: "map")
                                }
                            }
                            backupSection
                            Section("Data") {
                                Button { exportAllData() } label: {
                                    Label("Export All Data (CSV)", systemImage: "square.and.arrow.up")
                                }
                                Button { showingCSVImport = true } label: {
                                    Label("Import Data (CSV)", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                        .navigationTitle("Storage & Backups")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Storage & Backups", systemImage: "internaldrive")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $moreDest) { dest in
                switch dest {
                case .community: CommunityView()
                case .gear: GearTab()
                case .licenses: LicenseWalletView()
                case .sessions: SessionsView()
                }
            }
            .onAppear { if moreDest == nil { moreDest = initialDestination } }
            .onChange(of: appState.moreDestination) { _, dest in
                if let dest { moreDest = dest; appState.moreDestination = nil }
            }
            .task {
                catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
                totalCatches = catches.count
                totalSpots = ((try? appState.spotRepository.fetchAll()) ?? []).count
                speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
                iCloudAvailable = await CloudBackup.shared.isAvailable
                if iCloudAvailable {
                    lastBackupDate = await CloudBackup.shared.lastBackupDate
                }
                if let localLast = AutoBackup.lastRun {
                    lastBackupDate = max(lastBackupDate ?? .distantPast, localLast)
                }
                dbSize = await FileBackup.shared.databaseSize
                snapshots = await FileBackup.shared.snapshots()
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(url: url)
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
                Button("Restore", role: .destructive) { Haptics.warning(); restoreFromCloud() }
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
                    Haptics.warning()
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
            .sensoryFeedback(.selection, trigger: autoBackupEnabled)

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
                ToastCenter.shared.show("Imported \(count) catches")
                // Refresh stats
                catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
                totalCatches = catches.count
                speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Import failed", style: .error)
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
                ToastCenter.shared.show("Backup complete")
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
                ToastCenter.shared.show("Backup failed", style: .error)
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
                ToastCenter.shared.show("Restored — restart to see changes")
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
                ToastCenter.shared.show("Restore failed", style: .error)
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
                ToastCenter.shared.show("Restored — restart to see changes")
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
                ToastCenter.shared.show("Restore failed", style: .error)
            }
            isRestoring = false
        }
    }

}

// MARK: - Offline Maps (own screen, kept out of the main Profile list)

struct OfflineMapsView: View {
    @Environment(AppState.self) private var appState
    @State private var mapRegions: [OfflineRegion] = []
    @State private var tileCacheSize = "0 KB"
    @State private var showingSaveRegion = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { appState.mapManager.autoCacheEnabled },
                    set: { appState.mapManager.autoCacheEnabled = $0 }
                )) {
                    Label("Auto-cache maps nearby", systemImage: "square.and.arrow.down.on.square")
                }
                .sensoryFeedback(.selection, trigger: appState.mapManager.autoCacheEnabled)

                HStack {
                    Label("Cached tiles", systemImage: "internaldrive")
                    Spacer()
                    Text(tileCacheSize).font(.caption).foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    Haptics.warning()
                    appState.mapManager.clearTileCache()
                    tileCacheSize = ByteCountFormatter.string(
                        fromByteCount: appState.mapManager.tileCacheSizeBytes, countStyle: .file)
                    ToastCenter.shared.show("Tile cache cleared", style: .info, haptic: false)
                } label: {
                    Label("Clear Tile Cache", systemImage: "trash")
                }

                Button {
                    showingSaveRegion = true
                } label: {
                    HStack {
                        Label("Save Map Snapshot", systemImage: "camera")
                        Spacer()
                        if appState.mapManager.isDownloading { ProgressView() }
                    }
                }
                .disabled(appState.mapManager.isDownloading)
            } footer: {
                Text("With auto-cache on, satellite tiles around you are saved as you browse so the offline map works without signal. Snapshots capture a fixed area as an image.")
            }

            Section("Saved regions") {
                if mapRegions.isEmpty {
                    ContentUnavailableView("No offline regions", systemImage: "square.and.arrow.down",
                        description: Text("Save a snapshot above to use the map without signal."))
                } else {
                    ForEach(mapRegions) { region in
                        HStack {
                            Image(systemName: "map.fill").foregroundStyle(CurrentsTheme.accent)
                            VStack(alignment: .leading) {
                                Text(region.name)
                                Text(region.formattedSize).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(region.downloadedAt, style: .date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { appState.mapManager.deleteRegion(mapRegions[i]) }
                        mapRegions = appState.mapManager.downloadedRegions
                    }
                }
            }
        }
        .navigationTitle("Offline Maps")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .sheet(isPresented: $showingSaveRegion) {
            SaveRegionSheet { refresh() }
        }
    }

    private func refresh() {
        appState.mapManager.refreshDownloadedRegions()
        mapRegions = appState.mapManager.downloadedRegions
        tileCacheSize = ByteCountFormatter.string(
            fromByteCount: appState.mapManager.tileCacheSizeBytes, countStyle: .file)
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
                            ToastCenter.shared.show("Map region saved")
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
    @AppStorage("dateOrder") private var dateOrder = "auto"

    var body: some View {
        Form {
            Section("Measurement System") {
                Picker("System", selection: $units) {
                    Text("Metric (kg, cm, °C, km)").tag("metric")
                    Text("Imperial (lb, in, °F, mi)").tag("imperial")
                }
                .pickerStyle(.inline)
            }

            Section("Time Format") {
                Toggle("24-hour time", isOn: $use24HourTime)
            }

            Section {
                Picker("Date format", selection: $dateOrder) {
                    Text("Automatic (your region)").tag("auto")
                    Text("Day / Month / Year").tag("dayFirst")
                    Text("Month / Day / Year").tag("monthFirst")
                }
            } header: {
                Text("Date Format")
            } footer: {
                Text("Used when reading dates off scanned licences & permits. Most countries (incl. South Africa) use Day/Month/Year; the US uses Month/Day/Year.")
            }
        }
        .navigationTitle("Units")
        .sensoryFeedback(.selection, trigger: units)
        .sensoryFeedback(.selection, trigger: use24HourTime)
        .sensoryFeedback(.selection, trigger: dateOrder)
    }
}

struct PrivacySettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("privacyRadiusKm") private var privacyRadius = 0.0
    @AppStorage("shareCatchLocations") private var shareCatchLocations = false
    @AppStorage("shareCatchesWithFriends") private var shareCatches = true
    @AppStorage("shareSpotsWithFriends") private var shareSpots = false
    @AppStorage("shareSpotExactLocations") private var shareSpotExact = false
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false

    private var svc: CommunityService { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("Share my catches with friends", isOn: $shareCatches)
                Toggle("Share my spots with friends", isOn: $shareSpots)
                if shareSpots {
                    Toggle("Include exact spot locations", isOn: $shareSpotExact)
                }
                Toggle("Share catch locations", isOn: $shareCatchLocations)
            } header: {
                Text("What friends can see")
            } footer: {
                Text("These apply to all your friends. Catch bests always appear on the friends leaderboard; everything here is off unless you turn it on (catches default on). Spots stay private unless shared, and exact GPS stays off unless you allow it.")
            }
            .onChange(of: shareCatches) { _, _ in reapplySharing() }
            .onChange(of: shareSpots) { _, _ in reapplySharing() }
            .onChange(of: shareSpotExact) { _, _ in reapplySharing() }

            Section {
                VStack(alignment: .leading) {
                    Text(privacyRadius == 0
                         ? "Honey-Hole Obfuscation: off (exact)"
                         : "Honey-Hole Obfuscation: \(Int(privacyRadius)) km")
                    Slider(value: $privacyRadius, in: 0...20, step: 1)
                }
            } header: {
                Text("Catch location privacy")
            } footer: {
                Text("Controls how far your shared catch locations are randomly offset. At 0 km the exact location is shared; increase it to fuzz where you were fishing. Only takes effect when “Share catch locations” is on. (Shared spots always get at least ~4 km of fuzz when you don't share exact GPS.)")
            }

            Section {
                Toggle("Sync across my devices", isOn: $cloudSyncEnabled)
            } header: {
                Text("iCloud sync")
            } footer: {
                Text("Keep your catches and spots in sync across your iPhone and iPad using your own private iCloud account. This uses Apple's iCloud — the developer never sees your data — and is separate from the Community. Off by default.")
            }
            .sensoryFeedback(.selection, trigger: cloudSyncEnabled)
            .onChange(of: cloudSyncEnabled) { _, on in
                CloudSyncEngine.shared.setEnabled(on)
                ToastCenter.shared.show(on ? "iCloud sync on" : "iCloud sync off", style: .info)
            }

            Section {
                EmptyView()
            } header: {
                Text("Data & the Community")
            } footer: {
                Text("Currents is on-device by default — your catches, spots, and photos stay on your phone. Optional iCloud sync (above) keeps them across your own devices via your private iCloud, which the developer can't access. If you opt into the Community, a limited set of data (leaderboard catches, your angler profile, friend requests, and spots you explicitly share) syncs through Apple's CloudKit so friends can see it. You can leave the Community at any time.")
            }
        }
        .navigationTitle("Privacy")
        .sensoryFeedback(.selection, trigger: shareCatches)
        .sensoryFeedback(.selection, trigger: shareSpots)
        .sensoryFeedback(.selection, trigger: shareSpotExact)
        .sensoryFeedback(.selection, trigger: shareCatchLocations)
    }

    /// Re-apply the global sharing preferences to CloudKit (grants + shared spots).
    private func reapplySharing() {
        Task {
            await svc.syncCatchGrants()
            let spots = (try? appState.spotRepository.fetchAll()) ?? []
            await svc.republishSharedSpots(spots: spots)
        }
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
                Label("On-device catch logging", systemImage: "iphone")
                Label("On-device fish identification", systemImage: "brain")
                Label("Physics-based bite forecasting", systemImage: "cloud.sun")
                Label("Honey-hole privacy", systemImage: "lock.shield")
                Label("Optional community & leaderboards", systemImage: "person.2")
                Label("Gear effectiveness tracking", systemImage: "chart.bar")
                Label("Offline maps with bathymetry", systemImage: "map")
            }

            Section {
                Link(destination: URL(string: "https://ko-fi.com/aidanmcconnon")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill").font(.title3).foregroundStyle(CurrentsTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Support Currents").font(.subheadline.bold()).foregroundStyle(.primary)
                            Text("Buy me a coffee on Ko-fi").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Currents is free and open-source. Tips help cover development costs.")
            }
        }
        .navigationTitle("About")
    }
}
