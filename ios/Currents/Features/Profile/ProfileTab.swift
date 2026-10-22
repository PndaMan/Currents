import SwiftUI
import MapKit
import PhotosUI
import StoreKit
import UniformTypeIdentifiers

/// Pages pushed from Profile and settings.
enum SettingsRoute: Hashable {
    case appearance, units, notifications, privacy, widgets, storage, about, knots, regulations
}

/// Profile and settings, pushed from the avatar at the top of every tab
/// (`AppRoute.profile`). The angler's profile up top, then kit and reference,
/// settings, and support.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    /// Set when a deep link wants a specific screen (gear, licences, …).
    var initialDestination: AppState.MoreDestination? = nil

    @ObservedObject private var community = CommunityService.shared
    @AppStorage("communityName") private var storedName = ""
    @AppStorage("communityHomeWater") private var homeWater = ""
    @AppStorage("communityTitle") private var storedTitle = ""
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = "dark"
    @AppStorage("units") private var units = "metric"
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    @State private var catches: [CatchDetail] = []
    @State private var speciesCount = 0
    @State private var totalSpots = 0
    @State private var gearCount = 0
    @State private var lowStockCount = 0
    @State private var soonestLicence: FishingLicense?
    @State private var licenceCount = 0
    @State private var earnedBadges = 0
    @State private var totalBadges = 0

    @State private var titleShown = false
    @State private var showingEdit = false
    @State private var showingShare = false
    @State private var showingAchievements = false
    /// Programmatic destination pushed by a notification or Live Activity tap.
    @State private var moreDest: AppState.MoreDestination?

    private var displayName: String {
        let trimmed = storedName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Your profile" : trimmed
    }

    private var subtitle: String {
        let flair = TitleFlair.resolve(storedTitle)?.name
        let water = homeWater.trimmingCharacters(in: .whitespaces)
        switch (flair, water.isEmpty) {
        case let (flair?, false): return "\(flair), fishing \(water)"
        case let (flair?, true): return flair
        case (nil, false): return "Fishing \(water)"
        default: return storedName.isEmpty ? "Add your name and home water" : ""
        }
    }

    private var theme: ThemeOption { ThemeOption(rawValue: selectedTheme) ?? .ocean }

    var body: some View {
        List {
            Section {
                header
                    .pfBareRow()
                ActionTriple {
                    Button { showingEdit = true } label: {
                        Label("Edit profile", systemImage: "pencil")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button { showingShare = true } label: {
                        Label("Share card", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ActionTileStyle())
                    NavigationLink(value: AppRoute.gear) {
                        ActionTileLabel("Tackle box", systemImage: "shippingbox")
                    }
                    .buttonStyle(.dim)
                }
                .padding(.bottom, 4)
                .pfBareRow()
            }

            Section("Kit and reference") {
                NavigationLink(value: AppRoute.gear) {
                    PFRowLabel(title: "Tackle box", systemImage: "shippingbox.fill", color: .orange,
                               value: lowStockCount > 0 ? "\(lowStockCount) running low" : "\(gearCount) items",
                               valueColor: lowStockCount > 0 ? .dsScoreLow : .dsText2)
                }
                NavigationLink(value: AppRoute.licenses) {
                    PFRowLabel(title: "Licences", systemImage: "person.text.rectangle.fill", color: .green,
                               value: licenceValue.text, valueColor: licenceValue.color)
                }
                NavigationLink(value: SettingsRoute.knots) {
                    PFRowLabel(title: "Knots and rigs", systemImage: "link", color: .cyan,
                               value: "\(KnotEntry.all.count)")
                }
                NavigationLink(value: SettingsRoute.regulations) {
                    PFRowLabel(title: "Size and bag limits", systemImage: "ruler.fill", color: .purple)
                }
            }
            .pfRows()

            Section("Settings") {
                NavigationLink(value: SettingsRoute.appearance) {
                    PFRowLabel(title: "Appearance", systemImage: "paintpalette.fill", color: theme.primary,
                               value: "\(AppearanceMode(rawValue: appearanceMode)?.title ?? "Dark"), \(theme.displayName)")
                }
                NavigationLink(value: SettingsRoute.units) {
                    PFRowLabel(title: "Units", systemImage: "ruler.fill", color: .orange,
                               value: units == "imperial" ? "Imperial" : "Metric")
                }
                NavigationLink(value: SettingsRoute.notifications) {
                    PFRowLabel(title: "Notifications", systemImage: "bell.badge.fill", color: .red,
                               value: alertsEnabled ? "On" : "Off")
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    PFRowLabel(title: "Privacy", systemImage: "hand.raised.fill", color: .blue)
                }
                NavigationLink(value: SettingsRoute.widgets) {
                    PFRowLabel(title: "Widgets and Siri", systemImage: "square.grid.2x2.fill", color: .indigo)
                }
                NavigationLink(value: SettingsRoute.storage) {
                    PFRowLabel(title: "Offline maps and storage", systemImage: "externaldrive.fill", color: .gray,
                               value: regionsValue)
                }
            }
            .pfRows()

            Section {
                NavigationLink(value: SettingsRoute.about) {
                    PFRowLabel(title: "About Currents", systemImage: "info.circle.fill", color: .teal)
                }
                Button {
                    Haptics.tap()
                    hasOnboarded = false
                } label: {
                    PFRowLabel(title: "Show welcome again", systemImage: "play.fill", color: .green)
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Your logbook lives on this phone. Nothing is shared unless you turn it on.")
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(DS.accent)
        .pfTrackScroll($titleShown, threshold: 160)
        .pfScrollTitle(displayName, shown: titleShown)
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .appearance: AppearanceSettingsView()
            case .units: UnitsSettingsView()
            case .notifications: AlertSettingsView()
            case .privacy: PrivacySettingsView()
            case .widgets: WidgetsSiriView()
            case .storage: StorageSettingsView()
            case .about: AboutView()
            case .knots: KnotLibraryView()
            case .regulations: RegulationsView()
            }
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
        .task { load() }
        .sheet(isPresented: $showingEdit, onDismiss: load) {
            if community.joined {
                ProfileEditView(stats: myStats)
            } else {
                LocalProfileEditSheet()
            }
        }
        .sheet(isPresented: $showingShare) {
            ProfileShareSheet(name: displayName, subtitle: subtitle, avatar: community.myAvatar,
                              catches: catches.count, species: speciesCount, spots: totalSpots)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAchievements) {
            NavigationStack {
                ScrollView {
                    AchievementsCard(catches: catches, topCount: 50)
                        .padding(.horizontal, DS.gutter)
                        .padding(.vertical, DS.Space.s4)
                }
                .dsScreenBackground()
                .navigationTitle("Achievements")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingAchievements = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button { showingEdit = true } label: {
                avatar
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Edit profile")
            .padding(.bottom, DS.Space.s1)

            DetailHeader(title: displayName, subtitle: subtitle)
                .padding(.horizontal, -DS.gutter)

            HStack(spacing: DS.Space.s5) {
                statText(catches.count, "catches")
                statText(speciesCount, "species")
                statText(totalSpots, "spots")
            }
            .font(.callout)

            if totalBadges > 0 {
                Button { showingAchievements = true } label: {
                    VStack(spacing: DS.Space.s2) {
                        HStack {
                            Text("Achievements")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.dsText)
                            Spacer()
                            Text("\(earnedBadges) of \(totalBadges) unlocked")
                                .font(.subheadline)
                                .foregroundStyle(.dsText2)
                                .monospacedDigit()
                        }
                        ProgressView(value: Double(earnedBadges), total: Double(max(totalBadges, 1)))
                            .tint(DS.accent)
                    }
                }
                .buttonStyle(.dim)
                .padding(.top, DS.Space.s2)
                .accessibilityHint("Shows your achievements")
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s4)
    }

    private var avatar: some View {
        let _ = community.revision
        return ZStack {
            Circle().fill(DS.accent)
            if let image = community.myAvatar {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let initial = storedName.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased())
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "figure.fishing")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
    }

    private func statText(_ value: Int, _ label: String) -> some View {
        (Text("\(value)").fontWeight(.semibold).foregroundStyle(Color.dsText)
            + Text(" \(label)").foregroundStyle(Color.dsText2))
            .monospacedDigit()
    }

    // MARK: - Row values

    private var licenceValue: (text: String, color: Color) {
        if let lic = soonestLicence, let days = lic.daysUntilExpiry {
            return (days == 0 ? "Expires today" : (days == 1 ? "1 day left" : "\(days) days left"), .dsScoreLow)
        }
        return (licenceCount == 0 ? "" : "\(licenceCount)", .dsText2)
    }

    private var regionsValue: String {
        let n = appState.mapManager.downloadedRegions.count
        return n == 0 ? "" : (n == 1 ? "1 region" : "\(n) regions")
    }

    private var myStats: CommunityService.MyStats {
        let species = Dictionary(grouping: catches, by: { $0.species?.commonName ?? "" })
        let fav = species.filter { !$0.key.isEmpty }.max { $0.value.count < $1.value.count }?.key ?? ""
        return .init(
            totalCatches: catches.count,
            speciesCount: species.keys.filter { !$0.isEmpty }.count,
            bestWeightKg: catches.compactMap { $0.catchRecord.weightKg }.max() ?? 0,
            bestLengthCm: catches.compactMap { $0.catchRecord.lengthCm }.max() ?? 0,
            favoriteSpecies: fav
        )
    }

    private func load() {
        catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
        speciesCount = ((try? appState.catchRepository.speciesCounts()) ?? []).count
        totalSpots = ((try? appState.spotRepository.fetchAll()) ?? []).count
        let gear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        gearCount = gear.count
        lowStockCount = gear.filter(\.isLowStock).count
        let licences = (try? appState.licenseRepository.fetchAll()) ?? []
        licenceCount = licences.count
        soonestLicence = licences
            .filter { ($0.daysUntilExpiry ?? -1) >= 0 && ($0.daysUntilExpiry ?? 99) <= 30 }
            .min { ($0.daysUntilExpiry ?? 0) < ($1.daysUntilExpiry ?? 0) }
        let streak = BadgeDefinition.streakWeeks(from: catches)
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: streak)
        let visible = badges.filter { !$0.hidden || $0.earned }
        totalBadges = visible.count
        earnedBadges = visible.filter(\.earned).count
    }
}

// MARK: - Local profile editor

/// Edits the name, home water, bio, photo and title on this phone only. Used
/// until the angler joins Crew; after that the Crew profile editor (which also
/// publishes the profile) takes over.
private struct LocalProfileEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var homeWater = ""
    @State private var bio = ""
    @State private var title = ""
    @State private var avatar: UIImage?
    @State private var avatarChanged = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var earnedFlairs: [TitleFlair] = []
    @State private var showingTitlePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: DS.Space.s3) {
                        ZStack {
                            Circle().fill(DS.accent)
                            if let avatar {
                                Image(uiImage: avatar).resizable().scaledToFill()
                            } else {
                                Image(systemName: "figure.fishing")
                                    .font(.title.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            Text("Change photo").font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("About you") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Home water", text: $homeWater)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                }
                .pfRows()
                Section {
                    Button { showingTitlePicker = true } label: {
                        HStack {
                            Text("Title").foregroundStyle(.dsText)
                            Spacer()
                            Text(TitleFlair.resolve(title)?.name ?? "None")
                                .foregroundStyle(.dsText2)
                        }
                    }
                    .disabled(earnedFlairs.isEmpty)
                } footer: {
                    Text(earnedFlairs.isEmpty
                         ? "Titles unlock from achievements."
                         : "Titles unlock from achievements. Only crew and friends see your profile once you join Crew.")
                }
                .pfRows()
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                name = UserDefaults.standard.string(forKey: "communityName") ?? ""
                homeWater = svc.myHomeWater
                bio = svc.myBio
                title = svc.myTitle
                avatar = svc.myAvatar
                let all = (try? appState.catchRepository.fetchAll(limit: 2000)) ?? []
                let streak = BadgeDefinition.streakWeeks(from: all)
                let earned = Set(BadgeDefinition.compute(from: all, streakWeeks: streak)
                    .filter(\.earned).map(\.title))
                earnedFlairs = TitleFlair.all
                    .filter { earned.contains($0.achievement) }
                    .sorted { $0.rarity.rawValue > $1.rarity.rawValue }
                if let current = TitleFlair.resolve(title),
                   !earnedFlairs.contains(where: { $0.id == current.id }) {
                    earnedFlairs.append(current)
                }
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatar = image
                        avatarChanged = true
                    }
                }
            }
            .sheet(isPresented: $showingTitlePicker) {
                TitleFlairPickerSheet(selection: $title, flairs: earnedFlairs)
            }
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(name.trimmingCharacters(in: .whitespaces), forKey: "communityName")
        defaults.set(homeWater.trimmingCharacters(in: .whitespaces), forKey: "communityHomeWater")
        defaults.set(bio, forKey: "communityBio")
        defaults.set(title, forKey: "communityTitle")
        if avatarChanged, let avatar { svc.saveAvatar(avatar) }
        svc.bumpRevision()
        ToastCenter.shared.show("Profile saved")
        dismiss()
    }
}

// MARK: - Share card

/// A picture of the angler's profile to share. No spots or locations on it.
private struct ProfileShareSheet: View {
    let name: String
    let subtitle: String
    let avatar: UIImage?
    let catches: Int
    let species: Int
    let spots: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.s4) {
                card
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                Text("No spots or locations are on the card.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                Spacer()
                if let rendered {
                    let image = Image(uiImage: rendered)
                    ShareLink(item: image, preview: SharePreview(name, image: image)) {
                        Label("Share card", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dsPrimary)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s4)
                } else {
                    ProgressView().padding(.bottom, DS.Space.s4)
                }
            }
            .dsScreenBackground()
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { render() }
        }
    }

    private var card: some View {
        VStack(spacing: DS.Space.s3) {
            ZStack {
                Circle().fill(DS.accent)
                if let avatar {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else if let initial = name.first {
                    Text(String(initial).uppercased())
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            Text(name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: DS.Space.s6) {
                cardStat(catches, "catches")
                cardStat(species, "species")
                cardStat(spots, "spots")
            }
            .padding(.top, DS.Space.s2)
            HStack(spacing: 6) {
                CurrentsMark()
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                Text("Currents")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, DS.Space.s3)
        }
        .padding(.vertical, DS.Space.s8)
        .padding(.horizontal, DS.Space.s6)
        .frame(maxWidth: .infinity)
        .background(DS.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .background(Color.black, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func cardStat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: card.frame(width: 340).environment(\.colorScheme, .dark))
        renderer.scale = displayScale
        rendered = renderer.uiImage
    }
}

// MARK: - Offline maps and storage

/// Offline map regions, the map cache, backups and CSV import and export.
struct StorageSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true

    @State private var mapRegions: [OfflineRegion] = []
    @State private var tileCacheSize = "0 KB"
    @State private var showingSaveRegion = false
    @State private var regionToDelete: OfflineRegion?
    @State private var confirmClearCache = false

    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?
    @State private var showingRestoreConfirm = false
    @State private var lastBackupDate: Date?
    @State private var iCloudAvailable = false
    @State private var dbSize: String?
    @State private var snapshots: [FileBackup.Snapshot] = []
    @State private var restoreSnapshot: FileBackup.Snapshot?
    @State private var showingHistory = false

    @State private var exportURL: URL?
    @State private var showingCSVImport = false
    @State private var importMessage: String?
    @State private var showingImportAlert = false
    @State private var titleShown = false

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Offline maps and storage",
                             subtitle: "Everything you need with no signal.")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            Section {
                if mapRegions.isEmpty {
                    Text("No offline regions. Save one before you head somewhere with no signal.")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                } else {
                    ForEach(mapRegions) { region in
                        HStack(spacing: 14) {
                            ThumbView(systemImage: "map.fill", tint: DS.accent, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(region.name).foregroundStyle(.dsText)
                                Text("\(region.formattedSize), saved \(region.downloadedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.dsText2)
                            }
                            Spacer()
                            Button { regionToDelete = region } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.dsText2)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.dim)
                            .accessibilityLabel("Remove \(region.name)")
                        }
                    }
                }
                Button { showingSaveRegion = true } label: {
                    HStack {
                        Label("Save a map region", systemImage: "plus")
                            .foregroundStyle(.tint)
                        Spacer()
                        if appState.mapManager.isDownloading { ProgressView() }
                    }
                }
                .disabled(appState.mapManager.isDownloading)
            } header: {
                Text("Offline regions")
            } footer: {
                Text("A saved region keeps the satellite map for that area on this phone.")
            }
            .pfRows()

            Section {
                PFToggleRow(title: "Cache maps as I browse",
                            detail: "Keeps satellite tiles around you for no signal",
                            isOn: Binding(get: { appState.mapManager.autoCacheEnabled },
                                          set: { appState.mapManager.autoCacheEnabled = $0 }))
                LabeledContent("Cached tiles", value: tileCacheSize)
                Button("Clear tile cache", role: .destructive) { confirmClearCache = true }
            } header: {
                Text("Map cache")
            }
            .pfRows()

            backupSection

            Section("Data") {
                Button { exportAllData() } label: {
                    PFRowLabel(title: "Export all data", systemImage: "tablecells.fill", color: .green, value: "CSV")
                }
                Button { showingCSVImport = true } label: {
                    PFRowLabel(title: "Import catches", systemImage: "square.and.arrow.down.fill", color: .blue, value: "CSV")
                }
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(.gray)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Storage", shown: titleShown)
        .task { await load() }
        .sheet(isPresented: $showingSaveRegion) {
            SaveRegionSheet { refreshMaps() }
        }
        .sheet(isPresented: $showingHistory) { historySheet }
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
        .confirmationDialog("Remove this region?",
                            isPresented: Binding(get: { regionToDelete != nil },
                                                 set: { if !$0 { regionToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: regionToDelete) { region in
            Button("Remove region", role: .destructive) {
                appState.mapManager.deleteRegion(region)
                Haptics.warning()
                ToastCenter.shared.show("\(region.name) removed", style: .info, haptic: false)
                refreshMaps()
            }
        } message: { region in
            Text("Frees \(region.formattedSize). The map there will need signal until you save it again.")
        }
        .confirmationDialog("Clear the tile cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Remove cached tiles", role: .destructive) {
                Haptics.warning()
                appState.mapManager.clearTileCache()
                refreshMaps()
                ToastCenter.shared.show("Tile cache cleared", style: .info, haptic: false)
            }
        } message: {
            Text("Frees \(tileCacheSize). Saved regions are kept.")
        }
        .alert("Import complete", isPresented: $showingImportAlert) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
        .confirmationDialog("Restore from iCloud?", isPresented: $showingRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { Haptics.warning(); restoreFromCloud() }
        } message: {
            Text("Replaces everything on this phone with the iCloud backup. This cannot be undone.")
        }
        .confirmationDialog("Restore this backup?",
                            isPresented: Binding(get: { restoreSnapshot != nil },
                                                 set: { if !$0 { restoreSnapshot = nil } }),
                            titleVisibility: .visible,
                            presenting: restoreSnapshot) { snap in
            Button("Restore", role: .destructive) {
                Haptics.warning()
                showingHistory = false
                restoreFromSnapshot(snap)
            }
        } message: { snap in
            Text("Replaces everything on this phone with the backup from \(snap.date.formatted(date: .abbreviated, time: .shortened)). This cannot be undone.")
        }
    }

    // MARK: Backups

    private var backupSection: some View {
        Section {
            PFToggleRow(title: "Automatic daily backup",
                        detail: iCloudAvailable ? "On this phone and to iCloud" : "On this phone",
                        isOn: $autoBackupEnabled)

            Button { backUpNow() } label: {
                HStack {
                    Text(isBackingUp ? "Backing up" : "Back up now")
                        .foregroundStyle(.tint)
                    Spacer()
                    if isBackingUp { ProgressView() }
                    else if let dbSize {
                        Text(dbSize).foregroundStyle(.dsText2)
                    }
                }
            }
            .disabled(isBackingUp || isRestoring)

            if let date = lastBackupDate {
                LabeledContent("Last backup") {
                    Text(date, format: .relative(presentation: .named))
                }
            }

            if iCloudAvailable {
                Button { showingRestoreConfirm = true } label: {
                    HStack {
                        Text("Restore from iCloud").foregroundStyle(.dsText)
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isBackingUp || isRestoring)
            }

            if !snapshots.isEmpty {
                Button { showingHistory = true } label: {
                    HStack {
                        Text("Backup history").foregroundStyle(.dsText)
                        Spacer()
                        Text("\(snapshots.count)").foregroundStyle(.dsText2)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                }
            }
        } header: {
            Text("Backups")
        } footer: {
            if let msg = backupMessage {
                Text(msg)
            } else {
                Text(iCloudAvailable
                     ? "Backs up once a day when you leave the app, on this phone and to iCloud. Backups include catches, photos, spots, gear and licences."
                     : "Backs up once a day when you leave the app. Snapshots live in the app's documents, which your phone's own backup includes.")
            }
        }
        .pfRows()
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(snapshots) { snap in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.date.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.dsText)
                                Text(snap.formattedSize)
                                    .font(.subheadline)
                                    .foregroundStyle(.dsText2)
                            }
                            Spacer()
                            Button("Restore") { restoreSnapshot = snap }
                                .buttonStyle(TonalButtonStyle(fullWidth: false))
                                .disabled(isBackingUp || isRestoring)
                        }
                    }
                } footer: {
                    Text("The most recent automatic backups are kept on this phone.")
                }
                .pfRows()
            }
            .pfGroupedList()
            .dsScreenBackground()
            .navigationTitle("Backup history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHistory = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Actions

    private func load() async {
        refreshMaps()
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

    private func refreshMaps() {
        appState.mapManager.refreshDownloadedRegions()
        mapRegions = appState.mapManager.downloadedRegions
        tileCacheSize = ByteCountFormatter.string(
            fromByteCount: appState.mapManager.tileCacheSizeBytes, countStyle: .file)
    }

    private func exportAllData() {
        let exporter = DataExporter(appState: appState)
        exportURL = try? exporter.exportAll()
        if exportURL == nil { ToastCenter.shared.show("Export failed", style: .error) }
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Could not open the selected file."
                showingImportAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let exporter = DataExporter(appState: appState)
                let count = try exporter.importCatches(from: url)
                importMessage = count == 1 ? "Imported 1 catch." : "Imported \(count) catches."
                ToastCenter.shared.show(count == 1 ? "Imported 1 catch" : "Imported \(count) catches")
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Import failed", style: .error)
            }
            showingImportAlert = true
        case .failure(let error):
            importMessage = "Could not read the file: \(error.localizedDescription)"
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
                ToastCenter.shared.show("Backup complete")
            } catch {
                backupMessage = "Backup failed: \(error.localizedDescription)"
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
                backupMessage = "Restored. Restart Currents to see the changes."
                ToastCenter.shared.show("Restored. Restart to see changes")
            } catch {
                backupMessage = "Restore failed: \(error.localizedDescription)"
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
                backupMessage = "Restored. Restart Currents to see the changes."
                ToastCenter.shared.show("Restored. Restart to see changes")
            } catch {
                backupMessage = "Restore failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Restore failed", style: .error)
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
                            .accessibilityHidden(true)
                    }

                Form {
                    Section {
                        TextField("Region name, for example Vaal Dam", text: $regionName)
                    } footer: {
                        Text("Move the map so the area you want is in the frame. The satellite map, about 15 km across, is saved to this phone.")
                    }
                    .pfRows()
                }
                .scrollContentBackground(.hidden)
            }
            .dsScreenBackground()
            .navigationTitle("Save map region")
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
                            ToastCenter.shared.show("\(regionName) saved for offline")
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(regionName.isEmpty || isSaving || centerCoord == nil)
                }
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Units

struct UnitsSettingsView: View {
    @AppStorage("units") private var units = "metric"
    @AppStorage("use24HourTime") private var use24HourTime = true
    @AppStorage("dateOrder") private var dateOrder = "auto"
    @State private var titleShown = false

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Units")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            Section {
                Picker("Measurements", selection: $units) {
                    Text("Metric").tag("metric")
                    Text("Imperial").tag("imperial")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Measurements")
            } footer: {
                Text("A catch shows as \(Units.length(cm: 38, imperial: imperial)), \(Units.weight(kg: 1.2, imperial: imperial)). Water as \(imperial ? "64 °F" : "18 °C").")
            }

            Section {
                PFToggleRow(title: "24-hour time", detail: use24HourTime ? "17:30" : "5:30 PM", isOn: $use24HourTime)
            } header: {
                Text("Time")
            }
            .pfRows()

            Section {
                dateRow("Automatic", detail: Date.now.formatted(date: .numeric, time: .omitted), tag: "auto")
                dateRow("Day, month, year", detail: sample(dayFirst: true), tag: "dayFirst")
                dateRow("Month, day, year", detail: sample(dayFirst: false), tag: "monthFirst")
            } header: {
                Text("Date format")
            } footer: {
                Text("Used when reading dates off scanned licences and permits. Most countries, South Africa included, write the day first; the US writes the month first.")
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(.orange)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Units", shown: titleShown)
        .sensoryFeedback(.selection, trigger: units)
        .sensoryFeedback(.selection, trigger: dateOrder)
    }

    private func sample(dayFirst: Bool) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        let d = String(format: "%02d", c.day ?? 1), m = String(format: "%02d", c.month ?? 1)
        return dayFirst ? "\(d)/\(m)/\(c.year ?? 2026)" : "\(m)/\(d)/\(c.year ?? 2026)"
    }

    private func dateRow(_ title: String, detail: String, tag: String) -> some View {
        Button {
            dateOrder = tag
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.dsText)
                    Text(detail).font(.subheadline).foregroundStyle(.dsText2)
                }
                Spacer()
                if dateOrder == tag {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(dateOrder == tag ? .isSelected : [])
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("privacyRadiusKm") private var privacyRadius = 0.0
    @AppStorage("shareCatchLocations") private var shareCatchLocations = false
    @AppStorage("shareCatchesWithFriends") private var shareCatches = true
    @AppStorage("shareSpotsWithFriends") private var shareSpots = false
    @AppStorage("shareSpotExactLocations") private var shareSpotExact = false
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false
    @State private var titleShown = false

    private var svc: CommunityService { .shared }

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Privacy",
                             subtitle: "Your catches and spots stay on this phone unless you share them.")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            Section {
                PFToggleRow(title: "Share my catches", detail: "Species, size and photo", isOn: $shareCatches)
                PFToggleRow(title: "Share my spots", detail: "Spots stay private until you turn this on", isOn: $shareSpots)
                if shareSpots {
                    PFToggleRow(title: "Exact spot locations", detail: "Off moves shared spots about 4 km", isOn: $shareSpotExact)
                }
                PFToggleRow(title: "Share catch locations", detail: "Off keeps where you caught it private", isOn: $shareCatchLocations)
            } header: {
                Text("Crew and friends")
            } footer: {
                Text("These apply to all your friends. Your best catches always appear on the friends leaderboard.")
            }
            .pfRows()
            .onChange(of: shareCatches) { _, _ in reapplySharing() }
            .onChange(of: shareSpots) { _, _ in reapplySharing() }
            .onChange(of: shareSpotExact) { _, _ in reapplySharing() }

            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack {
                        Text("Move shared pins up to")
                            .foregroundStyle(.dsText)
                        Spacer()
                        Text(privacyRadius == 0 ? "Exact" : "\(Int(privacyRadius)) km")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.dsText)
                    }
                    Slider(value: $privacyRadius, in: 0...20, step: 1)
                        .accessibilityLabel("Honey-hole blur")
                        .accessibilityValue(privacyRadius == 0 ? "Exact" : "\(Int(privacyRadius)) kilometres")
                }
                .padding(.vertical, DS.Space.s1)
                .sensoryFeedback(.selection, trigger: privacyRadius)
            } header: {
                Text("Honey-hole blur")
            } footer: {
                Text("Moves your shared catch locations by up to this distance, so friends never see the exact rock you fished from. Works when Share catch locations is on.")
            }
            .pfRows()

            Section {
                PFToggleRow(title: "Sync across my devices", detail: "Your own private iCloud",
                            systemImage: "icloud.fill", color: .cyan, isOn: $cloudSyncEnabled)
            } header: {
                Text("Sync")
            } footer: {
                Text("Keeps catches and spots in step on your iPhone and iPad through your own iCloud. Nobody else can see it, including the developer.")
            }
            .pfRows()
            .onChange(of: cloudSyncEnabled) { _, on in
                CloudSyncEngine.shared.setEnabled(on)
                ToastCenter.shared.show(on ? "Syncing with your iCloud" : "Sync off. This phone only", style: .info)
            }

            Section {
                NavigationLink(value: SettingsRoute.storage) {
                    PFRowLabel(title: "Export or back up your data", systemImage: "square.and.arrow.up.fill", color: .green)
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Currents works on this phone by default. If you join Crew, only your angler profile, leaderboard catches, friend requests and the spots you choose to share go through Apple's CloudKit, so friends can see them. You can leave Crew at any time.")
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(.blue)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Privacy", shown: titleShown)
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

// MARK: - Widgets and Siri

/// What Currents puts on the Home Screen, Lock Screen and Dynamic Island, and
/// what you can say to Siri.
struct WidgetsSiriView: View {
    @State private var titleShown = false

    private let widgets: [(String, String, String, Color)] = [
        ("Bite score", "The bite forecast where you are, with its verdict", "gauge.with.dots.needle.67percent", .green),
        ("Next session", "Your live or next planned session", "calendar", .blue),
        ("Log a catch", "One tap to the catch log", "plus", .orange),
    ]

    private let shortcuts: [(String, String, String, Color)] = [
        ("Bite score", "What's the bite score in Currents", "cloud.sun.fill", .cyan),
        ("Start session", "Start a fishing session in Currents", "figure.fishing", .green),
        ("End session", "End my fishing session in Currents", "stop.circle.fill", .red),
        ("Log catch", "Log a catch in Currents", "fish.fill", .blue),
        ("Quick catch", "I caught one in Currents", "bolt.fill", .orange),
        ("Log a fish", "Log a fish in Currents", "mic.fill", .purple),
    ]

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Widgets and Siri",
                             subtitle: "Check the bite and log a catch without opening the app.")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            Section {
                ForEach(widgets, id: \.0) { item in
                    infoRow(item)
                }
            } header: {
                Text("Home Screen and Lock Screen")
            } footer: {
                Text("Touch and hold the Home Screen, tap Edit, then Add widget and search for Currents. The bite score also fits the Lock Screen.")
            }
            .pfRows()

            Section {
                infoRow(("Live session", "Timer, catches and the bite on the Lock Screen and in the Dynamic Island", "record.circle", .red))
                infoRow(("Tournaments", "Your points against the leader while a tournament runs", "trophy.fill", .yellow))
            } header: {
                Text("Live Activities")
            } footer: {
                Text("They start on their own when you start a session or join a tournament.")
            }
            .pfRows()

            Section {
                ForEach(shortcuts, id: \.0) { item in
                    HStack(spacing: 14) {
                        PFIcon(systemImage: item.2, color: item.3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).foregroundStyle(.dsText)
                            Text("\u{201C}\(item.1)\u{201D}")
                                .font(.subheadline)
                                .foregroundStyle(.dsText2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let url = URL(string: "shortcuts://") {
                    Link(destination: url) {
                        Text("Open the Shortcuts app").foregroundStyle(.tint)
                    }
                }
            } header: {
                Text("Siri and Shortcuts")
            } footer: {
                Text("Say any of these to Siri, or add them to the Action button in the Shortcuts app.")
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(.indigo)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Widgets and Siri", shown: titleShown)
    }

    private func infoRow(_ item: (String, String, String, Color)) -> some View {
        HStack(spacing: 14) {
            PFIcon(systemImage: item.2, color: item.3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.0).foregroundStyle(.dsText)
                Text(item.1).font(.subheadline).foregroundStyle(.dsText2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var titleShown = false

    private static let koFi = URL(string: "https://ko-fi.com/aidanmcconnon")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: DS.Space.s2) {
                    LogoView(style: .symbol, size: 84)
                    Text("Currents")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.dsText)
                    Text("Fish smarter. Log everything.")
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                    Text(version)
                        .font(.footnote)
                        .foregroundStyle(.dsText3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s4)
                .pfBareRow()
            }

            Section("What it does") {
                feature("Bite forecasts for your exact water", "gauge.with.dots.needle.67percent", .green)
                feature("A catch log that learns what works", "book.fill", .blue)
                feature("Species ID on your phone", "camera.viewfinder", .purple)
                feature("Crews, tournaments and live trips", "person.3.fill", .orange)
                feature("Offline maps with depth", "map.fill", .teal)
                feature("Honey-hole privacy", "hand.raised.fill", .indigo)
            }
            .pfRows()

            Section {
                Link(destination: Self.koFi) {
                    PFRowLabel(title: "Support Currents on Ko-fi", systemImage: "cup.and.saucer.fill", color: .orange)
                }
                Button {
                    requestReview()
                } label: {
                    PFRowLabel(title: "Rate Currents", systemImage: "star.fill", color: .yellow)
                }
                Button {
                    Haptics.tap()
                    hasOnboarded = false
                } label: {
                    PFRowLabel(title: "Show welcome again", systemImage: "play.fill", color: .green)
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Currents is free, with no ads and no account. A coffee helps cover the costs.")
            }
            .pfRows()

            Section("Data sources") {
                LabeledContent("Species", value: "FishBase")
                LabeledContent("Weather", value: "Open-Meteo")
                LabeledContent("Satellite map", value: "Esri World Imagery")
                LabeledContent("Rain radar", value: "RainViewer")
                LabeledContent("Bathymetry", value: "GLOBathy")
            }
            .pfRows()
        }
        .pfGroupedList()
        .detailTint(DS.accent)
        .pfTrackScroll($titleShown, threshold: 140)
        .pfScrollTitle("About", shown: titleShown)
    }

    private func feature(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            PFIcon(systemImage: icon, color: color)
            Text(text).foregroundStyle(.dsText)
        }
    }
}

// MARK: - Appearance mode

/// The angler's light or dark choice (Settings > Appearance). Applied at the
/// app root with `.preferredColorScheme`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// nil follows the phone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
