import SwiftUI
import UIKit

struct GearTab: View {
    @Environment(AppState.self) private var appState
    @State private var loadouts: [GearLoadout] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var showingAddItem = false
    @State private var showingAddLoadout = false
    @State private var showingCatalog = false
    @State private var selectedLoadout: GearLoadout?
    @State private var editingOwnedGear: OwnedGear?
    @State private var editingLoadout: GearLoadout?
    @State private var viewMode: ViewMode = .items
    @State private var categoryFilter: OwnedGear.Category?

    enum ViewMode: String, CaseIterable {
        case items = "My Gear"
        case presets = "Presets"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                    modePicker

                    switch viewMode {
                    case .items:
                        ownedGearContent
                    case .presets:
                        presetContent
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .navigationTitle("Gear")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddItem = true
                        } label: {
                            Label("Add Gear Item", systemImage: "plus.circle")
                        }
                        Button {
                            showingAddLoadout = true
                        } label: {
                            Label("New Preset", systemImage: "square.stack.3d.up")
                        }
                        Divider()
                        Button {
                            showingCatalog = true
                        } label: {
                            Label("Browse Catalog", systemImage: "books.vertical")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem, onDismiss: {
                Task { await refresh() }
            }) {
                AddOwnedGearSheet()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingAddLoadout, onDismiss: {
                Task { await refresh() }
            }) {
                AddGearSheet()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingCatalog, onDismiss: {
                Task { await refresh() }
            }) {
                NavigationStack {
                    GearCatalogBrowser()
                        .navigationTitle("Gear Catalog")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingCatalog = false }
                            }
                        }
                }
            }
            .sheet(item: $selectedLoadout) { loadout in
                GearDetailSheet(loadout: loadout, onEdit: { edited in
                    editingLoadout = edited
                    selectedLoadout = nil
                })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $editingOwnedGear, onDismiss: {
                Task { await refresh() }
            }) { gear in
                EditOwnedGearSheet(gear: gear)
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $editingLoadout, onDismiss: {
                Task { await refresh() }
            }) { loadout in
                EditLoadoutSheet(loadout: loadout)
                    .presentationBackground(.ultraThinMaterial)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { viewMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(viewMode == mode ? CurrentsTheme.accent : Color.clear)
                        .foregroundStyle(viewMode == mode ? .white : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(.secondary.opacity(viewMode == mode ? 0 : 0.3))
                        )
                }
            }
        }
    }

    // MARK: - Owned Gear (Individual Items)

    private var gearByCategory: [(OwnedGear.Category, [OwnedGear])] {
        let source = categoryFilter.map { cat in ownedGear.filter { $0.category == cat } } ?? ownedGear
        let grouped = Dictionary(grouping: source) { $0.category }
        return OwnedGear.Category.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.displayName < $1.displayName })
        }
    }

    @ViewBuilder
    private var ownedGearContent: some View {
        if ownedGear.isEmpty {
            gearEmptyState(
                icon: "backpack",
                title: "No Gear Yet",
                message: "Add your rods, reels, lures and more to mix and match when logging catches.",
                primaryLabel: "Add Your First Item",
                primaryAction: { showingAddItem = true },
                secondaryLabel: "Browse Gear Catalog",
                secondaryAction: { showingCatalog = true }
            )
        } else {
            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterChip(title: "All", isSelected: categoryFilter == nil) {
                        withAnimation(.easeInOut(duration: 0.15)) { categoryFilter = nil }
                    }
                    ForEach(ownedCategories, id: \.self) { cat in
                        FilterChip(
                            title: "\(cat.rawValue) · \(count(for: cat))",
                            isSelected: categoryFilter == cat
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                categoryFilter = categoryFilter == cat ? nil : cat
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            ForEach(gearByCategory, id: \.0) { category, items in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        GearCategoryLabel(category: category, text: "\(category.rawValue)s")
                            .font(.headline)
                        Spacer()
                        Text("\(items.count)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(CurrentsTheme.accent.opacity(0.12))
                            .foregroundStyle(CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                Button {
                                    editingOwnedGear = item
                                } label: {
                                    gearItemRow(item)
                                }
                                .tint(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if item.category.isConsumable {
                                    stockStepper(item)
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingOwnedGear = item
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    try? appState.ownedGearRepository.delete(item)
                                    if let p = item.photoPath { PhotoManager.delete(p) }
                                    NotificationManager.shared.cancelLowStockAlert(itemId: item.id)
                                    Haptics.warning()
                                    ToastCenter.shared.show("Gear deleted", style: .info, haptic: false)
                                    Task { await refresh() }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if item.id != items.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
                .glassCard()
            }
        }
    }

    private var ownedCategories: [OwnedGear.Category] {
        OwnedGear.Category.allCases.filter { cat in ownedGear.contains { $0.category == cat } }
    }

    private func count(for category: OwnedGear.Category) -> Int {
        ownedGear.filter { $0.category == category }.count
    }

    private func gearItemRow(_ item: OwnedGear) -> some View {
        HStack(spacing: 12) {
            GearThumbnail(photoPath: item.photoPath, category: item.category)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let brand = item.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let specs = item.specs {
                        if item.brand != nil {
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text(specs)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if item.isLowStock {
                        Text(item.stock ?? 0 <= 0 ? "OUT" : "LOW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }

    // MARK: - Tackle-box stock stepper

    private func stockStepper(_ item: OwnedGear) -> some View {
        let count = item.stock ?? 0
        return HStack(spacing: 12) {
            Button {
                changeStock(item, by: -1)
            } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
                    .foregroundStyle(count <= 0 ? Color.secondary.opacity(0.4) : CurrentsTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(count <= 0)

            Text("\(count)")
                .font(.subheadline.bold()).monospacedDigit()
                .frame(minWidth: 20)
                .foregroundStyle(item.isLowStock ? .orange : .primary)

            Button {
                changeStock(item, by: 1)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
                    .foregroundStyle(CurrentsTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
    }

    private func changeStock(_ item: OwnedGear, by delta: Int) {
        var updated = item
        updated.stock = max(0, (item.stock ?? 0) + delta)
        try? appState.ownedGearRepository.save(&updated)
        if let idx = ownedGear.firstIndex(where: { $0.id == item.id }) {
            ownedGear[idx] = updated
        }
        UISelectionFeedbackGenerator().selectionChanged()
        if updated.isLowStock {
            Task { await NotificationManager.shared.scheduleLowStockAlert(item: updated) }
        } else {
            NotificationManager.shared.cancelLowStockAlert(itemId: updated.id)
        }
    }

    // MARK: - Loadout Presets

    @ViewBuilder
    private var presetContent: some View {
        if loadouts.isEmpty {
            gearEmptyState(
                icon: "square.stack.3d.up",
                title: "No Presets Yet",
                message: "Save rod, reel and lure combos so logging a catch takes one tap.",
                primaryLabel: "Create a Preset",
                primaryAction: { showingAddLoadout = true }
            )
        } else {
            ForEach(loadouts) { loadout in
                Button {
                    selectedLoadout = loadout
                } label: {
                    PresetCard(loadout: loadout)
                }
                .tint(.primary)
                .contextMenu {
                    Button {
                        editingLoadout = loadout
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        try? appState.gearRepository.delete(loadout)
                        Haptics.warning()
                        ToastCenter.shared.show("Preset deleted", style: .info, haptic: false)
                        Task { await refresh() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private func gearEmptyState(
        icon: String,
        title: String,
        message: String,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(CurrentsTheme.accent.opacity(0.6))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(primaryLabel, action: primaryAction)
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton)
                .tint(CurrentsTheme.accent)
            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel, action: secondaryAction)
                    .font(.subheadline)
                    .tint(CurrentsTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func refresh() async {
        loadouts = (try? appState.gearRepository.fetchPresets()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let loadout: GearLoadout

    private var components: [(icon: String, text: String)] {
        var result: [(String, String)] = []
        if let rod = loadout.rod { result.append(("figure.fishing", rod)) }
        if let reel = loadout.reel { result.append(("record.circle", reel)) }
        if let line = loadout.lineLb { result.append(("scribble.variable", "\(Int(line)) lb")) }
        if let lure = loadout.lure {
            var text = lure
            if let color = loadout.lureColor { text += " (\(color))" }
            result.append(("fish.fill", text))
        }
        if let technique = loadout.technique { result.append(("scope", technique)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loadout.name)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if components.isEmpty {
                Text("Empty preset — tap to add components")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(components, id: \.text) { component in
                        HStack(spacing: 4) {
                            Image(systemName: component.icon)
                                .font(.system(size: 10))
                            Text(component.text)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(CurrentsTheme.accent.opacity(0.12))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Add Owned Gear Sheet

struct AddOwnedGearSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var category: OwnedGear.Category = .rod
    @State private var name = ""
    @State private var brand = ""
    @State private var specs = ""
    @State private var barcode = ""
    @State private var stock = 1
    @State private var lowStockThreshold = 2
    @State private var showingScanner = false
    @State private var lookupState: BarcodeLookupState = .idle
    @State private var photo: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                // Photo first: for a lure it carries the colour and pattern
                // that a name never will, so it's the fastest way to make an
                // entry recognisable later.
                Section {
                    GearPhotoField(image: $photo)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Type") {
                    Picker("Category", selection: $category) {
                        // Glyph in the dropdown so the category is recognisable
                        // before you read it.
                        ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                            GearCategoryLabel(category: cat).tag(cat)
                        }
                    }
                }
                Section("Details") {
                    TextField("Name (e.g. Shimano Stradic)", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs / Notes (optional)", text: $specs)
                }
                if category.isConsumable {
                    Section("Stock") {
                        Stepper("In stock: \(stock)", value: $stock, in: 0...999)
                        Stepper("Remind me at: \(lowStockThreshold)", value: $lowStockThreshold, in: 0...99)
                    }
                }
                if BarcodeScannerView.isSupported {
                    Section {
                        Button {
                            showingScanner = true
                        } label: {
                            Label(barcode.isEmpty ? "Scan Barcode" : "Barcode: \(barcode)",
                                  systemImage: "barcode.viewfinder")
                        }
                        BarcodeLookupStatus(state: lookupState)
                    } footer: {
                        Text("Scan a product barcode to auto-fill the name and brand, and keep it on the item for re-ordering.")
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { code in
                    Task { await handleScan(code) }
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Add Gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func handleScan(_ code: String) async {
        guard GearProductLookup.isValid(code) else {
            lookupState = .invalid
            return
        }
        barcode = GearProductLookup.normalized(code)
        lookupState = .looking
        do {
            let product = try await GearProductLookup.lookup(code)
            if name.isEmpty { name = product.title }
            if brand.isEmpty, let b = product.brand { brand = b }
            lookupState = .found(product.title)
        } catch GearProductLookup.LookupError.notFound {
            lookupState = .notFound
        } catch {
            lookupState = .offline
        }
    }

    private func save() {
        let consumable = category.isConsumable
        var item = OwnedGear(
            category: category,
            name: name,
            brand: brand.isEmpty ? nil : brand,
            specs: specs.isEmpty ? nil : specs,
            stock: consumable ? stock : nil,
            lowStockThreshold: consumable ? lowStockThreshold : nil,
            barcode: barcode.isEmpty ? nil : barcode
        )
        // Saved under the item's own id so it travels with the record and is
        // picked up by the existing photo backup.
        if let photo, let filename = try? PhotoManager.save(photo, id: "gear_\(item.id)") {
            item.photoPath = filename
        }
        try? appState.ownedGearRepository.save(&item)
        if item.isLowStock {
            Task { await NotificationManager.shared.scheduleLowStockAlert(item: item) }
        }
        ToastCenter.shared.show("Gear saved")
        dismiss()
    }
}

// MARK: - Barcode lookup status

enum BarcodeLookupState: Equatable {
    case idle, looking, found(String), notFound, invalid, offline
}

struct BarcodeLookupStatus: View {
    let state: BarcodeLookupState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .looking:
            Label { Text("Looking up product…") } icon: { ProgressView() }
                .font(.caption).foregroundStyle(.secondary)
        case .found(let title):
            Label("Found: \(title)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .notFound:
            Label("Barcode saved — no match found, add the details yourself.", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .invalid:
            Label("That doesn't look like a valid product barcode.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .offline:
            Label("Barcode saved — couldn't reach the product database (offline?).", systemImage: "wifi.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Gear Catalog Browser

struct GearCatalogBrowser: View {
    @Environment(AppState.self) private var appState
    @State private var items: [GearItem] = []
    @State private var ownedNames: Set<String> = []
    @State private var searchText = ""
    @State private var selectedCategory: GearItem.GearCategory?
    @State private var didLoad = false

    var filtered: [GearItem] {
        var result = items
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.brand.localizedCaseInsensitiveContains(searchText) ||
                $0.model.localizedCaseInsensitiveContains(searchText) ||
                ($0.type ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.targetSpecies ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    /// Items grouped by category, in enum order, for sectioned browsing.
    private var grouped: [(category: GearItem.GearCategory, items: [GearItem])] {
        let dict = Dictionary(grouping: filtered) { $0.category }
        return GearItem.GearCategory.allCases.compactMap { cat in
            guard let list = dict[cat], !list.isEmpty else { return nil }
            return (cat, list)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The row used to be pinned to a hard 46pt. Chips are taller than
            // that once they have an icon, so the content overflowed its own
            // scroll view and could be dragged around inside it. It sizes to
            // its content now, and only bounces along the axis it scrolls.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterChip(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(GearItem.GearCategory.allCases, id: \.self) { cat in
                        FilterChip(
                            title: cat.rawValue,
                            isSelected: selectedCategory == cat,
                            systemImage: GearItem.icon(for: cat)
                        ) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
            .fixedSize(horizontal: false, vertical: true)

            if !didLoad && items.isEmpty {
                // First open (catalog still syncing from the cloud).
                FishLoader(message: "Loading the tackle box…")
                    .frame(maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No gear found",
                    systemImage: "backpack",
                    description: Text("Try a different search or category.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                GearCatalogRow(
                                    item: item,
                                    isOwned: ownedNames.contains(item.model),
                                    onAdded: { ownedNames.insert(item.model) }
                                )
                            }
                        } header: {
                            HStack {
                                Label("\(group.category.rawValue)s", systemImage: GearItem.icon(for: group.category))
                                Spacer()
                                Text("\(group.items.count)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    // Pull the latest published catalog; once synced it's
                    // stored locally, so everything here works offline.
                    await GearCatalogSync.syncIfDue(db: appState.db, force: true)
                    items = (try? appState.gearCatalogRepository.fetchAll()) ?? []
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search brand, model, type, species...")
        .task {
            items = (try? appState.gearCatalogRepository.fetchAll()) ?? []
            let owned = (try? appState.ownedGearRepository.fetchAll()) ?? []
            ownedNames = Set(owned.map(\.name))
            // If the catalog hasn't landed yet (first launch, still syncing),
            // wait briefly and re-read so the loader gives way to real content.
            if items.isEmpty {
                await GearCatalogSync.syncIfDue(db: appState.db)
                items = (try? appState.gearCatalogRepository.fetchAll()) ?? []
            }
            didLoad = true
        }
    }
}

extension GearItem {
    static func icon(for cat: GearCategory) -> String {
        switch cat {
        case .rod: "figure.fishing"
        case .reel: "record.circle"
        case .lure: "fish.fill"
        case .bait: "ant.fill"
        case .line: "scribble.variable"
        case .hook: "paperclip"
        case .terminal: "link"
        case .accessory: "backpack.fill"
        }
    }
}

struct GearCatalogRow: View {
    @Environment(AppState.self) private var appState
    let item: GearItem
    let isOwned: Bool
    var onAdded: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: GearItem.icon(for: item.category))
                .font(.subheadline)
                .foregroundStyle(CurrentsTheme.accent)
                .frame(width: 38, height: 38)
                .background(CurrentsTheme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let type = item.type {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let specs = item.specs {
                        if item.type != nil {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(specs)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    if let target = item.targetSpecies {
                        Text(target)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CurrentsTheme.accent.opacity(0.1))
                            .foregroundStyle(CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                    if let price = item.priceRange {
                        Text(price)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if isOwned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CurrentsTheme.accent)
            } else {
                Button {
                    addToMyGear()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(CurrentsTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func addToMyGear() {
        let category: OwnedGear.Category = switch item.category {
        case .rod: .rod
        case .reel: .reel
        case .lure: .lure
        case .bait: .bait
        case .line: .line
        case .hook: .hook
        case .terminal, .accessory: .accessory
        }
        var gear = OwnedGear(
            category: category,
            name: item.model,
            brand: item.brand,
            specs: {
                let s = [item.type, item.specs].compactMap { $0 }.joined(separator: " — ")
                return s.isEmpty ? nil : s
            }()
        )
        try? appState.ownedGearRepository.save(&gear)
        ToastCenter.shared.show("Added to My Gear")
        withAnimation { onAdded?() }
    }

}

// MARK: - Existing Support Views

struct AddGearSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var rod = ""
    @State private var reel = ""
    @State private var lineLb = ""
    @State private var leaderLb = ""
    @State private var lure = ""
    @State private var lureColor = ""
    @State private var lureWeightG = ""
    @State private var technique = ""
    @State private var ownedGear: [OwnedGear] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Bass Finesse Setup", text: $name)
                }
                Section("Rod & Reel") {
                    loadoutGearPicker(category: .rod, selection: $rod, placeholder: "Rod")
                    loadoutGearPicker(category: .reel, selection: $reel, placeholder: "Reel")
                    HStack {
                        TextField("Line", text: $lineLb)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Leader", text: $leaderLb)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(.secondary)
                    }
                }
                Section("Lure / Bait") {
                    loadoutGearPicker(category: .lure, selection: $lure, placeholder: "Lure / Bait")
                    TextField("Color", text: $lureColor)
                    HStack {
                        TextField("Weight", text: $lureWeightG)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                Section("Technique") {
                    TechniquePicker(selection: $technique)
                }
            }
            .navigationTitle("New Loadout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .task {
                ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            }
        }
    }

    @ViewBuilder
    private func loadoutGearPicker(category: OwnedGear.Category, selection: Binding<String>, placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            TextField(placeholder, text: selection)
        } else {
            // Shared picker: custom mode is tracked separately from the
            // value, so typing a custom name doesn't dismiss the field.
            GearFieldPicker(placeholder: placeholder, items: items, selection: selection)
        }
    }

    private func save() {
        let cleanRod = rod == "__custom__" ? "" : rod
        let cleanReel = reel == "__custom__" ? "" : reel
        let cleanLure = lure == "__custom__" ? "" : lure
        let cleanTechnique = technique == "__custom__" ? "" : technique
        var loadout = GearLoadout(
            name: name,
            rod: cleanRod.isEmpty ? nil : cleanRod,
            reel: cleanReel.isEmpty ? nil : cleanReel,
            lineLb: Double(lineLb),
            leaderLb: Double(leaderLb),
            lure: cleanLure.isEmpty ? nil : cleanLure,
            lureColor: lureColor.isEmpty ? nil : lureColor,
            lureWeightG: Double(lureWeightG),
            technique: cleanTechnique.isEmpty ? nil : cleanTechnique
        )
        try? appState.gearRepository.save(&loadout)
        ToastCenter.shared.show("Preset saved")
        dismiss()
    }
}

struct GearDetailSheet: View {
    let loadout: GearLoadout
    var onEdit: ((GearLoadout) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    GearDetailGrid(loadout: loadout)
                }
            }
            .navigationTitle(loadout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            onEdit(loadout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Edit Owned Gear Sheet

struct EditOwnedGearSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let gear: OwnedGear
    @State private var category: OwnedGear.Category
    @State private var name: String
    @State private var brand: String
    @State private var specs: String
    @State private var stock: Int
    @State private var lowStockThreshold: Int
    @State private var photo: UIImage?

    init(gear: OwnedGear) {
        self.gear = gear
        _category = State(initialValue: gear.category)
        _name = State(initialValue: gear.name)
        _brand = State(initialValue: gear.brand ?? "")
        _specs = State(initialValue: gear.specs ?? "")
        _stock = State(initialValue: gear.stock ?? 0)
        _lowStockThreshold = State(initialValue: gear.lowStockThreshold ?? 2)
        _photo = State(initialValue: gear.photoPath.flatMap { PhotoManager.load($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GearPhotoField(image: $photo)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Type") {
                    Picker("Category", selection: $category) {
                        // Glyph in the dropdown so the category is recognisable
                        // before you read it.
                        ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                            GearCategoryLabel(category: cat).tag(cat)
                        }
                    }
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs / Notes (optional)", text: $specs)
                }
                if category.isConsumable {
                    Section("Stock") {
                        Stepper("In stock: \(stock)", value: $stock, in: 0...999)
                        Stepper("Remind me at: \(lowStockThreshold)", value: $lowStockThreshold, in: 0...99)
                    }
                }
                if let code = gear.barcode {
                    Section("Barcode") {
                        Label(code, systemImage: "barcode")
                            .font(.subheadline.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Edit Gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = gear
                        updated.category = category
                        updated.name = name
                        updated.brand = brand.isEmpty ? nil : brand
                        updated.specs = specs.isEmpty ? nil : specs
                        let consumable = category.isConsumable
                        updated.stock = consumable ? stock : nil
                        updated.lowStockThreshold = consumable ? lowStockThreshold : nil
                        // Delete first even when replacing: it clears the
                        // cached thumbnail, otherwise the row would keep
                        // showing the old picture at the same filename.
                        if let old = gear.photoPath { PhotoManager.delete(old) }
                        updated.photoPath = photo.flatMap {
                            try? PhotoManager.save($0, id: "gear_\(gear.id)")
                        }
                        try? appState.ownedGearRepository.save(&updated)
                        if updated.isLowStock {
                            Task { await NotificationManager.shared.scheduleLowStockAlert(item: updated) }
                        } else {
                            NotificationManager.shared.cancelLowStockAlert(itemId: updated.id)
                        }
                        ToastCenter.shared.show("Gear updated")
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Loadout Preset Sheet

struct EditLoadoutSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let loadout: GearLoadout
    @State private var name: String
    @State private var rod: String
    @State private var reel: String
    @State private var lineLb: String
    @State private var leaderLb: String
    @State private var lure: String
    @State private var lureColor: String
    @State private var lureWeightG: String
    @State private var technique: String
    @State private var ownedGear: [OwnedGear] = []

    init(loadout: GearLoadout) {
        self.loadout = loadout
        _name = State(initialValue: loadout.name)
        _rod = State(initialValue: loadout.rod ?? "")
        _reel = State(initialValue: loadout.reel ?? "")
        _lineLb = State(initialValue: loadout.lineLb.map { String($0) } ?? "")
        _leaderLb = State(initialValue: loadout.leaderLb.map { String($0) } ?? "")
        _lure = State(initialValue: loadout.lure ?? "")
        _lureColor = State(initialValue: loadout.lureColor ?? "")
        _lureWeightG = State(initialValue: loadout.lureWeightG.map { String($0) } ?? "")
        _technique = State(initialValue: loadout.technique ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Preset name", text: $name)
                }
                Section("Rod & Reel") {
                    loadoutGearPicker(category: .rod, selection: $rod, placeholder: "Rod")
                    loadoutGearPicker(category: .reel, selection: $reel, placeholder: "Reel")
                    HStack {
                        TextField("Line", text: $lineLb)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Leader", text: $leaderLb)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(.secondary)
                    }
                }
                Section("Lure / Bait") {
                    loadoutGearPicker(category: .lure, selection: $lure, placeholder: "Lure / Bait")
                    TextField("Color", text: $lureColor)
                    HStack {
                        TextField("Weight", text: $lureWeightG)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                Section("Technique") {
                    TechniquePicker(selection: $technique)
                }
            }
            .navigationTitle("Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = loadout
                        updated.name = name
                        let cleanRod = rod == "__custom__" ? "" : rod
                        let cleanReel = reel == "__custom__" ? "" : reel
                        let cleanLure = lure == "__custom__" ? "" : lure
                        let cleanTechnique = technique == "__custom__" ? "" : technique
                        updated.rod = cleanRod.isEmpty ? nil : cleanRod
                        updated.reel = cleanReel.isEmpty ? nil : cleanReel
                        updated.lineLb = Double(lineLb)
                        updated.leaderLb = Double(leaderLb)
                        updated.lure = cleanLure.isEmpty ? nil : cleanLure
                        updated.lureColor = lureColor.isEmpty ? nil : lureColor
                        updated.lureWeightG = Double(lureWeightG)
                        updated.technique = cleanTechnique.isEmpty ? nil : cleanTechnique
                        try? appState.gearRepository.save(&updated)
                        ToastCenter.shared.show("Preset updated")
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .task {
                ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            }
        }
    }

    @ViewBuilder
    private func loadoutGearPicker(category: OwnedGear.Category, selection: Binding<String>, placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            TextField(placeholder, text: selection)
        } else {
            // Shared picker: custom mode is tracked separately from the
            // value, so typing a custom name doesn't dismiss the field.
            GearFieldPicker(placeholder: placeholder, items: items, selection: selection)
        }
    }
}

// MARK: - Technique picker (preset list + custom)

/// Techniques are a catch attribute, not inventory. Offers the shared preset
/// list plus a free-text "Custom…" option, storing the plain technique string.
struct TechniquePicker: View {
    @Binding var selection: String
    @State private var custom: Bool

    init(selection: Binding<String>) {
        _selection = selection
        let v = selection.wrappedValue
        _custom = State(initialValue: !v.isEmpty && !FishingTechniques.presets.contains(v))
    }

    var body: some View {
        Picker("Technique", selection: Binding(
            get: { custom ? "__custom__" : selection },
            set: { newValue in
                if newValue == "__custom__" { custom = true; selection = "" }
                else { custom = false; selection = newValue }
            }
        )) {
            Text("None").tag("")
            ForEach(FishingTechniques.presets, id: \.self) { Text($0).tag($0) }
            Text("Custom…").tag("__custom__")
        }
        if custom {
            TextField("Custom technique", text: $selection)
                .autocorrectionDisabled()
        }
    }
}
