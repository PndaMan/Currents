import SwiftUI

struct GearTab: View {
    @Environment(AppState.self) private var appState
    @State private var loadouts: [GearLoadout] = []
    @State private var effectiveness: [(loadout: GearLoadout, catchCount: Int)] = []
    @State private var showingAdd = false
    @State private var selectedLoadout: GearLoadout?
    @State private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable {
        case list = "My Gear"
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
                    case .list:
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
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddGearSheet()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedLoadout) { loadout in
                GearDetailSheet(loadout: loadout)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private var loadoutList: some View {
        Group {
            if loadouts.isEmpty {
                ContentUnavailableView(
                    "No Gear Loadouts",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Save your rod/reel/lure combos for quick logging")
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

    private var effectivenessList: some View {
        Group {
            if effectiveness.isEmpty {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "chart.bar",
                    description: Text("Log catches with gear loadouts to see what works")
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

    private func refresh() async {
        loadouts = (try? appState.gearRepository.fetchAll()) ?? []
        effectiveness = (try? appState.gearRepository.effectiveness()) ?? []
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
            // Category filter chips
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
    let item: GearItem

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
                if let price = item.priceRange {
                    Text(price)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
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

    private func categoryIcon(_ cat: GearItem.GearCategory) -> String {
        switch cat {
        case .rod: return "line.diagonal"
        case .reel: return "gearshape.fill"
        case .lure: return "fish.circle.fill"
        case .bait: return "ant.fill"
        case .line: return "line.3.horizontal"
        case .hook: return "arrow.turn.down.right"
        case .terminal: return "paperclip"
        case .accessory: return "bag.fill"
        }
    }

    private func categoryColor(_ cat: GearItem.GearCategory) -> Color {
        switch cat {
        case .rod: return .brown
        case .reel: return .gray
        case .lure: return .green
        case .bait: return .orange
        case .line: return .blue
        case .hook: return .red
        case .terminal: return .purple
        case .accessory: return .teal
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
                    Label(rod, systemImage: "line.diagonal")
                }
                if let lure = loadout.lure {
                    Label(lure, systemImage: "fish.circle")
                }
                if let technique = loadout.technique {
                    Label(technique, systemImage: "hand.raised")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Bass Finesse Setup", text: $name)
                }
                Section("Rod & Reel") {
                    TextField("Rod", text: $rod)
                    TextField("Reel", text: $reel)
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
                    TextField("Lure / Bait", text: $lure)
                    TextField("Color", text: $lureColor)
                    HStack {
                        TextField("Weight", text: $lureWeightG)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                Section("Technique") {
                    TextField("e.g. Drop shot, Carolina rig", text: $technique)
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
        }
    }

    private func save() {
        var loadout = GearLoadout(
            name: name,
            rod: rod.isEmpty ? nil : rod,
            reel: reel.isEmpty ? nil : reel,
            lineLb: Double(lineLb),
            leaderLb: Double(leaderLb),
            lure: lure.isEmpty ? nil : lure,
            lureColor: lureColor.isEmpty ? nil : lureColor,
            lureWeightG: Double(lureWeightG),
            technique: technique.isEmpty ? nil : technique
        )
        try? appState.gearRepository.save(&loadout)
        dismiss()
    }
}

struct GearDetailSheet: View {
    let loadout: GearLoadout

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    GearDetailGrid(loadout: loadout)
                }
            }
            .navigationTitle(loadout.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
