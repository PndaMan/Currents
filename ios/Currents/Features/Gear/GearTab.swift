import SwiftUI

struct GearTab: View {
    @Environment(AppState.self) private var appState
    @State private var loadouts: [GearLoadout] = []
    @State private var effectiveness: [(loadout: GearLoadout, catchCount: Int)] = []
    @State private var showingAdd = false
    @State private var selectedLoadout: GearLoadout?
    @State private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable {
        case list = "Loadouts"
        case effectiveness = "Effectiveness"
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

// MARK: - Add Gear Sheet

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

// MARK: - Gear Detail Sheet

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
