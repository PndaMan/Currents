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
    /// Edit or Delete chosen on the preset detail. It runs once that sheet
    /// has gone, so the next sheet or dialog is not presented mid-dismiss.
    @State private var presetFollowUp: PresetFollowUp?
    @State private var viewMode: ViewMode = .items
    @State private var filter: GearFilter = .all
    @State private var didLoad = false
    @State private var loadFailed = false
    @State private var titleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PresetFollowUp {
        case edit(GearLoadout)
        case delete(GearLoadout)
    }

    enum ViewMode: String, CaseIterable {
        case items = "My gear"
        case presets = "Presets"
    }

    /// Which owned items the list shows: all, the ones running low, or one
    /// category.
    enum GearFilter: Hashable {
        case all, low
        case category(OwnedGear.Category)
    }

    private var subtitle: String {
        if ownedGear.isEmpty && loadouts.isEmpty { return "Nothing added yet" }
        let items = ownedGear.count == 1 ? "1 item" : "\(ownedGear.count) items"
        let presets = loadouts.count == 1 ? "1 preset" : "\(loadouts.count) presets"
        return "\(items), \(presets)"
    }

    var body: some View {
        withSheets(withConfirmations(page))
            .detailTint(nil)
            .pfTrackScroll($titleShown, threshold: 60)
            .pfScrollTitle("Tackle box", shown: titleShown)
            .navigationDestination(for: GearItemRoute.self) { route in
                GearItemDetailView(itemID: route.id)
            }
            .navigationDestination(for: GearEffectivenessRoute.self) { _ in
                GearEffectivenessView()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addMenu }
            }
            .task { await refresh() }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DetailHeader(title: "Tackle box", subtitle: didLoad && !loadFailed ? subtitle : nil)

                FilterChips(ViewMode.allCases, selection: $viewMode) { $0.rawValue }

                switch viewMode {
                case .items: ownedGearContent
                case .presets: presetContent
                }
            }
            .padding(.bottom, DS.Space.s8)
            .animation(reduceMotion ? nil : .easeOut(duration: DS.Motion.fast), value: viewMode)
            .animation(reduceMotion ? nil : .easeOut(duration: DS.Motion.fast), value: filter)
            .pageWidth()
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingAddItem = true
            } label: {
                Label("Add gear", systemImage: "plus.circle")
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

    // MARK: - Dialogs and sheets

    private func withConfirmations<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("Delete this gear?",
                                isPresented: Binding(get: { gearToDelete != nil },
                                                     set: { if !$0 { gearToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete gear", role: .destructive, action: deleteChosenGear)
            } message: {
                Text("The item, its photo and any stock alerts are removed.")
            }
            .confirmationDialog("Delete this preset?",
                                isPresented: Binding(get: { loadoutToDelete != nil },
                                                     set: { if !$0 { loadoutToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete preset", role: .destructive, action: deleteChosenLoadout)
            } message: {
                Text("Catches logged with it keep their gear snapshot.")
            }
    }

    private func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddItem, onDismiss: reload) {
                AddOwnedGearSheet()
            }
            .sheet(isPresented: $showingAddLoadout, onDismiss: reload) {
                AddGearSheet()
            }
            .sheet(isPresented: $showingCatalog, onDismiss: reload) {
                GearCatalogSheet()
            }
            .sheet(item: $selectedLoadout, onDismiss: runPresetFollowUp) { loadout in
                GearDetailSheet(loadout: loadout, onEdit: { edited in
                    presetFollowUp = .edit(edited)
                    selectedLoadout = nil
                }, onDelete: { doomed in
                    presetFollowUp = .delete(doomed)
                    selectedLoadout = nil
                })
                .dsSheet([.medium, .large])
            }
            .sheet(item: $editingOwnedGear, onDismiss: reload) { gear in
                EditOwnedGearSheet(gear: gear)
            }
            .sheet(item: $editingLoadout, onDismiss: reload) { loadout in
                EditLoadoutSheet(loadout: loadout)
            }
    }

    private func runPresetFollowUp() {
        guard let next = presetFollowUp else { return }
        presetFollowUp = nil
        switch next {
        case .edit(let loadout): editingLoadout = loadout
        case .delete(let loadout): loadoutToDelete = loadout
        }
    }

    private func deleteChosenGear() {
        defer { gearToDelete = nil }
        guard let item = gearToDelete else { return }
        do {
            try appState.ownedGearRepository.delete(item)
        } catch {
            ToastCenter.shared.show("Could not delete this gear", style: .error)
            return
        }
        if let p = item.photoPath { PhotoManager.delete(p) }
        NotificationManager.shared.cancelLowStockAlert(itemId: item.id)
        Haptics.warning()
        ToastCenter.shared.show("Gear deleted", style: .info, haptic: false)
        reload()
    }

    private func deleteChosenLoadout() {
        defer { loadoutToDelete = nil }
        guard let loadout = loadoutToDelete else { return }
        do {
            try appState.gearRepository.delete(loadout)
        } catch {
            ToastCenter.shared.show("Could not delete this preset", style: .error)
            return
        }
        Haptics.warning()
        ToastCenter.shared.show("Preset deleted", style: .info, haptic: false)
        reload()
    }

    // MARK: - Owned gear

    private var lowItems: [OwnedGear] { ownedGear.filter(\.isLowStock) }

    private var shownCategories: [OwnedGear.Category] {
        switch filter {
        case .all: ownedCategories
        case .low: ownedCategories.filter { cat in lowItems.contains { $0.category == cat } }
        case .category(let cat): ownedCategories.contains(cat) ? [cat] : ownedCategories
        }
    }

    @ViewBuilder
    private var ownedGearContent: some View {
        if !didLoad {
            loading
        } else if loadFailed {
            loadError
        } else if ownedGear.isEmpty {
            emptyGear
        } else {
            if !lowItems.isEmpty && filter != .low {
                lowStockRow
            }
            categoryChips
            if filter == .low && lowItems.isEmpty {
                InlineEmpty(systemImage: "checkmark.circle",
                            text: "Nothing is running low.",
                            actionTitle: "Show all gear") { filter = .all }
            } else {
                gearList
            }
            effectivenessRow
                .padding(.top, DS.Space.s4)
        }
    }

    private var loading: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s8)
    }

    private var loadError: some View {
        InlineEmpty(systemImage: "exclamationmark.triangle",
                    text: "Your tackle box could not be read. Nothing is lost.",
                    actionTitle: "Try again") { reload() }
    }

    private var emptyGear: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            InlineEmpty(systemImage: "shippingbox",
                        text: "Your tackle box is empty. Add rods, reels, lures and more to pick from when you log a catch.",
                        actionTitle: "Add gear") { showingAddItem = true }
            Button { showingCatalog = true } label: {
                ArtRow(title: "Browse the gear catalog", subtitle: "Popular rods, reels, lures and bait",
                       chevron: true) {
                    ThumbView(systemImage: "books.vertical.fill", tint: .orange, size: 52)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    /// One row for everything running low; tapping it shows only those items.
    private var lowStockRow: some View {
        let names = lowItems.map(\.name)
        let subtitle = names.count > 2
            ? "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
            : names.joined(separator: " and ")
        return CardGroup {
            Button { filter = .low } label: {
                CardRow("\(lowItems.count) running low", subtitle: subtitle,
                        systemImage: "exclamationmark.triangle.fill", tint: .orange, chevron: true)
            }
            .buttonStyle(.dsCardRow)
            .accessibilityHint("Shows only the gear that is running low")
        }
    }

    private var filterOptions: [GearFilter] {
        var options: [GearFilter] = [.all]
        // The running-low card sets this filter, so the chip shows only
        // once the card has been tapped and is hidden.
        if filter == .low { options.append(.low) }
        options += ownedCategories.map { GearFilter.category($0) }
        return options
    }

    private func filterTitle(_ option: GearFilter) -> String {
        switch option {
        case .all: "All"
        case .low: "Running low \(lowItems.count)"
        case .category(let cat): "\(cat.plural) \(count(for: cat))"
        }
    }

    private var categoryChips: some View {
        FilterChips(filterOptions, selection: $filter, title: { filterTitle($0) })
    }

    private var gearList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(shownCategories, id: \.self) { category in
                SectionTitle(category.plural, detail: "\(items(in: category).count)")
                    .padding(.top, DS.Space.s4)
                ForEach(items(in: category)) { item in
                    gearRow(item)
                }
            }
        }
    }

    private var effectivenessRow: some View {
        NavigationLink(value: GearEffectivenessRoute()) {
            ArtRow(title: "Gear effectiveness", subtitle: "Which lures and presets catch", chevron: true) {
                ThumbView(systemImage: "chart.bar.fill", tint: .orange, size: 52)
            }
        }
        .buttonStyle(.dsRow)
    }

    private var ownedCategories: [OwnedGear.Category] {
        OwnedGear.Category.allCases.filter { cat in ownedGear.contains { $0.category == cat } }
    }

    private func items(in category: OwnedGear.Category) -> [OwnedGear] {
        ownedGear
            .filter { $0.category == category && (filter != .low || $0.isLowStock) }
            .sorted { $0.displayName < $1.displayName }
    }

    private func count(for category: OwnedGear.Category) -> Int {
        ownedGear.filter { $0.category == category }.count
    }

    /// Brand (or specs) and how many catches it has, on one line.
    private func rowSubtitle(_ item: OwnedGear) -> String? {
        var parts: [String] = []
        if let sub = [item.brand, item.specs].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            parts.append(sub)
        }
        let caught = GearStats.catchCount(for: item, in: catches)
        if caught > 0 { parts.append(caught == 1 ? "1 catch" : "\(caught) catches") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func gearRow(_ item: OwnedGear) -> some View {
        HStack(spacing: 0) {
            NavigationLink(value: GearItemRoute(id: item.id)) {
                // Consumables end in a stock stepper instead of a chevron.
                ArtRow(title: item.name, subtitle: rowSubtitle(item),
                       chevron: !item.category.isConsumable) {
                    GearThumb(item: item, size: 56)
                }
            }
            .buttonStyle(.dim)

            if item.category.isConsumable {
                Group {
                    if item.stock == nil {
                        // Not counted yet: offer to start counting, never "Out".
                        Button("Set stock") { setStock(item, to: 1) }
                            .buttonStyle(TonalButtonStyle(fullWidth: false))
                            .accessibilityLabel("Set stock for \(item.name)")
                    } else {
                        PFStepper(value: stockLabel(item), canDecrement: (item.stock ?? 0) > 0,
                                  label: "\(item.name) in stock",
                                  tint: item.isLowStock ? DS.ink(.dsScoreLow) : .dsText) { delta in
                            changeStock(item, by: delta)
                        }
                    }
                }
                .padding(.trailing, DS.gutter)
            }
        }
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
        setStock(item, to: max(0, (item.stock ?? 0) + delta))
    }

    private func setStock(_ item: OwnedGear, to stock: Int) {
        var updated = item
        updated.stock = stock
        do {
            try appState.ownedGearRepository.save(&updated)
        } catch {
            ToastCenter.shared.show("Could not update the stock", style: .error)
            return
        }
        if let idx = ownedGear.firstIndex(where: { $0.id == item.id }) {
            ownedGear[idx] = updated
        }
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
            loading
        } else if loadFailed {
            loadError
        } else if loadouts.isEmpty {
            InlineEmpty(systemImage: "square.stack.3d.up",
                        text: "No presets yet. Save a rod, reel and lure combo so logging a catch takes one tap.",
                        actionTitle: "New preset") { showingAddLoadout = true }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(loadouts) { loadout in
                    presetRow(loadout)
                }
            }
            SectionFootnote("Pick a preset when you log a catch to save the whole setup.")
        }
    }

    private func presetRow(_ loadout: GearLoadout) -> some View {
        Button {
            selectedLoadout = loadout
        } label: {
            PresetCard(loadout: loadout,
                       catchCount: GearStats.catchCount(for: loadout, in: catches),
                       lureItem: ownedGear.first { $0.displayName == loadout.lure })
        }
        .buttonStyle(.dsRow)
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

    private func reload() {
        Task { await refresh() }
    }

    private func refresh() async {
        do {
            loadouts = try appState.gearRepository.fetchPresets()
            ownedGear = try appState.ownedGearRepository.fetchAll()
            loadFailed = false
        } catch {
            // An empty tackle box here would read as lost gear.
            loadFailed = true
        }
        if case .category(let cat) = filter, !ownedCategories.contains(cat) { filter = .all }
        // Catches only feed the per-item counts, so a failed read drops them.
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

/// A preset in the tackle box: the lure's picture, the name, what's in it and
/// how many catches it has.
struct PresetCard: View {
    let loadout: GearLoadout
    var catchCount: Int = 0
    var lureItem: OwnedGear? = nil

    private var summary: String {
        var parts: [String] = []
        if let lure = loadout.lure {
            parts.append(loadout.lureColor.map { "\(lure) (\($0))" } ?? lure)
        }
        if let line = loadout.lineLb { parts.append("\(PresetSheet.number(line)) lb line") }
        if parts.isEmpty, let rod = loadout.rod { parts.append(rod) }
        if parts.isEmpty, let reel = loadout.reel { parts.append(reel) }
        if let technique = loadout.technique { parts.append(technique.lowercased()) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ArtRow(title: loadout.name, subtitle: summary.isEmpty ? "Nothing in it yet" : summary,
               chevron: true) {
            art
        } trailing: {
            if catchCount > 0 {
                Label("\(catchCount)", systemImage: "fish")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .accessibilityLabel(catchCount == 1 ? "1 catch" : "\(catchCount) catches")
            }
        }
    }

    @ViewBuilder
    private var art: some View {
        if let lureItem {
            GearThumb(item: lureItem, size: 56)
        } else if let lure = loadout.lure, !lure.isEmpty {
            LureArtView(name: lure, size: 56)
        } else {
            ThumbView(systemImage: "square.stack.3d.up.fill", tint: .orange, size: 56)
        }
    }
}

// MARK: - Owned gear form

/// Add a new item to the tackle box.
struct AddOwnedGearSheet: View {
    var body: some View { OwnedGearSheet() }
}

/// Edit an item already in the tackle box.
struct EditOwnedGearSheet: View {
    let gear: OwnedGear
    var body: some View { OwnedGearSheet(editing: gear) }
}

/// The one form for adding and editing tackle box items, laid out like a
/// Contacts edit sheet: the photo on top, then labelled rows on cards,
/// Cancel and Add or Save in the bar.
struct OwnedGearSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let editing: OwnedGear?
    @State private var category: OwnedGear.Category
    @State private var name: String
    @State private var brand: String
    @State private var specs: String
    @State private var barcode: String
    @State private var stock: Int
    @State private var lowStockThreshold: Int
    @State private var photo: UIImage?
    @State private var showingScanner = false
    @State private var lookupState: BarcodeLookupState = .idle
    @FocusState private var nameFocused: Bool
    /// "Type it in" on the scanner: focus Name once the scanner has gone.
    @State private var typeInAfterScan = false

    init(editing: OwnedGear? = nil) {
        self.editing = editing
        _category = State(initialValue: editing?.category ?? .rod)
        _name = State(initialValue: editing?.name ?? "")
        _brand = State(initialValue: editing?.brand ?? "")
        _specs = State(initialValue: editing?.specs ?? "")
        _barcode = State(initialValue: editing?.barcode ?? "")
        _stock = State(initialValue: editing?.stock ?? 1)
        _lowStockThreshold = State(initialValue: editing?.lowStockThreshold ?? 2)
        _photo = State(initialValue: editing?.photoPath.flatMap { PhotoManager.load($0) })
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    GearPhotoField(image: $photo, category: category, name: name)
                    detailsSection
                    if category.isConsumable {
                        stockSection
                    }
                    if BarcodeScannerView.isDeviceSupported || !barcode.isEmpty {
                        barcodeSection
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .detailScrollEdge()
            .dsScreenBackground()
            .navigationTitle(editing == nil ? "Add gear" : "Edit gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save)
                        .bold()
                        .disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { GearKeyboard.dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner, onDismiss: focusNameIfAsked) {
                BarcodeScannerSheet(onScan: { code in
                    Task { await handleScan(code) }
                }, onTypeIn: {
                    typeInAfterScan = true
                })
            }
        }
        .dsSheet([.large])
    }

    private var detailsSection: some View {
        GearFormSection("Details") {
            GearCardField("Type") {
                Picker("Type", selection: $category) {
                    ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .haptic(.selection, trigger: category)
            }
            GearCardField("Name") {
                TextField("Name", text: $name, prompt: Text("Stradic 2500"))
                    .gearCardInput()
                    .focused($nameFocused)
            }
            GearCardField("Brand") {
                TextField("Brand", text: $brand, prompt: Text("Optional"))
                    .gearCardInput()
            }
            GearCardField("Specs") {
                TextField("Specs", text: $specs, prompt: Text("Length, weight or notes"))
                    .gearCardInput()
            }
        }
    }

    private var stockSection: some View {
        GearFormSection("Stock", note: "You get a reminder when you are down to \(lowStockThreshold).") {
            GearStockRow(title: "In stock", value: $stock, range: 0...999)
            GearStockRow(title: "Remind me at", value: $lowStockThreshold, range: 0...99)
        }
    }

    private var barcodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Barcode")
            CardGroup(separatorInset: DS.Space.s4) {
                if !barcode.isEmpty {
                    GearCardField("Barcode") {
                        Text(barcode)
                            .monospacedDigit()
                            .foregroundStyle(.dsText2)
                            .textSelection(.enabled)
                    }
                }
                if BarcodeScannerView.isDeviceSupported {
                    Button {
                        Task { await startScan() }
                    } label: {
                        CardRow(barcode.isEmpty ? "Scan barcode" : "Scan again",
                                systemImage: "barcode.viewfinder", tint: DS.accent)
                    }
                    .buttonStyle(.dsCardRow)
                }
            }
            if lookupState == .idle {
                SectionFootnote("Scanning fills in the name and brand when the product is known.")
            } else {
                BarcodeLookupStatus(state: lookupState)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    private func focusNameIfAsked() {
        guard typeInAfterScan else { return }
        typeInAfterScan = false
        nameFocused = true
    }

    /// Camera off and a device that cannot scan get different copy, since
    /// only the first can be fixed in Settings.
    private func startScan() async {
        let allowed = await CameraAccess.request()
        guard allowed else {
            lookupState = .cameraOff
            return
        }
        guard BarcodeScannerView.isSupported else {
            lookupState = .unsupported
            return
        }
        if lookupState == .cameraOff || lookupState == .unsupported { lookupState = .idle }
        showingScanner = true
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
            if trimmedName.isEmpty { name = product.title }
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
        var item = editing ?? OwnedGear(category: category, name: trimmedName)
        item.category = category
        item.name = trimmedName
        item.brand = brand.isEmpty ? nil : brand
        item.specs = specs.isEmpty ? nil : specs
        item.stock = consumable ? stock : nil
        item.lowStockThreshold = consumable ? lowStockThreshold : nil
        item.barcode = barcode.isEmpty ? nil : barcode
        savePhoto(into: &item)
        do {
            try appState.ownedGearRepository.save(&item)
        } catch {
            ToastCenter.shared.show(editing == nil ? "Could not add this gear" : "Could not save this gear",
                                    style: .error)
            return
        }
        if item.isLowStock {
            Task { await NotificationManager.shared.scheduleLowStockAlert(item: item) }
        } else if editing != nil {
            NotificationManager.shared.cancelLowStockAlert(itemId: item.id)
        }
        ToastCenter.shared.show(editing == nil ? "Gear added" : "Gear updated")
        dismiss()
    }

    /// Saved under the item's own id so it travels with the record and is
    /// picked up by the existing photo backup.
    private func savePhoto(into item: inout OwnedGear) {
        if let old = editing?.photoPath {
            // Delete first even when replacing: it clears the cached
            // thumbnail, otherwise the row would keep showing the old
            // picture at the same filename.
            PhotoManager.delete(old)
        }
        item.photoPath = photo.flatMap { try? PhotoManager.save($0, id: "gear_\(item.id)") }
    }
}

// MARK: - Barcode lookup status

enum BarcodeLookupState: Equatable {
    case idle, looking, found(String), notFound, invalid, offline, cameraOff, unsupported
}

/// One line under the barcode card saying what the last scan found, or why
/// scanning can't start.
struct BarcodeLookupStatus: View {
    let state: BarcodeLookupState
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .looking:
            Label { Text("Looking up the product") } icon: { ProgressView() }
                .font(.footnote).foregroundStyle(.dsText2)
        case .found(let title):
            Label("Found \(title)", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.dsScoreGood)
        case .notFound:
            Label("No match. Fill in the details.", systemImage: "questionmark.circle")
                .font(.footnote).foregroundStyle(.dsText2)
        case .invalid:
            Label("That doesn't look like a product barcode. Try again.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.dsScoreLow)
        case .offline:
            Label("The product database could not be reached. Fill in the details.", systemImage: "wifi.slash")
                .font(.footnote).foregroundStyle(.dsText2)
        case .cameraOff:
            cameraOff
        case .unsupported:
            Label("Scanning is not available on this device right now. Fill in the details.",
                  systemImage: "barcode.viewfinder")
                .font(.footnote).foregroundStyle(.dsText2)
        }
    }

    private var cameraOff: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label("Camera access is off. Allow it in Settings to scan barcodes.", systemImage: "camera.badge.ellipsis")
                .font(.footnote)
                .foregroundStyle(.dsText2)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(TonalButtonStyle(fullWidth: false))
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Gear catalog

/// The catalog in its own sheet, opened from the tackle box.
struct GearCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GearCatalogBrowser()
                .navigationTitle("Gear catalog")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .dsSheet([.medium, .large])
    }
}

/// Popular gear to add to the tackle box in one tap: a plain list grouped by
/// category, filtered by chips and searched from the bar.
struct GearCatalogBrowser: View {
    @Environment(AppState.self) private var appState
    @State private var items: [GearItem] = []
    @State private var ownedNames: Set<String> = []
    @State private var searchText = ""
    @State private var selectedCategory: GearItem.GearCategory?
    @State private var didLoad = false
    @State private var retrying = false

    var filtered: [GearItem] {
        var result = items
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter {
                $0.brand.localizedCaseInsensitiveContains(q) ||
                $0.model.localizedCaseInsensitiveContains(q) ||
                ($0.type ?? "").localizedCaseInsensitiveContains(q) ||
                ($0.targetSpecies ?? "").localizedCaseInsensitiveContains(q)
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
        List {
            Section {
                chips.dsListRow()
            }
            ForEach(grouped, id: \.category) { group in
                Section {
                    SectionTitle(group.category.plural, detail: "\(group.items.count)")
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(group.items) { item in
                        GearCatalogRow(item: item, isOwned: ownedNames.contains(item.model),
                                       onAdded: { ownedNames.insert(item.model) })
                            .dsListRow()
                    }
                }
            }
        }
        .dsPlainList()
        .detailScrollEdge()
        .overlay { stateOverlay }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Brand, model, type or species")
        .task { await load() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip("All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(GearItem.GearCategory.allCases, id: \.self) { cat in
                    Chip(cat.plural, isSelected: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, DS.Space.s1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if !didLoad {
            // First open, catalog still downloading.
            FishLoader(message: "Loading the gear catalog")
        } else if items.isEmpty {
            notDownloaded
        } else if filtered.isEmpty {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Nothing in this category", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Pick another category."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private var notDownloaded: some View {
        ContentUnavailableView {
            Label("Catalog not downloaded yet", systemImage: "wifi.slash")
        } description: {
            Text("It downloads once when you have signal, then works offline.")
        } actions: {
            Button("Try again") { Task { await retry() } }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                .disabled(retrying)
        }
    }

    private func fetch() -> [GearItem] {
        (try? appState.gearCatalogRepository.fetchAll()) ?? []
    }

    private func load() async {
        items = fetch()
        let owned = (try? appState.ownedGearRepository.fetchAll()) ?? []
        ownedNames = Set(owned.map(\.name))
        // Show the local copy straight away; pull new items in the background.
        if !items.isEmpty { didLoad = true }
        await GearCatalogSync.syncIfDue(db: appState.db)
        items = fetch()
        didLoad = true
    }

    private func retry() async {
        retrying = true
        await GearCatalogSync.syncIfDue(db: appState.db, force: true)
        items = fetch()
        retrying = false
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

    /// The tackle box category an item is added under.
    var ownedCategory: OwnedGear.Category {
        switch category {
        case .rod: .rod
        case .reel: .reel
        case .lure: .lure
        case .bait: .bait
        case .line: .line
        case .hook: .hook
        case .terminal, .accessory: .accessory
        }
    }
}

extension GearItem.GearCategory {
    /// Group and chip label, in sentence case.
    var plural: String {
        switch self {
        case .rod: "Rods"
        case .reel: "Reels"
        case .lure: "Lures"
        case .bait: "Bait"
        case .line: "Line"
        case .hook: "Hooks"
        case .terminal: "Terminal tackle"
        case .accessory: "Accessories"
        }
    }
}

/// A catalog item: its art, type and specs, the species it's for and the
/// price band, with a button to add it to the tackle box.
struct GearCatalogRow: View {
    @Environment(AppState.self) private var appState
    let item: GearItem
    let isOwned: Bool
    var onAdded: (() -> Void)?

    /// Type and specs on the line above the name ("Spinning, 2-piece").
    private var over: String? {
        let type = item.type.map(Self.sentenceCase)
        let parts = [type, item.specs].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 0) {
            ArtRow(over: over, title: item.displayName, subtitle: item.targetSpecies,
                   subtitleIcon: item.targetSpecies == nil ? nil : "fish") {
                art
            } trailing: {
                if let price = item.priceRange {
                    Text(price)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .accessibilityLabel("Price band \(price.count) of 4")
                }
            }
            addButton
                .padding(.trailing, DS.gutter)
        }
    }

    @ViewBuilder
    private var art: some View {
        switch item.category {
        case .lure, .bait:
            LureArtView(name: item.displayName, size: 52)
        case .terminal:
            ThumbView(systemImage: GearItem.icon(for: .terminal), tint: item.ownedCategory.tint, size: 52)
        default:
            GearThumbnail(photoPath: nil, category: item.ownedCategory, size: 52)
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if isOwned {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.dsScoreGood)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("In your tackle box")
        } else {
            Button(action: addToMyGear) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Add \(item.displayName) to your tackle box")
        }
    }

    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first) + text.dropFirst().lowercased()
    }

    private func addToMyGear() {
        let category = item.ownedCategory
        var gear = OwnedGear(
            category: category,
            name: item.model,
            brand: item.brand,
            specs: {
                let s = [item.type, item.specs].compactMap { $0 }.joined(separator: ", ")
                return s.isEmpty ? nil : s
            }(),
            // Consumables start with the one just added, so the row shows a
            // count instead of "Out".
            stock: category.isConsumable ? 1 : nil
        )
        do {
            try appState.ownedGearRepository.save(&gear)
        } catch {
            ToastCenter.shared.show("Could not add this to your tackle box", style: .error)
            return
        }
        ToastCenter.shared.show("Added to your tackle box")
        withAnimation { onAdded?() }
    }
}

// MARK: - Preset form

/// Create a new preset.
struct AddGearSheet: View {
    var body: some View { PresetSheet() }
}

/// Edit a saved preset.
struct EditLoadoutSheet: View {
    let loadout: GearLoadout
    var body: some View { PresetSheet(editing: loadout) }
}

/// The one form for adding and editing presets: the lure's picture and name
/// on top, then rod and reel, lure or bait and technique as card rows.
/// Gear the angler owns is offered as a menu, with Custom for anything else.
struct PresetSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let editing: GearLoadout?
    @State private var name: String
    @State private var rod: String
    @State private var reel: String
    @State private var lineLb: String
    @State private var leaderLb: String
    @State private var lure: String
    @State private var lureColor: String
    /// Grams, or ounces when the units setting is imperial. Stored in grams.
    @State private var lureWeight: String
    @State private var technique: String
    @State private var ownedGear: [OwnedGear] = []
    /// The units the weight field was filled in, fixed while the form is open.
    private let imperialWeight: Bool
    /// The weight as first shown, so saving an untouched field keeps the
    /// stored grams exactly instead of round-tripping through ounces.
    private let initialLureWeight: String

    static let gramsPerOunce = 28.349523

    init(editing: GearLoadout? = nil) {
        self.editing = editing
        let imperial = Units.isImperial
        let weight = editing?.lureWeightG.map { Self.number(imperial ? $0 / Self.gramsPerOunce : $0) } ?? ""
        imperialWeight = imperial
        initialLureWeight = weight
        _name = State(initialValue: editing?.name ?? "")
        _rod = State(initialValue: editing?.rod ?? "")
        _reel = State(initialValue: editing?.reel ?? "")
        _lineLb = State(initialValue: editing?.lineLb.map(Self.number) ?? "")
        _leaderLb = State(initialValue: editing?.leaderLb.map(Self.number) ?? "")
        _lure = State(initialValue: editing?.lure ?? "")
        _lureColor = State(initialValue: editing?.lureColor ?? "")
        _lureWeight = State(initialValue: weight)
        _technique = State(initialValue: editing?.technique ?? "")
    }

    /// "10" rather than "10.0" for whole numbers.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    PresetDraftHeader(name: name, lure: lure)
                        .padding(.horizontal, DS.gutter)
                    GearFormSection {
                        GearCardField("Name") {
                            TextField("Name", text: $name, prompt: Text("Bass finesse"))
                                .gearCardInput()
                        }
                    }
                    rodSection
                    lureSection
                    GearFormSection {
                        TechniquePicker(selection: $technique, style: .card)
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .detailScrollEdge()
            .dsScreenBackground()
            .navigationTitle(editing == nil ? "New preset" : "Edit preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save)
                        .bold()
                        .disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { GearKeyboard.dismiss() }
                }
            }
            .task {
                ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            }
        }
        .dsSheet([.large])
    }

    private var rodSection: some View {
        GearFormSection("Rod and reel") {
            gearPicker(.rod, selection: $rod, placeholder: "Rod")
            gearPicker(.reel, selection: $reel, placeholder: "Reel")
            numberRow("Line", text: $lineLb, unit: "lb")
            numberRow("Leader", text: $leaderLb, unit: "lb")
        }
    }

    private var lureSection: some View {
        GearFormSection("Lure or bait") {
            gearPicker(.lure, selection: $lure, placeholder: "Lure or bait")
            colourRow
            numberRow("Weight", text: $lureWeight, unit: imperialWeight ? "oz" : "g")
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, unit: String) -> some View {
        GearCardField(label) {
            HStack(spacing: DS.Space.s1) {
                TextField(label, text: text, prompt: Text("Optional"))
                    .gearCardInput(.decimalPad)
                Text(unit).foregroundStyle(.dsText2)
            }
        }
    }

    private var colourRow: some View {
        GearCardField("Colour") {
            HStack(spacing: DS.Space.s2) {
                TextField("Colour", text: $lureColor, prompt: Text("Green pumpkin"))
                    .gearCardInput()
                if LureColorSwatch.isKnown(lureColor) {
                    LureColorSwatch(name: lureColor, size: 18)
                }
            }
        }
    }

    /// Owned gear of that kind as a picker with Custom, or a plain labelled
    /// field when the tackle box has none.
    @ViewBuilder
    private func gearPicker(_ category: OwnedGear.Category, selection: Binding<String>,
                            placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            GearCardField(placeholder) {
                TextField(placeholder, text: selection, prompt: Text("Optional"))
                    .gearCardInput()
            }
        } else {
            GearCardPicker(placeholder: placeholder, options: items.map(\.displayName), selection: selection)
        }
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == GearFieldTag.custom ? nil : trimmed
    }

    /// The weight field in grams. An untouched field keeps the stored value.
    private var lureWeightGrams: Double? {
        if lureWeight == initialLureWeight, let stored = editing?.lureWeightG { return stored }
        guard let value = lureWeight.measurementValue else { return nil }
        return imperialWeight ? value * Self.gramsPerOunce : value
    }

    private func save() {
        var loadout = editing ?? GearLoadout(name: trimmedName)
        loadout.name = trimmedName
        loadout.rod = clean(rod)
        loadout.reel = clean(reel)
        loadout.lineLb = lineLb.measurementValue
        loadout.leaderLb = leaderLb.measurementValue
        loadout.lure = clean(lure)
        loadout.lureColor = clean(lureColor)
        loadout.lureWeightG = lureWeightGrams
        loadout.technique = clean(technique)
        do {
            try appState.gearRepository.save(&loadout)
        } catch {
            ToastCenter.shared.show(editing == nil ? "Could not add this preset" : "Could not save this preset",
                                    style: .error)
            return
        }
        ToastCenter.shared.show(editing == nil ? "Preset added" : "Preset updated")
        dismiss()
    }
}

// MARK: - Preset detail

struct GearDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let loadout: GearLoadout
    var onEdit: ((GearLoadout) -> Void)?
    var onDelete: ((GearLoadout) -> Void)? = nil
    @State private var catches: [CatchDetail] = []
    @AppStorage("units") private var units = "metric"

    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        if let rod = loadout.rod { result.append(("Rod", rod)) }
        if let reel = loadout.reel { result.append(("Reel", reel)) }
        if let line = loadout.lineLb { result.append(("Line", "\(PresetSheet.number(line)) lb")) }
        if let leader = loadout.leaderLb { result.append(("Leader", "\(PresetSheet.number(leader)) lb")) }
        if let lure = loadout.lure { result.append(("Lure", lure)) }
        if let color = loadout.lureColor { result.append(("Colour", color)) }
        if let weight = loadout.lureWeightG {
            result.append(("Lure weight", Units.lureWeight(grams: weight, imperial: units == "imperial")))
        }
        if let technique = loadout.technique { result.append(("Technique", FishingTechniques.label(for: technique))) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    header
                    if onEdit != nil || onDelete != nil {
                        actions
                    }
                    setup
                }
                .padding(.vertical, DS.Space.s4)
                .pageWidth()
            }
            .detailTint(nil)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if let lure = loadout.lure, !lure.isEmpty {
                LureArtView(name: lure, size: 96)
                    .padding(.horizontal, DS.gutter)
                    .accessibilityHidden(true)
            }
            DetailHeader(over: "Preset", title: loadout.name, subtitle: caughtLine)
        }
    }

    private var actions: some View {
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

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Setup")
            if rows.isEmpty {
                if let onEdit {
                    InlineEmpty(systemImage: "square.stack.3d.up",
                                text: "Nothing in this preset yet. Add a rod, reel and lure.",
                                actionTitle: "Edit preset") { onEdit(loadout) }
                } else {
                    InlineEmpty(systemImage: "square.stack.3d.up", text: "Nothing in this preset yet.")
                }
            } else {
                KeyValueList(rows: rows)
            }
        }
    }

    private var caughtLine: String? {
        let n = GearStats.catchCount(for: loadout, in: catches)
        guard n > 0 else { return nil }
        return n == 1 ? "1 catch with this setup" : "\(n) catches with this setup"
    }
}

// MARK: - Form pieces

extension View {
    /// A text field inside `GearCardField`: trailing like a Settings value,
    /// leading once the field sits under its label at accessibility sizes.
    func gearCardInput(_ keyboard: UIKeyboardType = .default) -> some View {
        modifier(GearCardInput(keyboard: keyboard))
    }
}

private struct GearCardInput: ViewModifier {
    let keyboard: UIKeyboardType
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .keyboardType(keyboard)
            .foregroundStyle(.dsText)
    }
}

/// Closes the keyboard whichever field has it, for the keyboard bar's Done
/// (decimal pads have no return key).
@MainActor
enum GearKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// A titled card of form rows: `SectionTitle`, the rows on one `CardGroup`
/// and an optional note, like `CardSection`, with the hairlines inset to the
/// text because form rows have no icon tile.
struct GearFormSection<Content: View>: View {
    let title: String?
    var note: String? = nil
    private let content: Content

    init(_ title: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { SectionTitle(title) }
            CardGroup(separatorInset: DS.Space.s4) { content }
            if let note, !note.isEmpty { SectionFootnote(note) }
        }
    }
}

/// One form row on a card: the label on the left and its control on the
/// right, padded like `CardRow`. At accessibility sizes the control moves
/// under the label so neither is cut off.
struct GearCardField<Control: View>: View {
    let label: String
    private let control: Control
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s1))
            : AnyLayout(HStackLayout(spacing: DS.Space.s3))
        layout {
            Text(label)
                .font(.body)
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            control
                .frame(maxWidth: .infinity, alignment: stacked ? .leading : .trailing)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }
}

/// The plain list-row field, kept for the profile editor. The gear forms
/// use `GearCardField`.
struct GearFormField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default
    var unit: String? = nil

    init(_ label: String, text: Binding<String>, prompt: String = "",
         keyboard: UIKeyboardType = .default, unit: String? = nil) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.keyboard = keyboard
        self.unit = unit
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: DS.Space.s1) {
                TextField(label, text: $text, prompt: Text(prompt))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                if let unit {
                    Text(unit).foregroundStyle(.dsText2)
                }
            }
        }
    }
}

/// A count with the tackle box's minus and plus capsule, as a card row.
struct GearStockRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        GearCardField(title) {
            PFStepper(value: "\(value)", canDecrement: value > range.lowerBound, label: title) { delta in
                value = min(max(value + delta, range.lowerBound), range.upperBound)
            }
        }
    }
}

/// One pick-one card row for a list of named options with None and Custom.
/// Up to `menuLimit` options it is a menu, and Custom adds a text row under
/// it; past that the row pushes `GearOptionList`, which searches and takes
/// anything typed. Needs a NavigationStack.
struct GearCardPicker: View {
    let placeholder: String
    let options: [String]
    var label: (String) -> String = { $0 }
    @Binding var selection: String
    @State private var isCustom: Bool

    /// Longer lists are hard to scan in a menu.
    static let menuLimit = 8

    init(placeholder: String, options: [String], label: @escaping (String) -> String = { $0 },
         selection: Binding<String>) {
        self.placeholder = placeholder
        self.options = options
        self.label = label
        self._selection = selection
        let value = selection.wrappedValue
        _isCustom = State(initialValue: !value.isEmpty && !options.contains(value))
    }

    private var shown: String { selection.isEmpty ? "None" : label(selection) }

    var body: some View {
        if options.count > Self.menuLimit {
            NavigationLink {
                GearOptionList(title: placeholder, options: options, label: label, selection: $selection)
            } label: {
                CardRow(placeholder, value: shown, chevron: true)
            }
            .buttonStyle(.dsCardRow)
        } else {
            VStack(spacing: 0) {
                GearCardField(placeholder) {
                    Picker(placeholder, selection: choice) {
                        Text("None").tag("")
                        ForEach(options, id: \.self) { option in
                            Text(label(option)).tag(option)
                        }
                        Text("Custom").tag(GearFieldTag.custom)
                    }
                    .pickerStyle(.menu)
                }
                if isCustom {
                    Rectangle()
                        .fill(Color.dsSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, DS.Space.s4)
                    TextField(placeholder, text: $selection,
                              prompt: Text("Type the \(placeholder.lowercased())"))
                        .foregroundStyle(.dsText)
                        .autocorrectionDisabled()
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, 10)
                        .frame(minHeight: 54)
                }
            }
        }
    }

    private var choice: Binding<String> {
        Binding(
            get: { isCustom ? GearFieldTag.custom : selection },
            set: { newValue in
                Haptics.selection()
                if newValue == GearFieldTag.custom {
                    isCustom = true
                    selection = ""
                } else {
                    isCustom = false
                    selection = newValue
                }
            }
        )
    }
}

/// A long pick-one list pushed from a form row, like a Settings picker: the
/// title, a search field under it, then None and every option on one card
/// with a tick on the chosen one. Text that matches nothing can be used as
/// typed. Picking goes back.
struct GearOptionList: View {
    let title: String
    let options: [String]
    var label: (String) -> String = { $0 }
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var titleShown = false

    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    private var filtered: [String] {
        guard !typed.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(typed) }
    }

    /// The current value when it was typed rather than picked.
    private var customValue: String? {
        selection.isEmpty || options.contains(selection) ? nil : selection
    }

    /// Typed text that is not already an option or the current value.
    private var newValue: String? {
        guard !typed.isEmpty else { return nil }
        let known = options.map(label) + [customValue].compactMap { $0 }
        if known.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) { return nil }
        return typed.prefix(1).uppercased() + String(typed.dropFirst())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: title)
                PFSearchField(prompt: "Search or type your own", text: $query)
                    .padding(.top, DS.Space.s4)
                    .padding(.bottom, DS.Space.s4)
                CardGroup(separatorInset: DS.Space.s4) {
                    if let newValue {
                        row("Use \u{201C}\(newValue)\u{201D}", value: newValue, selected: false)
                    }
                    if typed.isEmpty {
                        row("None", value: "", selected: selection.isEmpty)
                        if let customValue {
                            row(customValue, value: customValue, selected: true)
                        }
                    }
                    ForEach(filtered, id: \.self) { option in
                        row(label(option), value: option, selected: selection == option)
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .detailScrollEdge()
        .dsScreenBackground()
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle(title, shown: titleShown)
    }

    private func row(_ text: String, value: String, selected: Bool) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            CardRow(text) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .buttonStyle(.dsCardRow)
        .buttonHaptic(.selection)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The top of the preset form: the lure's picture and the name as typed,
/// as the preset will look in the tackle box.
struct PresetDraftHeader: View {
    let name: String
    let lure: String

    private var lureName: String? {
        let trimmed = lure.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == GearFieldTag.custom ? nil : trimmed
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
                Text(lureName ?? "Pick a lure or bait below")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Technique picker (preset list + custom)

/// Techniques are a catch attribute, not inventory. Stores the plain
/// technique. The shared list is longer than a menu should be, so the row
/// pushes a searchable list that also takes a technique typed in; it needs a
/// NavigationStack. `.listRow` is a row in a List or Form, `.card` a row on
/// a `CardGroup`.
struct TechniquePicker: View {
    enum Style { case listRow, card }

    @Binding var selection: String
    var style: Style = .listRow
    @State private var custom: Bool

    init(selection: Binding<String>, style: Style = .listRow) {
        _selection = selection
        self.style = style
        let v = selection.wrappedValue
        _custom = State(initialValue: !v.isEmpty && !FishingTechniques.presets.contains(v))
    }

    private static var isLong: Bool { FishingTechniques.presets.count > GearCardPicker.menuLimit }

    private var shown: String { selection.isEmpty ? "None" : FishingTechniques.label(for: selection) }

    var body: some View {
        switch style {
        case .card:
            GearCardPicker(placeholder: "Technique", options: FishingTechniques.presets,
                           label: FishingTechniques.label(for:), selection: $selection)
        case .listRow:
            if Self.isLong {
                NavigationLink {
                    GearOptionList(title: "Technique", options: FishingTechniques.presets,
                                   label: FishingTechniques.label(for:), selection: $selection)
                } label: {
                    LabeledContent("Technique", value: shown)
                }
            } else {
                menu
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Picker("Technique", selection: choice) {
            Text("None").tag("")
            ForEach(FishingTechniques.presets, id: \.self) { technique in
                Text(FishingTechniques.label(for: technique)).tag(technique)
            }
            Text("Custom").tag(GearFieldTag.custom)
        }
        .pickerStyle(.menu)
        if custom {
            TextField("Technique", text: $selection, prompt: Text("Type the technique"))
                .autocorrectionDisabled()
        }
    }

    private var choice: Binding<String> {
        Binding(
            get: { custom ? GearFieldTag.custom : selection },
            set: { newValue in
                Haptics.selection()
                if newValue == GearFieldTag.custom {
                    custom = true
                    selection = ""
                } else {
                    custom = false
                    selection = newValue
                }
            }
        )
    }
}

extension FishingTechniques {
    /// A listed technique in sentence case for display ("Drop shot"). The
    /// stored value is unchanged; custom techniques show as typed.
    static func label(for technique: String) -> String {
        guard presets.contains(technique), let first = technique.first else { return technique }
        return String(first) + technique.dropFirst().lowercased()
    }
}
