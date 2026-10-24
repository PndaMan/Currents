import SwiftUI
import MapKit
import PhotosUI
import StoreKit
import UniformTypeIdentifiers
import Charts

/// Pages pushed from Profile and settings.
enum SettingsRoute: Hashable {
    case appearance, units, notifications, privacy, widgets, offlineMaps, storage, about, knots, regulations
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

    /// The subtitle under your name here. The title has its own badge below,
    /// so only the home water shows.
    private var headerSubtitle: String {
        guard TitleFlair.resolve(storedTitle) != nil else { return subtitle }
        let water = homeWater.trimmingCharacters(in: .whitespaces)
        return water.isEmpty ? "" : "Fishing \(water)"
    }

    private var theme: ThemeOption { ThemeOption(rawValue: selectedTheme) ?? .ocean }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    profileActions
                }
                GameCenterSection()
                kitSection
                settingsSection
                CardSection {
                    row(SettingsRoute.about, "About Currents", "info.circle.fill", .teal,
                        value: AboutView.shortVersion)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 160)
        .pfScrollTitle(displayName, shown: titleShown)
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .appearance: AppearanceSettingsView()
            case .units: UnitsSettingsView()
            case .notifications: AlertSettingsView()
            case .privacy: PrivacySettingsView()
            case .widgets: WidgetsSiriView()
            case .offlineMaps: OfflineMapsView()
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
    }

    // MARK: - Sections

    private var profileActions: some View {
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
    }

    private var kitSection: some View {
        CardSection("Kit and reference") {
            row(AppRoute.gear, "Tackle box", "shippingbox.fill", .orange,
                value: lowStockCount > 0 ? "\(lowStockCount) running low" : "\(gearCount) items",
                valueTint: lowStockCount > 0 ? .dsScoreLow : .dsText2)
            row(AppRoute.licenses, "Licences", "person.text.rectangle.fill", .green,
                value: licenceValue.text, valueTint: licenceValue.color)
            row(SettingsRoute.knots, "Knots and rigs", "link", .cyan,
                value: "\(KnotCatalog.shared.entries.count)")
            row(SettingsRoute.regulations, "Size and bag limits", "list.bullet.clipboard.fill", .purple)
        }
    }

    private var settingsSection: some View {
        CardSection("Settings") {
            row(SettingsRoute.appearance, "Appearance", "paintpalette.fill", theme.primary,
                value: AppearanceMode(rawValue: appearanceMode)?.title ?? "Dark")
            row(SettingsRoute.units, "Units", "ruler.fill", .orange,
                value: units == "imperial" ? "Imperial" : "Metric")
            row(SettingsRoute.notifications, "Notifications", "bell.badge.fill", .red,
                value: alertsEnabled ? "On" : "Off")
            row(SettingsRoute.privacy, "Privacy", "hand.raised.fill", .blue)
            row(SettingsRoute.widgets, "Widgets and Siri", "square.grid.2x2.fill", .indigo)
            row(SettingsRoute.offlineMaps, "Offline maps", "map.fill", .green, value: regionsValue)
            row(SettingsRoute.storage, "Storage and backups", "externaldrive.fill", .mint)
        }
    }

    /// One navigation row on a settings card.
    private func row<Route: Hashable>(_ route: Route, _ title: String, _ systemImage: String, _ tint: Color,
                                      value: String? = nil, valueTint: Color = .dsText2) -> some View {
        NavigationLink(value: route) {
            CardRow(title, systemImage: systemImage, tint: tint, value: value, valueTint: valueTint, chevron: true)
        }
        .buttonStyle(.dsCardRow)
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

            DetailHeader(title: displayName, subtitle: headerSubtitle)
                .padding(.horizontal, -DS.gutter)

            if TitleFlair.resolve(storedTitle) != nil {
                TitleFlairChip(title: storedTitle)
            }

            HStack(spacing: DS.Space.s5) {
                statText(catches.count, "catches")
                statText(speciesCount, "species")
                statText(totalSpots, "spots")
            }
            .font(.callout)

            if totalBadges > 0 {
                NavigationLink {
                    AchievementsView(catches: catches)
                } label: {
                    VStack(spacing: DS.Space.s2) {
                        HStack {
                            Text("Achievements")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.dsText)
                            Spacer()
                            Text("\(earnedBadges) of \(totalBadges) earned")
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
                .accessibilityHint("Opens your achievements")
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
        let manager = appState.mapManager
        if manager.isDownloading { return "Downloading" }
        let n = manager.downloadedRegions.count
        return n == 0 ? "" : (n == 1 ? "1 map" : "\(n) maps")
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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                photoSection
                aboutSection
                bioSection
                titleSection
            }
            .gearFormStyle()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(trimmedName.isEmpty)
                }
            }
            .task { load() }
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

    private var photoSection: some View {
        Section {
            HStack(spacing: DS.Space.s4) {
                avatarImage
                Text("Photo")
                    .foregroundStyle(.dsText)
                Spacer(minLength: DS.Space.s2)
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Text(avatar == nil ? "Choose" : "Change")
                }
            }
        }
        .pfRows()
    }

    private var avatarImage: some View {
        ZStack {
            Circle().fill(DS.accent)
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                Image(systemName: "figure.fishing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var aboutSection: some View {
        Section {
            GearFormField("Name", text: $name, prompt: "Your name")
                .textContentType(.name)
            GearFormField("Home water", text: $homeWater, prompt: "Optional")
        } header: {
            Text("About you")
        }
        .pfRows()
    }

    private var bioSection: some View {
        Section {
            TextField("Bio", text: $bio, prompt: Text("What and where you fish"), axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text("Bio")
        }
        .pfRows()
    }

    private var titleSection: some View {
        Section {
            Button { showingTitlePicker = true } label: {
                LabeledContent("Title") {
                    HStack(spacing: DS.Space.s1) {
                        Text(TitleFlair.resolve(title)?.name ?? "None")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                }
                .foregroundStyle(.dsText)
            }
            .disabled(earnedFlairs.isEmpty)
        } footer: {
            Text(earnedFlairs.isEmpty
                 ? "Titles unlock from achievements."
                 : "Titles unlock from achievements. Only crew and friends see your profile once you join Crew.")
        }
        .pfRows()
    }

    private func load() {
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

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(trimmedName, forKey: "communityName")
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
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s4) {
                    card
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .accessibilityElement(children: .combine)
                    SectionFootnote("No spots or locations are on the card.")
                }
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
                .frame(maxWidth: .infinity)
            }
            .detailTint(nil)
            .safeAreaInset(edge: .bottom) { shareButton }
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { rendered = ShareCardRenderer.image(card) }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        Group {
            if let rendered {
                let image = Image(uiImage: rendered)
                ShareLink(item: image, preview: SharePreview(name, image: image)) {
                    Label("Share card", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dsPrimary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, DS.Space.s4)
    }

    /// The card in the share card family: avatar as the cover, name and
    /// subtitle, three stats and the wordmark footer. Fits its content.
    private var card: some View {
        ShareCardCanvas(height: nil) {
            avatarCover
            Text(name)
                .font(.title.bold())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, DS.Space.s4)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.dsText2)
                    .lineLimit(2)
            }
            HStack(spacing: DS.Space.s2) {
                ShareCardStat(value: "\(catches)", label: catches == 1 ? "Catch" : "Catches")
                ShareCardStat(value: "\(species)", label: "Species")
                ShareCardStat(value: "\(spots)", label: spots == 1 ? "Spot" : "Spots")
            }
            .padding(.top, DS.Space.s4)
            ShareCardFooter(detail: "Tight lines")
                .padding(.top, DS.Space.s5)
        }
    }

    /// The photo when there is one, otherwise the initial on the accent.
    private var avatarCover: some View {
        Color.dsFill
            .overlay { DS.accent.opacity(0.3) }
            .overlay {
                if let avatar {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else if let initial = name.first {
                    Text(String(initial).uppercased())
                        .font(.largeTitle.bold())
                        .foregroundStyle(DS.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - Storage and backups

/// What Currents keeps on this phone, a way into offline maps, backups, and
/// CSV import and export.
struct StorageSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled = true

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
    @State private var usage: StorageUsage?

    var body: some View {
        TodayPage("Storage and backups",
                  subtitle: usage.map { "\(StorageUsage.format($0.total)) on this phone" } ?? "On this phone") {
            StorageUsageBar(usage: usage)
                .padding(.horizontal, DS.gutter)
            CardSection("Maps") {
                NavigationLink(value: SettingsRoute.offlineMaps) {
                    CardRow("Offline maps", subtitle: "Downloads and cached tiles", systemImage: "map.fill",
                            tint: .green, value: usage.map { StorageUsage.format($0.maps) }, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            }
            backupSection
            CardSection("Data") {
                Button { exportAllData() } label: {
                    CardRow("Export all data", systemImage: "tablecells.fill", tint: .green, value: "CSV")
                }
                .buttonStyle(.dsCardRow)
                Button { showingCSVImport = true } label: {
                    CardRow("Import catches", systemImage: "square.and.arrow.down.fill", tint: .blue, value: "CSV")
                }
                .buttonStyle(.dsCardRow)
            }
        }
        .task { await load() }
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
        CardSection("Backups", note: backupMessage ?? "Catches, photos, spots, gear and licences.") {
            CardToggleRow("Automatic daily backup",
                          subtitle: iCloudAvailable ? "On this phone and to iCloud" : "On this phone",
                          systemImage: "clock.arrow.circlepath", tint: .blue, isOn: $autoBackupEnabled)
            Button { backUpNow() } label: {
                CardRow(isBackingUp ? "Backing up" : "Back up now", systemImage: "icloud.and.arrow.up.fill",
                        tint: .cyan, value: isBackingUp ? nil : dbSize) {
                    if isBackingUp { ProgressView() }
                }
            }
            .buttonStyle(.dsCardRow)
            .disabled(isBackingUp || isRestoring)
            if let date = lastBackupDate {
                CardRow("Last backup", systemImage: "checkmark.circle.fill", tint: .green) {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.dsText2)
                }
            }
            if iCloudAvailable {
                Button { showingRestoreConfirm = true } label: {
                    CardRow("Restore from iCloud", systemImage: "arrow.counterclockwise.icloud.fill", tint: .orange) {
                        if isRestoring { ProgressView() }
                    }
                }
                .buttonStyle(.dsCardRow)
                .disabled(isBackingUp || isRestoring)
            }
            if !snapshots.isEmpty {
                Button { showingHistory = true } label: {
                    CardRow("Backup history", systemImage: "clock.fill", tint: .purple,
                            value: "\(snapshots.count)", chevron: true)
                }
                .buttonStyle(.dsCardRow)
            }
        }
    }

    private var historySheet: some View {
        NavigationStack {
            ScrollView {
                CardSection(note: "The latest automatic backups on this phone.") {
                    ForEach(snapshots) { snap in
                        CardRow(snap.date.formatted(date: .abbreviated, time: .shortened),
                                subtitle: snap.formattedSize, systemImage: "externaldrive.fill", tint: .mint) {
                            Button("Restore") { restoreSnapshot = snap }
                                .buttonStyle(TonalButtonStyle(fullWidth: false))
                                .disabled(isBackingUp || isRestoring)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s4)
            }
            .dsScreenBackground()
            .detailScrollEdge()
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
        iCloudAvailable = await CloudBackup.shared.isAvailable
        if iCloudAvailable {
            lastBackupDate = await CloudBackup.shared.lastBackupDate
        }
        if let localLast = AutoBackup.lastRun {
            lastBackupDate = max(lastBackupDate ?? .distantPast, localLast)
        }
        dbSize = await FileBackup.shared.databaseSize
        snapshots = await FileBackup.shared.snapshots()
        await measure()
    }

    /// Fills the storage bar. Downloaded map and backup sizes are already
    /// known; the photo folder, database and map cache are measured off the
    /// main thread.
    private func measure() async {
        let files = await StorageUsage.measureFiles()
        let manager = appState.mapManager
        manager.refreshDownloadedRegions()
        let overlay = manager.offlineOverlay
        let cache = await Task.detached(priority: .utility) { overlay.cacheSizeBytes }.value
        let maps = manager.packBytes + manager.legacyMaps.reduce(Int64(0)) { $0 + $1.sizeBytes } + cache
        let backups = snapshots.reduce(Int64(0)) { $0 + $1.sizeBytes }
        usage = StorageUsage(maps: maps, photos: files.photos, logbook: files.logbook, backups: backups)
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

// MARK: - Storage bar

/// What Currents keeps on this phone, by kind.
struct StorageUsage: Equatable {
    var maps: Int64
    var photos: Int64
    var logbook: Int64
    var backups: Int64

    var total: Int64 { maps + photos + logbook + backups }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// The catch photo folder and the database files, which nothing else
    /// tracks. Same locations as PhotoManager and FileBackup use.
    static func measureFiles() async -> (photos: Int64, logbook: Int64) {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var photos: Int64 = 0
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
               let files = fm.enumerator(at: docs.appendingPathComponent("catch_photos", isDirectory: true),
                                         includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in files {
                    photos += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            var logbook: Int64 = 0
            if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                for name in ["currents.sqlite", "currents.sqlite-wal", "currents.sqlite-shm"] {
                    let path = support.appendingPathComponent(name).path
                    logbook += (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                }
            }
            return (photos, logbook)
        }.value
    }
}

/// One stacked bar of storage by kind, with a legend, like iPhone Storage.
private struct StorageUsageBar: View {
    let usage: StorageUsage?

    private struct Part: Identifiable {
        let name: String
        let bytes: Int64
        let color: Color
        var id: String { name }
    }

    private var parts: [Part] {
        guard let usage else { return [] }
        return [
            Part(name: "Offline maps", bytes: usage.maps, color: DS.accent),
            Part(name: "Catch photos", bytes: usage.photos, color: .dsScoreGood),
            Part(name: "Logbook", bytes: usage.logbook, color: .dsScoreFair),
            Part(name: "Backups", bytes: usage.backups, color: .gray),
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if parts.isEmpty {
                Capsule()
                    .fill(Color.dsFill2)
                    .frame(height: 14)
                    .overlay {
                        if usage == nil { ProgressView().controlSize(.mini) }
                    }
            } else {
                Chart(parts) { part in
                    BarMark(x: .value("Size", Double(part.bytes)), y: .value("Storage", "Currents"))
                        .foregroundStyle(part.color)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartXScale(domain: 0...Double(max(usage?.total ?? 1, 1)))
                .frame(height: 14)
                .clipShape(Capsule())
                .accessibilityHidden(true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Space.s3, alignment: .leading)],
                          alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(parts) { part in
                        HStack(spacing: 6) {
                            Circle().fill(part.color).frame(width: 8, height: 8)
                            Text(part.name)
                                .foregroundStyle(.dsText2)
                            Text(StorageUsage.format(part.bytes))
                                .monospacedDigit()
                                .foregroundStyle(.dsText)
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DetailHeader(title: "Units", subtitle: "How catches, weather and dates read.")

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("Measurements")
                    HStack(spacing: DS.Space.s3) {
                        systemCard("Metric", tag: "metric")
                        systemCard("Imperial", tag: "imperial")
                    }
                    .padding(.horizontal, DS.gutter)
                }

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("Time")
                    PFToggleRow(title: "24-hour time", detail: use24HourTime ? "17:30" : "5:30 PM", isOn: $use24HourTime)
                        .pfCard()
                }

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("Date format")
                    VStack(spacing: 0) {
                        dateRow("Automatic", detail: Date.now.formatted(date: .numeric, time: .omitted), tag: "auto")
                        PFDivider()
                        dateRow("Day, month, year", detail: sample(dayFirst: true), tag: "dayFirst")
                        PFDivider()
                        dateRow("Month, day, year", detail: sample(dayFirst: false), tag: "monthFirst")
                    }
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .padding(.horizontal, DS.gutter)
                    PFFootnote("Used to read dates off scanned licences.")
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Units", shown: titleShown)
    }

    /// A choice card that shows a real catch in that system, so the choice
    /// explains itself.
    private func systemCard(_ title: String, tag: String) -> some View {
        let isActive = units == tag
        let imperial = tag == "imperial"
        return Button {
            units = tag
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isActive ? Color.dsText : Color.dsText2)
                    Spacer(minLength: 4)
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.dsText3))
                        .accessibilityHidden(true)
                }
                Text(Units.length(cm: 38, imperial: imperial))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .padding(.top, DS.Space.s2)
                Text("\(Units.weight(kg: 1.2, imperial: imperial)), water \(Units.temperature(18, imperial: imperial))")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
            )
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
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

    private var svc: CommunityService { .shared }

    var body: some View {
        TodayPage("Privacy", subtitle: "Everything stays on this phone until you share it.") {
            sharingSection
            blurSection
            syncSection
            CardSection("Your data") {
                NavigationLink(value: SettingsRoute.storage) {
                    CardRow("Export or back up", systemImage: "square.and.arrow.up.fill", tint: .green, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            }
        }
    }

    private var sharingSection: some View {
        CardSection("Crew and friends", note: "Your best catches always show on the friends leaderboard.") {
            CardToggleRow("Share my catches", subtitle: "Species, size and photo",
                          systemImage: "fish.fill", tint: .blue, isOn: $shareCatches)
            CardToggleRow("Share my spots", subtitle: "Private until you turn this on",
                          systemImage: "mappin.circle.fill", tint: .red, isOn: $shareSpots)
            if shareSpots {
                CardToggleRow("Exact spot locations", subtitle: "Off moves shared spots about 4 km",
                              systemImage: "scope", tint: .orange, isOn: $shareSpotExact)
            }
            CardToggleRow("Share catch locations", subtitle: "Off keeps where you caught it private",
                          systemImage: "location.fill", tint: .green, isOn: $shareCatchLocations)
        }
        .onChange(of: shareCatches) { _, _ in reapplySharing() }
        .onChange(of: shareSpots) { _, _ in reapplySharing() }
        .onChange(of: shareSpotExact) { _, _ in reapplySharing() }
    }

    private var blurSection: some View {
        CardSection("Honey-hole blur",
                    note: shareCatchLocations ? "Friends see an area this wide, never the exact rock."
                                              : "Turn on Share catch locations to use this.") {
            HStack(spacing: 14) {
                BlurRadiusPreview(radiusKm: privacyRadius, tint: .blue)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack {
                        Text("Move pins up to")
                            .foregroundStyle(.dsText)
                        Spacer(minLength: 4)
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
            }
            .padding(DS.Space.s4)
            .disabled(!shareCatchLocations)
            .opacity(shareCatchLocations ? 1 : 0.5)
            .haptic(.selection, trigger: privacyRadius)
        }
    }

    /// Builds without the iCloud entitlement (the sideload build) cannot
    /// sync, so the toggle would do nothing there.
    @ViewBuilder
    private var syncSection: some View {
        if CrewCloud.buildHasCloudKit {
            CardSection("Sync", note: "Nobody else can see your iCloud data.") {
                CardToggleRow("Sync across my devices", subtitle: "Your own private iCloud",
                              systemImage: "icloud.fill", tint: .cyan, isOn: $cloudSyncEnabled)
            }
            .onChange(of: cloudSyncEnabled) { _, on in
                CloudSyncEngine.shared.setEnabled(on)
                ToastCenter.shared.show(on ? "Syncing with your iCloud" : "Sync off. This phone only", style: .info)
            }
        } else {
            CardSection("Sync") {
                CardRow("Not available in this build", systemImage: "icloud.slash.fill", tint: .cyan)
            }
        }
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

/// What a friend sees for a shared catch: the pin itself, or a circle that
/// grows with the blur distance.
private struct BlurRadiusPreview: View {
    let radiusKm: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 64

    var body: some View {
        let diameter = 14 + (size - 18) * CGFloat(min(max(radiusKm, 0), 20) / 20)
        ZStack {
            Color.dsFill2
            if radiusKm == 0 {
                Image(systemName: "mappin")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .transition(.opacity)
            } else {
                Circle()
                    .fill(tint.opacity(0.22))
                    .overlay(Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1.5))
                    .frame(width: diameter, height: diameter)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: radiusKm)
        .accessibilityHidden(true)
    }
}

// MARK: - Widgets and Siri

/// What Currents puts on the Home Screen, Lock Screen and Dynamic Island, and
/// what you can say to Siri. The previews read the same snapshot the widgets do,
/// so they show today's real bite and sessions.
struct WidgetsSiriView: View {
    @State private var titleShown = false
    @State private var snapshot: CurrentsSnapshot?

    private let shortcuts: [(String, String, String, Color)] = [
        ("Bite score", "What's the bite score in Currents", "cloud.sun.fill", .cyan),
        ("Start session", "Start a fishing session in Currents", "figure.fishing", .green),
        ("End session", "End my fishing session in Currents", "stop.circle.fill", .red),
        ("Log catch", "Log a catch in Currents", "fish.fill", .blue),
        ("Quick catch", "I caught one in Currents", "bolt.fill", .orange),
        ("Log a fish", "Log a fish in Currents", "mic.fill", .purple),
    ]

    private let widgetColumns = [GridItem(.flexible(), spacing: DS.Space.s3),
                                 GridItem(.flexible(), spacing: DS.Space.s3)]

    /// The verdict, or nil before the app has worked out a forecast.
    private var verdict: String? {
        guard let v = snapshot?.biteVerdict.trimmingCharacters(in: .whitespaces),
              !v.isEmpty, v != "\u{2014}" else { return nil }
        return v
    }

    private var score: Int? { verdict == nil ? nil : snapshot?.biteScore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                DetailHeader(title: "Widgets and Siri",
                             subtitle: "The bite and a log button, outside the app.")

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Home Screen and Lock Screen")
                    LazyVGrid(columns: widgetColumns, spacing: DS.Space.s4) {
                        widgetTile("Bite score") { biteWidget }
                        widgetTile("Next session") { sessionWidget }
                        widgetTile("Log a catch") { logWidget }
                        widgetTile("Lock Screen", fill: .dsFill2) { lockWidget }
                    }
                    .padding(.horizontal, DS.gutter)
                    PFFootnote("Touch and hold the Home Screen, tap Edit, then Add widget.")
                        .padding(.top, DS.Space.s3)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Live Activities")
                    row("Live session", "Timer, catches and the bite",
                        "record.circle", .red)
                    row("Tournaments", "Your points against the leader",
                        "trophy.fill", .yellow)
                    PFFootnote("They start on their own.")
                        .padding(.top, DS.Space.s2)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Siri and Shortcuts")
                    ForEach(shortcuts, id: \.0) { item in
                        row(item.0, "\u{201C}\(item.1)\u{201D}", item.2, item.3)
                    }
                    if let url = URL(string: "shortcuts://") {
                        Link(destination: url) {
                            Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                        }
                        .buttonStyle(.dsTonal)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s3)
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Widgets and Siri", shown: titleShown)
        .task { snapshot = SharedStore.load() }
    }

    // MARK: Widget previews

    /// A square widget-shaped tile with its name underneath, as in the widget gallery.
    private func widgetTile<Content: View>(_ caption: String, fill: Color = .dsFill,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: DS.Space.s2) {
            fill
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    content()
                        .padding(DS.Space.s4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var biteWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let score {
                ScoreRing(score: score, size: 56)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 56)
            }
            Spacer(minLength: DS.Space.s1)
            Text("Bite score")
                .font(.caption)
                .foregroundStyle(.dsText2)
            Text(verdict ?? "No forecast yet")
                .font(.headline)
                .foregroundStyle(.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let place = snapshot?.locationName, !place.isEmpty {
                Text(place)
                    .font(.caption)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var sessionWidget: some View {
        if let snapshot, let start = snapshot.activeSessionStart {
            VStack(alignment: .leading, spacing: 2) {
                Label("Live session", systemImage: "record.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.dsScoreSlow)
                Spacer(minLength: DS.Space.s1)
                Text(snapshot.activeSessionName ?? "Session")
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                Text(start, style: .timer)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
            }
        } else if let snapshot, let name = snapshot.nextSessionName, let date = snapshot.nextSessionDate {
            VStack(alignment: .leading, spacing: 2) {
                Label("Next session", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: DS.Space.s1)
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Sessions", systemImage: "figure.fishing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: DS.Space.s1)
                Text("No session planned")
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                Text("Plan one in Currents")
                    .font(.caption)
                    .foregroundStyle(.dsText2)
            }
        }
    }

    private var logWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.dsOnPrimary)
                .frame(width: 48, height: 48)
                .background(Color.dsPrimaryButton, in: Circle())
                .accessibilityHidden(true)
            Spacer(minLength: DS.Space.s1)
            Text("Log a catch")
                .font(.headline)
                .foregroundStyle(.dsText)
            Text("One tap to the catch log")
                .font(.caption)
                .foregroundStyle(.dsText2)
                .lineLimit(2)
        }
    }

    private var lockWidget: some View {
        VStack(spacing: DS.Space.s2) {
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Gauge(value: Double(score ?? 0), in: 0...100) {
                Image(systemName: "fish.fill")
            } currentValueLabel: {
                Text(score.map { "\($0)" } ?? "\u{2013}")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(score.map { DS.scoreColor($0) } ?? .dsText3)
            .accessibilityLabel(score.map { "Bite score \($0) out of 100" } ?? "No forecast yet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Rows

    private func row(_ title: String, _ detail: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            ThumbView(systemImage: icon, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.dsText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - About

struct AboutView: View {
    @State private var titleShown = false

    /// "2.4", for the About row in settings.
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var version: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(Self.shortVersion)" : "Version \(Self.shortVersion) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                header
                CardSection("Support", note: "Free, with no ads and no account.") {
                    // Hidden until the App Store returns the tips, so a build
                    // without them never shows a dead row.
                    if TipJar.shared.isAvailable {
                        NavigationLink(value: AboutRoute.tips) {
                            CardRow("Leave a tip", systemImage: "heart.fill", tint: .pink, chevron: true)
                        }
                        .buttonStyle(.dsCardRow)
                    }
                    // The App Store's write-review page, as Apple recommends for
                    // a permanent Rate button.
                    Link(destination: ReviewPrompt.writeReviewURL) {
                        CardRow("Rate Currents", systemImage: "star.fill", tint: .yellow, chevron: true)
                    }
                    .buttonStyle(.dsCardRow)
                    .accessibilityHint("Opens the App Store")
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Data sources")
                    KeyValueList(rows: [
                        ("Species", "FishBase"),
                        ("Weather", "Open-Meteo"),
                        ("Satellite map", TileSources.current.name),
                        ("Countries and provinces", "Natural Earth"),
                        ("Rain radar", "RainViewer"),
                        ("Bathymetry", "GLOBathy"),
                        ("Water, ramps and access", "OpenStreetMap contributors"),
                    ])
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 140)
        .pfScrollTitle("About", shown: titleShown)
        .navigationDestination(for: AboutRoute.self) { _ in TipJarView() }
        .task {
            // Tries again each visit, as the tips may not have loaded before
            // (offline, or not on sale yet).
            if TipJar.shared.state != .loaded { await TipJar.shared.load() }
        }
    }

    private var header: some View {
        VStack(spacing: DS.Space.s2) {
            AppIconPreview(tint: ThemeOption.current.primary, size: 84)
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
