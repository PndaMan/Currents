import SwiftUI
import UIKit

/// The tackle box, pushed from Profile (`AppRoute.gear`) and from the logbook.
/// Owned items with stock counts, and presets that bundle a whole setup.
struct GearTab: View {
    @Environment(AppState.self) private var appState
    @State private var loadouts: [GearLoadout] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var catches: [CatchDetail] = []
    @State private var showingAddItem = false
    @State private var showingAddLoadout = false
    @State private var showingCatalog = false
    @State private var selectedLoadout: GearLoadout?
    @State private var editingOwnedGear: OwnedGear?
    @State private var editingLoadout: GearLoadout?
    /// Deleting gear (and a preset) is confirmed first. One mis-tap in a
    /// context menu shouldn't erase an item, its photo and its stock alerts.
    @State private var gearToDelete: OwnedGear?
    @State private var loadoutToDelete: GearLoadout?
    @State private var viewMode: ViewMode = .items
    @State private var categoryFilter: OwnedGear.Category?
    @State private var didLoad = false
    @State private var titleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ViewMode: String, CaseIterable {
        case items = "My gear"
        case presets = "Presets"
    }

    private var subtitle: String {
        if ownedGear.isEmpty && loadouts.isEmpty { return "Nothing added yet" }
        let items = ownedGear.count == 1 ? "1 item" : "\(ownedGear.count) items"
        let presets = loadouts.count == 1 ? "1 preset" : "\(loadouts.count) presets"
        return "\(items), \(presets)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DetailHeader(title: "Tackle box", subtitle: didLoad ? subtitle : nil)

                Picker("Show", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.gutter)

                switch viewMode {
                case .items: ownedGearContent
                case .presets: presetContent
                }
            }
            .padding(.bottom, DS.Space.s8)
            .animation(reduceMotion ? nil : .easeOut(duration: DS.Motion.fast), value: viewMode)
            .animation(reduceMotion ? nil : .easeOut(duration: DS.Motion.fast), value: categoryFilter)
            .pageWidth()
        }
        .detailTint(.orange)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Tackle box", shown: titleShown)
        .navigationDestination(for: GearItemRoute.self) { route in
            GearItemDetailView(itemID: route.id)
        }
        .navigationDestination(for: GearEffectivenessRoute.self) { _ in
            GearEffectivenessView()
        }
        .confirmationDialog("Delete this gear?",
                            isPresented: Binding(get: { gearToDelete != nil },
                                                 set: { if !$0 { gearToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete gear", role: .destructive) {
                if let item = gearToDelete {
                    try? appState.ownedGearRepository.delete(item)
                    if let p = item.photoPath { PhotoManager.delete(p) }
                    NotificationManager.shared.cancelLowStockAlert(itemId: item.id)
                    Haptics.warning()
                    ToastCenter.shared.show("Gear deleted", style: .info, haptic: false)
                    Task { await refresh() }
                }
                gearToDelete = nil
            }
        } message: {
            Text("The item, its photo and any stock alerts are removed.")
        }
        .confirmationDialog("Delete this preset?",
                            isPresented: Binding(get: { loadoutToDelete != nil },
                                                 set: { if !$0 { loadoutToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete preset", role: .destructive) {
                if let loadout = loadoutToDelete {
                    try? appState.gearRepository.delete(loadout)
                    Haptics.warning()
                    ToastCenter.shared.show("Preset deleted", style: .info, haptic: false)
                    Task { await refresh() }
                }
                loadoutToDelete = nil
            }
        } message: {
            Text("Catches logged with it keep their gear snapshot.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add gear item", systemImage: "plus.circle")
                    }
                    Button {
                        showingAddLoadout = true
                    } label: {
                        Label("New preset", systemImage: "square.stack.3d.up")
                    }
                    Divider()
                    Button {
                        showingCatalog = true
                    } label: {
                        Label("Browse the gear catalog", systemImage: "books.vertical")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showingAddItem, onDismiss: {
            Task { await refresh() }
        }) {
            AddOwnedGearSheet()
        }
        .sheet(isPresented: $showingAddLoadout, onDismiss: {
            Task { await refresh() }
        }) {
            AddGearSheet()
        }
        .sheet(isPresented: $showingCatalog, onDismiss: {
            Task { await refresh() }
        }) {
            NavigationStack {
                GearCatalogBrowser()
                    .navigationTitle("Gear catalog")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingCatalog = false }
                        }
                    }
            }
        }
        .sheet(item: $selectedLoadout) { loadout in
            GearDetailSheet(loadout: loadout, onEdit: { edited in
                selectedLoadout = nil
                editingLoadout = edited
            }, onDelete: { doomed in
                selectedLoadout = nil
                loadoutToDelete = doomed
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingOwnedGear, onDismiss: {
            Task { await refresh() }
        }) { gear in
            EditOwnedGearSheet(gear: gear)
        }
        .sheet(item: $editingLoadout, onDismiss: {
            Task { await refresh() }
        }) { loadout in
            EditLoadoutSheet(loadout: loadout)
        }
        .task { await refresh() }
    }

    // MARK: - Owned gear

    private var shownCategories: [OwnedGear.Category] {
        categoryFilter.map { [$0] } ?? ownedCategories
    }

    @ViewBuilder
    private var ownedGearContent: some View {
        if !didLoad {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s8)
        } else if ownedGear.isEmpty {
            ContentUnavailableView {
                Label("No gear yet", systemImage: "shippingbox")
            } description: {
                Text("Add your rods, reels, lures and more to mix and match when you log a catch.")
            } actions: {
                Button("Add your first item") { showingAddItem = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                Button("Browse the gear catalog") { showingCatalog = true }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, DS.Space.s6)
        } else {
            if let low = ownedGear.first(where: \.isLowStock) {
                NavigationLink(value: GearItemRoute(id: low.id)) {
                    PFNotice(systemImage: "shippingbox.fill", tint: .dsScoreLow,
                             title: (low.stock ?? 0) <= 0 ? "Out of \(low.name)" : "Running low on \(low.name)",
                             message: lowMessage(low)) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                }
                .buttonStyle(.dim)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip("All", isSelected: categoryFilter == nil) { categoryFilter = nil }
                    ForEach(ownedCategories, id: \.self) { cat in
                        Chip("\(cat.plural) \(count(for: cat))", isSelected: categoryFilter == cat) {
                            categoryFilter = categoryFilter == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
            .sensoryFeedback(.selection, trigger: categoryFilter)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shownCategories, id: \.self) { category in
                    Text(category.plural)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)
                        .padding(.bottom, DS.Space.s1)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(items(in: category)) { item in
                        gearRow(item)
                    }
                }
            }

            NavigationLink(value: GearEffectivenessRoute()) {
                HStack(spacing: 14) {
                    PFIcon(systemImage: "chart.bar.fill", color: .orange)
                    Text("Gear effectiveness")
                        .foregroundStyle(.dsText)
                    Spacer()
                    Text("Which lures catch")
                        .foregroundStyle(.dsText2)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.dsText3)
                }
                .padding(DS.Space.s4)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
            }
            .buttonStyle(.dim)
            .padding(.top, DS.Space.s4)
        }
    }

    private func lowMessage(_ item: OwnedGear) -> String {
        let stock = item.stock ?? 0
        let at = item.lowStockThreshold ?? 1
        return stock <= 0 ? "None left. Restock before your next trip."
            : "\(stock) left, you asked to hear at \(at)."
    }

    private var ownedCategories: [OwnedGear.Category] {
        OwnedGear.Category.allCases.filter { cat in ownedGear.contains { $0.category == cat } }
    }

    private func items(in category: OwnedGear.Category) -> [OwnedGear] {
        ownedGear.filter { $0.category == category }.sorted { $0.displayName < $1.displayName }
    }

    private func count(for category: OwnedGear.Category) -> Int {
        ownedGear.filter { $0.category == category }.count
    }

    private func gearRow(_ item: OwnedGear) -> some View {
        let caught = GearStats.catchCount(for: item, in: catches)
        return HStack(spacing: 14) {
            NavigationLink(value: GearItemRoute(id: item.id)) {
                HStack(spacing: 14) {
                    GearThumb(item: item, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(.dsText)
                            .lineLimit(1)
                        if let sub = [item.brand, item.specs].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                            Text(sub)
                                .font(.subheadline)
                                .foregroundStyle(.dsText2)
                                .lineLimit(1)
                        }
                        if caught > 0 {
                            Label(caught == 1 ? "1 catch" : "\(caught) catches", systemImage: "fish")
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dim)

            if item.category.isConsumable {
                PFStepper(value: stockLabel(item), canDecrement: (item.stock ?? 0) > 0,
                          label: "\(item.name) in stock") { delta in
                    changeStock(item, by: delta)
                }
                .foregroundStyle(item.isLowStock ? Color.dsScoreLow : Color.dsText)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .contextMenu {
            Button {
                editingOwnedGear = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                gearToDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func stockLabel(_ item: OwnedGear) -> String {
        let stock = item.stock ?? 0
        return stock <= 0 ? "Out" : "\(stock)"
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

    // MARK: - Presets

    @ViewBuilder
    private var presetContent: some View {
        if !didLoad {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s8)
        } else if loadouts.isEmpty {
            ContentUnavailableView {
                Label("No presets yet", systemImage: "square.stack.3d.up")
            } description: {
                Text("Save rod, reel and lure combos so logging a catch takes one tap.")
            } actions: {
                Button("Create a preset") { showingAddLoadout = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            }
            .padding(.top, DS.Space.s6)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(loadouts) { loadout in
                    Button {
                        selectedLoadout = loadout
                    } label: {
                        PresetCard(loadout: loadout,
                                   catchCount: GearStats.catchCount(for: loadout, in: catches),
                                   lureItem: ownedGear.first { $0.displayName == loadout.lure })
                    }
                    .buttonStyle(.dim)
                    .contextMenu {
                        Button {
                            editingLoadout = loadout
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            loadoutToDelete = loadout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            PFFootnote("Pick a preset when you log a catch to save the whole setup.")
        }
    }

    private func refresh() async {
        loadouts = (try? appState.gearRepository.fetchPresets()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
        didLoad = true
    }
}

/// Pushes an owned item's detail page. `OwnedGear` isn't Hashable, so the
/// route carries its id and the page reads the latest copy.
struct GearItemRoute: Hashable {
    let id: String
}

struct GearEffectivenessRoute: Hashable {}

// MARK: - Preset row

struct PresetCard: View {
    let loadout: GearLoadout
    var catchCount: Int = 0
    var lureItem: OwnedGear? = nil

    private var summary: String {
        var parts: [String] = []
        if let lure = loadout.lure {
            parts.append(loadout.lureColor.map { "\(lure) (\($0))" } ?? lure)
        }
        if let line = loadout.lineLb { parts.append("\(Int(line)) lb line") }
        if parts.isEmpty, let rod = loadout.rod { parts.append(rod) }
        if parts.isEmpty, let reel = loadout.reel { parts.append(reel) }
        if let technique = loadout.technique { parts.append(technique.lowercased()) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            if let lureItem {
                GearThumb(item: lureItem, size: 56)
            } else if let lure = loadout.lure, !lure.isEmpty {
                LureArtView(name: lure, size: 56)
            } else {
                ThumbView(systemImage: "square.stack.3d.up.fill", tint: .orange, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(loadout.name)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                Text(summary.isEmpty ? "Empty preset, tap to add a rod, reel and lure" : summary)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                if catchCount > 0 {
                    Label(catchCount == 1 ? "1 catch" : "\(catchCount) catches", systemImage: "fish")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.dsText3)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
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
                Section {
                    GearCategoryChips(selection: $category, inset: 0)
                        .gearFormBareRow()
                } header: {
                    Text("Type")
                }
                Section("Details") {
                    TextField("Name, for example Shimano Stradic", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs or notes (optional)", text: $specs)
                }
                .pfRows()
                if category.isConsumable {
                    Section("Stock") {
                        GearStockRow(title: "In stock", value: $stock, range: 0...999)
                        GearStockRow(title: "Remind me at", value: $lowStockThreshold, range: 0...99)
                    }
                    .pfRows()
                }
                if BarcodeScannerView.isSupported {
                    Section {
                        Button {
                            showingScanner = true
                        } label: {
                            Label(barcode.isEmpty ? "Scan barcode" : "Barcode \(barcode)",
                                  systemImage: "barcode.viewfinder")
                        }
                        BarcodeLookupStatus(state: lookupState)
                    } footer: {
                        Text("Fills in the name and brand.")
                    }
                    .pfRows()
                }
            }
            .gearFormStyle()
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    BarcodeScannerView { code in
                        Task { await handleScan(code) }
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan barcode")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingScanner = false }
                        }
                    }
                }
            }
            .navigationTitle("Add gear")
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
            Label { Text("Looking up the product") } icon: { ProgressView() }
                .font(.caption).foregroundStyle(.secondary)
        case .found(let title):
            Label("Found \(title)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .notFound:
            Label("Barcode saved. No match found, so add the details yourself.", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .invalid:
            Label("That doesn't look like a valid product barcode.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .offline:
            Label("Barcode saved. The product database could not be reached, so add the details yourself.", systemImage: "wifi.slash")
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
                HStack(spacing: 6) {
                    Chip("All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(GearItem.GearCategory.allCases, id: \.self) { cat in
                        Chip(cat.rawValue, systemImage: GearItem.icon(for: cat),
                             isSelected: selectedCategory == cat) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 6)
            }
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
            .fixedSize(horizontal: false, vertical: true)

            if !didLoad && items.isEmpty {
                // First open (catalog still syncing from the cloud).
                FishLoader(message: "Loading the gear catalog")
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
                        .pfRows()
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .detailScrollEdge()
                .task {
                    // Pull the latest published catalog in the background; once
                    // synced it's stored locally, so browsing works offline.
                    await GearCatalogSync.syncIfDue(db: appState.db)
                    items = (try? appState.gearCatalogRepository.fetchAll()) ?? []
                }
            }
        }
        .dsScreenBackground()
        .searchable(text: $searchText, prompt: "Brand, model, type or species")
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
            if item.category == .lure || item.category == .bait {
                LureArtView(name: item.displayName, size: 44)
                    .accessibilityHidden(true)
            } else {
                ThumbView(systemImage: GearItem.icon(for: item.category), tint: .orange, size: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                HStack(spacing: 0) {
                    if let type = item.type {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let specs = item.specs {
                        Text(item.type != nil ? ", \(specs)" : specs)
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
                            .background(Color.dsFill2, in: Capsule())
                            .foregroundStyle(.dsText)
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
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In your tackle box")
            } else {
                Button {
                    addToMyGear()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(item.displayName) to your tackle box")
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
                let s = [item.type, item.specs].compactMap { $0 }.joined(separator: ", ")
                return s.isEmpty ? nil : s
            }()
        )
        try? appState.ownedGearRepository.save(&gear)
        ToastCenter.shared.show("Added to your tackle box")
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
                Section {
                    PresetDraftHeader(name: name, lure: lure)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section("Name") {
                    TextField("For example, bass finesse setup", text: $name)
                }
                .pfRows()
                Section("Rod and reel") {
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
                .pfRows()
                Section("Lure or bait") {
                    loadoutGearPicker(category: .lure, selection: $lure, placeholder: "Lure or bait")
                    TextField("Colour", text: $lureColor)
                    HStack {
                        TextField("Weight", text: $lureWeightG)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                .pfRows()
                Section("Technique") {
                    TechniquePicker(selection: $technique)
                }
                .pfRows()
            }
            .gearFormStyle()
            .navigationTitle("New preset")
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
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let loadout: GearLoadout
    var onEdit: ((GearLoadout) -> Void)?
    var onDelete: ((GearLoadout) -> Void)? = nil
    @State private var catches: [CatchDetail] = []

    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        if let rod = loadout.rod { result.append(("Rod", rod)) }
        if let reel = loadout.reel { result.append(("Reel", reel)) }
        if let line = loadout.lineLb { result.append(("Line", "\(Int(line)) lb")) }
        if let leader = loadout.leaderLb { result.append(("Leader", "\(Int(leader)) lb")) }
        if let lure = loadout.lure { result.append(("Lure", lure)) }
        if let color = loadout.lureColor { result.append(("Colour", color)) }
        if let weight = loadout.lureWeightG { result.append(("Lure weight", "\(Int(weight)) g")) }
        if let technique = loadout.technique { result.append(("Technique", technique)) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        if let lure = loadout.lure, !lure.isEmpty {
                            LureArtView(name: lure, size: 96)
                                .padding(.horizontal, DS.gutter)
                                .accessibilityHidden(true)
                        }
                        DetailHeader(over: "Preset", title: loadout.name, subtitle: caughtLine)
                    }

                    if onEdit != nil || onDelete != nil {
                        ActionTriple {
                            if let onEdit {
                                Button { onEdit(loadout) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(ActionTileStyle(.primary))
                            }
                            if let onDelete {
                                Button { onDelete(loadout) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(ActionTileStyle(.destructive))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Setup")
                        if rows.isEmpty {
                            PFFootnote("Nothing in this preset yet. Edit it to add a rod, reel and lure.")
                        } else {
                            PFKeyValueCard(rows: rows)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s4)
                .pageWidth()
            }
            .detailTint(.orange)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
            }
        }
    }

    private var caughtLine: String? {
        let n = GearStats.catchCount(for: loadout, in: catches)
        guard n > 0 else { return nil }
        return n == 1 ? "1 catch with this setup" : "\(n) catches with this setup"
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
                Section {
                    GearCategoryChips(selection: $category, inset: 0)
                        .gearFormBareRow()
                } header: {
                    Text("Type")
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs or notes (optional)", text: $specs)
                }
                .pfRows()
                if category.isConsumable {
                    Section("Stock") {
                        GearStockRow(title: "In stock", value: $stock, range: 0...999)
                        GearStockRow(title: "Remind me at", value: $lowStockThreshold, range: 0...99)
                    }
                    .pfRows()
                }
                if let code = gear.barcode {
                    Section("Barcode") {
                        Label(code, systemImage: "barcode")
                            .font(.subheadline.monospaced())
                            .textSelection(.enabled)
                    }
                    .pfRows()
                }
            }
            .gearFormStyle()
            .navigationTitle("Edit gear")
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
                Section {
                    PresetDraftHeader(name: name, lure: lure)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section("Name") {
                    TextField("Preset name", text: $name)
                }
                .pfRows()
                Section("Rod and reel") {
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
                .pfRows()
                Section("Lure or bait") {
                    loadoutGearPicker(category: .lure, selection: $lure, placeholder: "Lure or bait")
                    TextField("Colour", text: $lureColor)
                    HStack {
                        TextField("Weight", text: $lureWeightG)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                .pfRows()
                Section("Technique") {
                    TechniquePicker(selection: $technique)
                }
                .pfRows()
            }
            .gearFormStyle()
            .navigationTitle("Edit preset")
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

// MARK: - Sheet pieces

extension View {
    /// The add and edit gear forms on the page background with `dsFill`
    /// rows, like the settings pages, and a hard edge under the title.
    func gearFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .dsScreenBackground()
            .detailScrollEdge()
    }

    /// A clear, full-width form row for content that brings its own
    /// background (chips). It stays inside the row, so nothing pokes past
    /// the screen edge.
    func gearFormBareRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The gear categories as chips, so the type is one tap instead of a menu.
struct GearCategoryChips: View {
    @Binding var selection: OwnedGear.Category
    /// Leading and trailing space inside the scroller.
    var inset: CGFloat = DS.gutter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                    Chip(cat.rawValue, isSelected: selection == cat) { selection = cat }
                }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, DS.Space.s1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A count with the tackle box's minus and plus capsule.
struct GearStockRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.dsText)
            Spacer()
            PFStepper(value: "\(value)", canDecrement: value > range.lowerBound, label: title) { delta in
                value = min(max(value + delta, range.lowerBound), range.upperBound)
            }
        }
    }
}

/// The top of the preset form: the lure's picture and the name as typed.
struct PresetDraftHeader: View {
    let name: String
    let lure: String

    private var lureName: String? {
        let trimmed = lure.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "__custom__" ? nil : trimmed
    }

    var body: some View {
        HStack(spacing: 14) {
            if let lureName {
                LureArtView(name: lureName, size: 64)
            } else {
                ThumbView(systemImage: "square.stack.3d.up.fill", tint: .orange, size: 64)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "New preset" : name)
                    .font(.title3.bold())
                    .foregroundStyle(name.isEmpty ? Color.dsText3 : Color.dsText)
                    .lineLimit(2)
                Text(lureName ?? "Add a lure or bait below")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
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
            Text("Custom").tag("__custom__")
        }
        if custom {
            TextField("Custom technique", text: $selection)
                .autocorrectionDisabled()
        }
    }
}
