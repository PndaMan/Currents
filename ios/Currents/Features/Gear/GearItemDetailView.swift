import SwiftUI

// MARK: - Category helpers

extension OwnedGear.Category {
    /// Group label in the tackle box.
    var plural: String {
        switch self {
        case .rod: "Rods"
        case .reel: "Reels"
        case .lure: "Lures"
        case .line: "Line"
        case .bait: "Bait"
        case .hook: "Hooks"
        case .accessory: "Accessories"
        }
    }

    /// Thumbnail tint when an item has no photo.
    var tint: Color {
        switch self {
        case .rod: .orange
        case .reel: .blue
        case .lure: .green
        case .line: .cyan
        case .bait: .yellow
        case .hook: .gray
        case .accessory: .purple
        }
    }
}

/// Rounded square gear thumbnail: the item's photo, the lure art for lures
/// and bait, or its category symbol on the category tint.
struct GearThumb: View {
    let item: OwnedGear
    var size: CGFloat = 56

    var body: some View {
        if item.photoPath != nil {
            GearThumbnail(photoPath: item.photoPath, category: item.category, size: size)
                .clipShape(RoundedRectangle(cornerRadius: size < 48 ? size * 0.25 : DS.Radius.thumb, style: .continuous))
        } else if item.category == .lure || item.category == .bait {
            LureArtView(name: item.name, size: size)
        } else {
            ThumbView(systemImage: item.category.icon, tint: item.category.tint, size: size)
        }
    }
}

// MARK: - Catch counts

/// Read-only counts of logged catches per item and preset, from the gear
/// snapshot saved with each catch.
enum GearStats {
    static func catchCount(for item: OwnedGear, in catches: [CatchDetail]) -> Int {
        matching(item, in: catches).count
    }

    static func matching(_ item: OwnedGear, in catches: [CatchDetail]) -> [CatchDetail] {
        let names: Set<String> = [item.displayName, item.name]
        func has(_ value: String?) -> Bool { value.map { names.contains($0) } ?? false }
        return catches.filter { detail in
            guard let g = detail.gearLoadout else { return false }
            switch item.category {
            case .rod: return has(g.rod)
            case .reel: return has(g.reel)
            case .lure, .bait: return has(g.lure)
            default: return has(g.rod) || has(g.reel) || has(g.lure)
            }
        }
    }

    static func catchCount(for loadout: GearLoadout, in catches: [CatchDetail]) -> Int {
        catches.filter { detail in
            guard let g = detail.gearLoadout else { return false }
            return g.id == loadout.id || g.name == loadout.name
        }.count
    }
}

// MARK: - Item detail

/// One owned item: photo or symbol, name and brand, stock, details and how it
/// has done on the water.
struct GearItemDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    @State private var item: OwnedGear?
    @State private var catches: [CatchDetail] = []
    @State private var editing: OwnedGear?
    @State private var confirmDelete = false
    @State private var titleShown = false

    var body: some View {
        ScrollView {
            if let item {
                content(item)
                    .pageWidth()
            }
        }
        .detailTint(item?.category.tint ?? .orange)
        .pfTrackScroll($titleShown, threshold: 200)
        .pfScrollTitle(item?.name ?? "Gear", shown: titleShown)
        .task { load() }
        .sheet(item: $editing, onDismiss: load) { gear in
            EditOwnedGearSheet(gear: gear)
        }
        .confirmationDialog("Delete this gear?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete gear", role: .destructive) { delete() }
        } message: {
            Text("The item, its photo and any stock alerts are removed.")
        }
    }

    @ViewBuilder
    private func content(_ item: OwnedGear) -> some View {
        let mine = GearStats.matching(item, in: catches)
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                GearThumb(item: item, size: 120)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                DetailHeader(over: item.category.rawValue, title: item.name, subtitle: item.brand)
                ActionTriple {
                    Button { editing = item } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    if let barcode = item.barcode {
                        ShareLink(item: "\(item.displayName), barcode \(barcode)") {
                            ActionTileLabel("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.dim)
                    }
                    Button { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(ActionTileStyle(.destructive))
                }
            }

            if item.category.isConsumable {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("In the box")
                    VStack(spacing: 0) {
                        stockRow("In stock", value: item.stock ?? 0, low: item.isLowStock) { change(stockBy: $0) }
                        Rectangle().fill(Color.dsSeparator).frame(height: 0.5).padding(.leading, DS.Space.s4)
                        stockRow("Remind me at", value: item.lowStockThreshold ?? 1, low: false) { change(thresholdBy: $0) }
                    }
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .padding(.horizontal, DS.gutter)
                    PFFootnote(stockFootnote(item))
                        .padding(.top, DS.Space.s2)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Details")
                PFKeyValueCard(rows: detailRows(item))
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("On the water")
                if mine.isEmpty {
                    PFNotice(systemImage: "fish", tint: .dsText2, title: "No catches with this yet",
                             message: "Pick it when you log a catch and it shows up here.")
                } else {
                    PFKeyValueCard(rows: waterRows(mine))
                    NavigationLink(value: GearEffectivenessRoute()) {
                        HStack {
                            Text("Compare with your other gear")
                                .foregroundStyle(.tint)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.dsText3)
                        }
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                    }
                    .buttonStyle(.dim)
                    .padding(.top, DS.Space.s3)
                }
            }
        }
        .padding(.bottom, DS.Space.s8)
    }

    private func stockRow(_ title: String, value: Int, low: Bool, onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).foregroundStyle(.dsText)
            Spacer()
            PFStepper(value: "\(value)", canDecrement: value > 0, label: title, onChange: onChange)
                .foregroundStyle(low ? Color.dsScoreLow : Color.dsText)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
    }

    private func stockFootnote(_ item: OwnedGear) -> String {
        let stock = item.stock ?? 0
        let at = item.lowStockThreshold ?? 1
        if stock <= 0 { return "Out of stock." }
        if item.isLowStock { return "Running low. You asked to hear at \(at)." }
        return "You get a reminder when you are down to \(at)."
    }

    private func detailRows(_ item: OwnedGear) -> [(String, String)] {
        var rows: [(String, String)] = [("Category", item.category.rawValue)]
        if let brand = item.brand, !brand.isEmpty { rows.append(("Brand", brand)) }
        if let specs = item.specs, !specs.isEmpty { rows.append(("Specs", specs)) }
        if let barcode = item.barcode { rows.append(("Barcode", barcode)) }
        rows.append(("Added", item.createdAt.formatted(date: .abbreviated, time: .omitted)))
        return rows
    }

    private func waterRows(_ mine: [CatchDetail]) -> [(String, String)] {
        var rows: [(String, String)] = [("Catches", "\(mine.count)")]
        let spots = Dictionary(grouping: mine.compactMap { $0.spot?.name }, by: { $0 })
        if let best = spots.max(by: { $0.value.count < $1.value.count })?.key {
            rows.append(("Best at", best))
        }
        let species = Dictionary(grouping: mine.compactMap { $0.species?.commonName }, by: { $0 })
        if let top = species.max(by: { $0.value.count < $1.value.count })?.key {
            rows.append(("Top species", top))
        }
        if let last = mine.map(\.catchRecord.caughtAt).max() {
            rows.append(("Last catch", last.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
    }

    // MARK: Actions

    private func load() {
        item = ((try? appState.ownedGearRepository.fetchAll()) ?? []).first { $0.id == itemID }
        catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
    }

    private func change(stockBy delta: Int) {
        guard var updated = item else { return }
        updated.stock = max(0, (updated.stock ?? 0) + delta)
        save(updated)
    }

    private func change(thresholdBy delta: Int) {
        guard var updated = item else { return }
        updated.lowStockThreshold = max(0, (updated.lowStockThreshold ?? 1) + delta)
        save(updated)
    }

    private func save(_ gear: OwnedGear) {
        var updated = gear
        try? appState.ownedGearRepository.save(&updated)
        item = updated
        UISelectionFeedbackGenerator().selectionChanged()
        if updated.isLowStock {
            Task { await NotificationManager.shared.scheduleLowStockAlert(item: updated) }
        } else {
            NotificationManager.shared.cancelLowStockAlert(itemId: updated.id)
        }
    }

    private func delete() {
        guard let item else { return }
        try? appState.ownedGearRepository.delete(item)
        if let p = item.photoPath { PhotoManager.delete(p) }
        NotificationManager.shared.cancelLowStockAlert(itemId: item.id)
        Haptics.warning()
        ToastCenter.shared.show("Gear deleted", style: .info, haptic: false)
        dismiss()
    }
}

// MARK: - Gear effectiveness

/// Which lures and techniques have caught fish, from the gear saved with each
/// catch. Worked out on this phone.
struct GearEffectivenessView: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var didLoad = false
    @State private var titleShown = false

    private var withGear: [CatchDetail] { catches.filter { $0.gearLoadout != nil } }

    private func tally(_ key: (GearLoadout) -> String?) -> [(String, Int)] {
        let names = withGear.compactMap { $0.gearLoadout.flatMap(key) }.filter { !$0.isEmpty }
        return Dictionary(grouping: names, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DetailHeader(title: "Gear effectiveness",
                             subtitle: didLoad ? (withGear.count == 1 ? "1 catch logged with gear" : "\(withGear.count) catches logged with gear") : nil)

                if didLoad && withGear.isEmpty {
                    ContentUnavailableView("No gear on your catches yet", systemImage: "chart.bar",
                                           description: Text("Pick a preset or your gear when you log a catch and this fills in."))
                } else {
                    bars("Catches by lure", tally { $0.lure }, tint: .orange, showsLureArt: true)
                    bars("Catches by preset", tally { $0.isAutoCreated ? nil : $0.name }, tint: .blue)
                    bars("Technique breakdown", tally { $0.technique }, tint: .green)
                    PFFootnote("Catches logged without gear are left out.")
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.orange)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Gear effectiveness", shown: titleShown)
        .task {
            catches = (try? appState.catchRepository.fetchAll(limit: 10000)) ?? []
            didLoad = true
        }
    }

    @ViewBuilder
    private func bars(_ title: String, _ rows: [(String, Int)], tint: Color, showsLureArt: Bool = false) -> some View {
        if !rows.isEmpty {
            let top = Array(rows.prefix(8))
            let peak = max(top.first?.1 ?? 1, 1)
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(title)
                VStack(spacing: DS.Space.s3) {
                    ForEach(top, id: \.0) { name, count in
                        HStack(spacing: 14) {
                            if showsLureArt {
                                LureArtView(name: name, size: 44)
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(name).foregroundStyle(.dsText).lineLimit(1)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.body.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.dsText)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.dsFill2)
                                        Capsule().fill(tint)
                                            .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(peak)))
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(name)
                        .accessibilityValue(count == 1 ? "1 catch" : "\(count) catches")
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }
}
