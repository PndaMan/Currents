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
    @State private var showingFilePicker = false
    @State private var backupFileURL: URL?
    @State private var iCloudAvailable = false
    @State private var dbSize: String?
    @State private var showingCSVImport = false
    @State private var importMessage: String?
    @State private var showingImportAlert = false

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
                        StatCard(value: "\(totalSpots)", label: "Spots", icon: "mappin.circle.fill")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Badges
                Section("Badges") {
                    BadgesGridView(catches: catches)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal)
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

                // Backup — iCloud when available (App Store), file-based fallback (sideloaded)
                if iCloudAvailable {
                    iCloudBackupSection
                } else {
                    fileBackupSection
                }

                // Support
                Section {
                    Link(destination: URL(string: "https://ko-fi.com/aidanmcconnon")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(.pink)
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
                iCloudAvailable = await CloudBackup.shared.isAvailable
                if iCloudAvailable {
                    lastBackupDate = await CloudBackup.shared.lastBackupDate
                }
                dbSize = await FileBackup.shared.databaseSize

                // Track badge count for new-badge notification
                let streakDays = BadgeDefinition.streakDays(from: catches)
                let allBadges = BadgeDefinition.compute(from: catches, streakDays: streakDays)
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
            .sheet(item: $backupFileURL) { url in
                ShareSheet(url: url)
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    importFromFile(url)
                }
            }
            .overlay(alignment: .top) {
                if showBadgeToast, let title = newBadgeTitle {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
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
            .alert("Restore from Backup?", isPresented: $showingRestoreConfirm) {
                if iCloudAvailable {
                    Button("Restore", role: .destructive) { restoreFromCloud() }
                } else {
                    Button("Choose File", role: .destructive) { showingFilePicker = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if iCloudAvailable {
                    Text("This will replace all local data with the iCloud backup. This cannot be undone.")
                } else {
                    Text("Select a .sqlite backup file to restore. This will replace all local data.")
                }
            }
        }
    }

    // MARK: - iCloud Backup Section (App Store installs)

    private var iCloudBackupSection: some View {
        Section {
            Button {
                backupToCloud()
            } label: {
                HStack {
                    Label("Back Up to iCloud", systemImage: "icloud.and.arrow.up")
                    Spacer()
                    if isBackingUp { ProgressView() }
                }
            }
            .disabled(isBackingUp || isRestoring)

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
        } header: {
            Text("iCloud Backup")
        } footer: {
            Text("Automatically syncs your data across devices via iCloud.")
        }
    }

    // MARK: - File Backup Section (sideloaded IPAs)

    private var fileBackupSection: some View {
        Section {
            Button {
                exportBackupFile()
            } label: {
                HStack {
                    Label("Export Backup", systemImage: "arrow.up.doc")
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

            Button {
                showingRestoreConfirm = true
            } label: {
                HStack {
                    Label("Import Backup", systemImage: "arrow.down.doc")
                    Spacer()
                    if isRestoring { ProgressView() }
                }
            }
            .disabled(isBackingUp || isRestoring)

            if let msg = backupMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.contains("Error") ? .red : .green)
            }
        } header: {
            Text("Backup & Restore")
        } footer: {
            Text("Export your database to Files, AirDrop, or any storage. Import to restore on a new install.")
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

    private func exportBackupFile() {
        isBackingUp = true
        backupMessage = nil
        Task {
            do {
                let url = try await FileBackup.shared.exportBackup(db: appState.db)
                backupFileURL = url
                backupMessage = "Backup exported"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isBackingUp = false
        }
    }

    private func importFromFile(_ url: URL) {
        isRestoring = true
        backupMessage = nil
        Task {
            do {
                try await FileBackup.shared.importBackup(from: url, to: appState.db)
                backupMessage = "Restore complete — restart app to see changes"
            } catch {
                backupMessage = "Error: \(error.localizedDescription)"
            }
            isRestoring = false
        }
    }
}

// MARK: - Document Picker for Import

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType(filenameExtension: "sqlite") ?? .data,
            .database,
            .data,
        ])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
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
