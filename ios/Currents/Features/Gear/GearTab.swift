import SwiftUI

struct GearTab: View {
    @Environment(AppState.self) private var appState
    @State private var loadouts: [GearLoadout] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var effectiveness: [(loadout: GearLoadout, catchCount: Int)] = []
    @State private var showingAddItem = false
    @State private var showingAddLoadout = false
    @State private var selectedLoadout: GearLoadout?
    @State private var editingOwnedGear: OwnedGear?
    @State private var editingLoadout: GearLoadout?
    @State private var viewMode: ViewMode = .items

    enum ViewMode: String, CaseIterable {
        case items = "My Gear"
        case presets = "Presets"
        case effectiveness = "Effectiveness"
        case catalog = "Catalog"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch viewMode {
                    case .items:
                        ownedGearList
                    case .presets:
                        loadoutList
                    case .effectiveness:
                        effectivenessList
                    case .catalog:
                        GearCatalogBrowser()
                    }
                }
            }
            .navigationTitle("Gear")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if viewMode == .presets {
                            showingAddLoadout = true
                        } else {
                            showingAddItem = true
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

    // MARK: - Owned Gear (Individual Items)

    private var gearByCategory: [(OwnedGear.Category, [OwnedGear])] {
        let grouped = Dictionary(grouping: ownedGear) { $0.category }
        return OwnedGear.Category.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    private var ownedGearList: some View {
        Group {
            if ownedGear.isEmpty {
                ContentUnavailableView(
                    "No Gear Added",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Add your rods, reels, lures, and more to mix and match when logging catches")
                )
            } else {
                List {
                    ForEach(gearByCategory, id: \.0) { category, items in
                        Section {
                            ForEach(items) { item in
                                Button {
                                    editingOwnedGear = item
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: category.icon)
                                            .foregroundStyle(categoryColor(category))
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.displayName)
                                                .font(.subheadline.bold())
                                            if let specs = item.specs {
                                                Text(specs)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.primary)
                                .padding(.vertical, 2)
                            }
                            .onDelete { offsets in
                                for i in offsets {
                                    try? appState.ownedGearRepository.delete(items[i])
                                }
                                Task { await refresh() }
                            }
                        } header: {
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue + "s")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Loadout Presets

    private var loadoutList: some View {
        Group {
            if loadouts.isEmpty {
                ContentUnavailableView(
                    "No Loadout Presets",
                    systemImage: "tray.2",
                    description: Text("Save rod/reel/lure combos for quick selection when logging")
                )
            } else {
                List {
                    ForEach(loadouts) { loadout in
                        Button {
                            selectedLoadout = loadout
                        } label: {
                            GearLoadoutRow(loadout: loadout)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            try? appState.gearRepository.delete(loadouts[i])
                        }
                        loadouts.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Effectiveness

    private var effectivenessList: some View {
        Group {
            if effectiveness.isEmpty {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "chart.bar",
                    description: Text("Log catches with gear to see what works")
                )
            } else {
                List {
                    ForEach(effectiveness, id: \.loadout.id) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.loadout.name)
                                    .font(.headline)
                                if let lure = item.loadout.lure {
                                    Text(lure)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(item.catchCount)")
                                .font(.title2.bold())
                                .monospacedDigit()
                            Text("catches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func categoryColor(_ cat: OwnedGear.Category) -> Color {
        switch cat {
        case .rod: .brown
        case .reel: .gray
        case .lure: .green
        case .line: .blue
        case .technique: .purple
        case .bait: .orange
        case .hook: .red
        case .accessory: .teal
        }
    }

    private func refresh() async {
        loadouts = (try? appState.gearRepository.fetchAll()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        effectiveness = (try? appState.gearRepository.effectiveness()) ?? []
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Category", selection: $category) {
                        ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
                Section("Details") {
                    TextField("Name (e.g. Shimano Stradic)", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs / Notes (optional)", text: $specs)
                }
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

    private func save() {
        var item = OwnedGear(
            category: category,
            name: name,
            brand: brand.isEmpty ? nil : brand,
            specs: specs.isEmpty ? nil : specs
        )
        try? appState.ownedGearRepository.save(&item)
        dismiss()
    }
}

// MARK: - Gear Catalog Browser

struct GearCatalogBrowser: View {
    @Environment(AppState.self) private var appState
    @State private var items: [GearItem] = []
    @State private var searchText = ""
    @State private var selectedCategory: GearItem.GearCategory?

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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(GearItem.GearCategory.allCases, id: \.self) { cat in
                        FilterChip(title: cat.rawValue, isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            List {
                Section("\(filtered.count) items") {
                    ForEach(filtered) { item in
                        GearCatalogRow(item: item)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search gear by brand, type, species...")
        }
        .task {
            items = (try? appState.gearCatalogRepository.fetchAll()) ?? []
        }
    }
}

struct GearCatalogRow: View {
    @Environment(AppState.self) private var appState
    let item: GearItem
    @State private var added = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: categoryIcon(item.category))
                    .foregroundStyle(categoryColor(item.category))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline.bold())
                    if let type = item.type {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if added {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        addToMyGear()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                if let specs = item.specs {
                    Text(specs)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let target = item.targetSpecies {
                    Text(target)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
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
        withAnimation { added = true }
    }

    private func categoryIcon(_ cat: GearItem.GearCategory) -> String {
        switch cat {
        case .rod: "lines.measurement.horizontal"
        case .reel: "circle.circle"
        case .lure: "fish.fill"
        case .bait: "ladybug.fill"
        case .line: "water.waves"
        case .hook: "paperclip"
        case .terminal: "link"
        case .accessory: "bag.fill"
        }
    }

    private func categoryColor(_ cat: GearItem.GearCategory) -> Color {
        switch cat {
        case .rod: .brown
        case .reel: .gray
        case .lure: .green
        case .bait: .orange
        case .line: .blue
        case .hook: .red
        case .terminal: .purple
        case .accessory: .teal
        }
    }
}

// MARK: - Existing Support Views

struct GearLoadoutRow: View {
    let loadout: GearLoadout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loadout.name)
                .font(.headline)

            HStack(spacing: 12) {
                if let rod = loadout.rod {
                    Label(rod, systemImage: "lines.measurement.horizontal")
                }
                if let lure = loadout.lure {
                    Label(lure, systemImage: "fish.fill")
                }
                if let technique = loadout.technique {
                    Label(technique, systemImage: "figure.fishing")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

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
                    loadoutGearPicker(category: .technique, selection: $technique, placeholder: "Technique")
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
            Picker(placeholder, selection: selection) {
                Text("None").tag("")
                ForEach(items) { item in
                    Text(item.displayName).tag(item.displayName)
                }
                Text("Custom...").tag("__custom__")
            }
            if selection.wrappedValue == "__custom__" {
                TextField("Custom \(placeholder.lowercased())", text: selection)
            }
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

    init(gear: OwnedGear) {
        self.gear = gear
        _category = State(initialValue: gear.category)
        _name = State(initialValue: gear.name)
        _brand = State(initialValue: gear.brand ?? "")
        _specs = State(initialValue: gear.specs ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Category", selection: $category) {
                        ForEach(OwnedGear.Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Specs / Notes (optional)", text: $specs)
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
                        try? appState.ownedGearRepository.save(&updated)
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
                    loadoutGearPicker(category: .technique, selection: $technique, placeholder: "Technique")
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
            Picker(placeholder, selection: selection) {
                Text("None").tag("")
                ForEach(items) { item in
                    Text(item.displayName).tag(item.displayName)
                }
                Text("Custom...").tag("__custom__")
            }
            if selection.wrappedValue == "__custom__" {
                TextField("Custom \(placeholder.lowercased())", text: selection)
            }
        }
    }
}
