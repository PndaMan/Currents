import SwiftUI
import MapKit

/// Download an offline map: a square on the map, a country or a province.
/// The size of each level of detail shows before anything downloads, and
/// big areas are saved the fishing way: an overview of the whole area and
/// close-ups only around water and the angler's own places.
///
/// From the map: `OfflineDownloadSheet(region: visibleRegion)` opens with
/// the square over that part of the map (nil starts around the angler).
struct OfflineDownloadSheet: View {
    let target: OfflineDownloadTarget

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var area: GeoRect?
    @State private var detail: OfflineDetail
    @State private var plans: [OfflineDetail: OfflinePlan] = [:]
    @State private var planning = false
    @State private var outline: [[CLLocationCoordinate2D]] = []
    @State private var freeBytes: Int64 = OfflinePackStore.freeBytes
    @State private var detent: PresentationDetent = .large
    @State private var nameEdited = false
    /// The last name filled in from the map, to tell it from a typed one.
    @State private var autoName = ""

    private let initialRegion: MKCoordinateRegion?

    /// A square on the map, opening on `region` (nil: around the angler).
    init(region: MKCoordinateRegion? = nil, name: String? = nil) {
        self.init(target: .area(region.map { GeoRect(region: $0) }, name: name ?? ""))
    }

    init(target: OfflineDownloadTarget) {
        self.target = target
        let initialName: String
        switch target {
        case .area(let rect, let name):
            initialName = name
            _area = State(initialValue: rect)
            _detail = State(initialValue: .standard)
            initialRegion = rect?.region(padding: 1.35)
        case .region(let region):
            initialName = region.name
            _detail = State(initialValue: .standard)
            initialRegion = region.bounds.region()
        case .country(let country):
            initialName = OfflineRegionCatalog.displayName(country)
            _detail = State(initialValue: .overview)
            initialRegion = country.bounds.region()
        }
        _name = State(initialValue: initialName)
        _nameEdited = State(initialValue: !initialName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if target.isArea { areaLayout } else { regionLayout }
            }
            .navigationTitle(target.isArea ? "Download an area" : "Download a map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task(id: planKey) { await plan() }
        .task(id: nameKey) { await suggestName() }
    }

    // MARK: Layouts

    /// Map with the square on top, choices underneath.
    private var areaLayout: some View {
        VStack(spacing: 0) {
            OfflineAreaPicker(area: $area, initial: initialRegion)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                nameField
                ForEach([OfflineDetail.standard, .maximum], id: \.self) { option in
                    choice(option)
                }
                downloadButton
                footnote
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)
            .background(Color.dsBackground)
        }
    }

    private var regionLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                preview
                    .padding(.horizontal, DS.gutter)
                DetailHeader(over: regionOver, title: regionTitle, subtitle: regionSubtitle)
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Detail")
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        ForEach(OfflineDetail.allCases, id: \.self) { option in
                            choice(option)
                        }
                        nameField
                            .padding(.top, DS.Space.s2)
                        downloadButton
                            .padding(.top, DS.Space.s2)
                        footnote
                    }
                    .padding(.horizontal, DS.gutter)
                }
            }
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .dsScreenBackground()
        .detailScrollEdge()
    }

    /// The region's outline over satellite, with where the close-ups go.
    private var preview: some View {
        Map(initialPosition: .region(initialRegion ?? MKCoordinateRegion(.world)), interactionModes: []) {
            ForEach(Array(outline.enumerated()), id: \.offset) { _, ring in
                MapPolygon(coordinates: ring)
                    .foregroundStyle(DS.accent.opacity(0.16))
                    .stroke(DS.accent, lineWidth: 2)
            }
            ForEach(Array((plans[detail]?.closeUps ?? []).prefix(400).enumerated()), id: \.offset) { _, rect in
                MapPolygon(coordinates: corners(rect))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .stroke(.white, lineWidth: 1)
            }
        }
        .mapStyle(.hybrid(elevation: .flat))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityLabel("Map of \(regionTitle)")
    }

    private var nameField: some View {
        TextField("Name this map", text: $name)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            .onChange(of: name) { _, new in nameEdited = !new.isEmpty && new != autoName }
            .accessibilityLabel("Map name")
    }

    private func choice(_ option: OfflineDetail) -> some View {
        let plan = plans[option]
        let unavailable = plan.map { $0.tooLarge || $0.estimatedBytes > room } ?? false
        let selected = detail == option
        return Button {
            Haptics.selection()
            detail = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? DS.accent : Color.dsText3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.dsText)
                    Text(choiceDetail(option, plan: plan))
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let plan, !plan.tooLarge {
                    Text(OfflineFormat.estimate(plan.estimatedBytes))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .monospacedDigit()
                } else if plan == nil {
                    ProgressView()
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 12)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(selected ? DS.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .disabled(unavailable)
        .opacity(unavailable ? 0.5 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choiceDetail(_ option: OfflineDetail, plan: OfflinePlan?) -> String {
        guard let plan else { return "Working out the size." }
        if plan.tooLarge { return "Too large at this detail. Make the square smaller." }
        if plan.estimatedBytes > room { return "Not enough free space on this phone." }
        switch option {
        case .overview:
            return "The whole area at a glance, no close-ups."
        case .standard:
            return OfflineFormat.closeUps(plan, isArea: target.isArea) + ". Banks, roads and launch sites."
        case .maximum:
            return OfflineFormat.closeUps(plan, isArea: target.isArea) + ". Sharpest, to read rocks and weed beds."
        }
    }

    private var downloadButton: some View {
        Button {
            start()
        } label: {
            Text("Download")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
        .disabled(!canDownload)
    }

    private var footnote: some View {
        Text(footnoteText)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footnoteText: String {
        let free = "\(OfflineFormat.bytes(freeBytes)) free on this phone."
        if target.isArea && area == nil { return "Move the map to place the square. " + free }
        guard let plan = plans[detail] else { return free }
        var text = "\(OfflineFormat.estimate(plan.estimatedBytes)). " + free
        if plan.trimmed {
            text += " That is the most one map holds, so close-ups cover your places and the biggest waters first. Pick a smaller region for more."
        }
        if !appState.mapManager.downloadOnCellular {
            text += " Downloads use Wi-Fi only."
        }
        return text
    }

    // MARK: Titles

    private var regionTitle: String {
        switch target {
        case .area: name
        case .region(let r): r.name
        case .country(let c): OfflineRegionCatalog.displayName(c)
        }
    }

    private var regionOver: String? {
        switch target {
        case .area: nil
        case .region(let r):
            OfflineRegionCatalog.country(r.countryId).map(OfflineRegionCatalog.displayName)
        case .country: "Country"
        }
    }

    private var regionSubtitle: String? {
        switch target {
        case .area: nil
        case .region(let r): "\(OfflineFormat.kind(r)), \(OfflineFormat.area(r.areaKm2))"
        case .country(let c): OfflineFormat.area(c.areaKm2)
        }
    }

    // MARK: Planning

    private var estimateScale: Double { appState.mapManager.estimateScale() }

    /// Room left after a margin, so a download never fills the phone.
    private var room: Int64 { freeBytes - 300_000_000 }

    private var canDownload: Bool {
        guard let plan = plans[detail], !plan.tooLarge, plan.estimatedBytes <= room, !planning else { return false }
        return !target.isArea || area != nil
    }

    /// Changes when the area moves enough to need new sizes.
    private var planKey: String {
        guard case .area = target, let a = area else { return "fixed" }
        return String(format: "%.4f,%.4f,%.4f,%.4f", a.minLat, a.minLon, a.maxLat, a.maxLon)
    }

    private var nameKey: String {
        guard case .area = target, let a = area else { return "none" }
        return String(format: "%.2f,%.2f", a.center.latitude, a.center.longitude)
    }

    private func plan() async {
        freeBytes = OfflinePackStore.freeBytes
        let scale = estimateScale
        switch target {
        case .area:
            guard let a = area else { plans = [:]; return }
            var out: [OfflineDetail: OfflinePlan] = [:]
            for option in [OfflineDetail.standard, .maximum] {
                out[option] = OfflinePlanner.areaPlan(a, detail: option, scale: scale)
            }
            plans = out
            if out[detail]?.tooLarge == true, out[.standard]?.tooLarge == false { detail = .standard }
        case .region, .country:
            guard plans.isEmpty else { return }
            planning = true
            let (id, bounds, areaKm2) = regionInfo
            let points = OfflineUserPlaces.load(appState).closeUpPoints
            let waters = OfflineUserPlaces.waters(in: bounds, appState: appState)
                .map { (OfflineCloseUp.water($0), CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            let result = await Task.detached(priority: .userInitiated) { () -> ([[CLLocationCoordinate2D]], [OfflineDetail: OfflinePlan]) in
                let rings = OfflineRegionCatalog.outline(id)
                let inside: (CLLocationCoordinate2D) -> Bool = { c in
                    bounds.contains(c) && (rings.isEmpty || OfflineRegionCatalog.contains(rings, c))
                }
                let places = points.filter(inside).map(OfflineCloseUp.place)
                let ws = waters.filter { inside($0.1) }.map { $0.0 }
                let shape = OfflinePlanner.Shape(bounds: bounds, rings: rings, areaKm2: areaKm2)
                var out: [OfflineDetail: OfflinePlan] = [:]
                for option in OfflineDetail.allCases {
                    out[option] = OfflinePlanner.regionPlan(shape, detail: option, places: places, waters: ws,
                                                            scale: scale)
                }
                return (rings, out)
            }.value
            outline = result.0
            plans = result.1
            planning = false
        }
    }

    private var regionInfo: (String, GeoRect, Double) {
        switch target {
        case .region(let r): (r.id, r.bounds, r.areaKm2)
        case .country(let c): (c.id, c.bounds, c.areaKm2)
        case .area(let rect, _): ("", rect ?? GeoRect(minLat: 0, minLon: 0, maxLat: 0, maxLon: 0), 0)
        }
    }

    /// A square gets the place's name from the map, until the angler types one.
    private func suggestName() async {
        guard case .area = target, !nameEdited, let a = area else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let found = await OfflinePlaceName.name(for: a.center), !nameEdited else { return }
        autoName = found
        name = found
    }

    private func start() {
        guard let plan = plans[detail] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        let kind: OfflinePack.Kind
        let regionId: String?
        let bounds: GeoRect
        switch target {
        case .area:
            guard let a = area else { return }
            finalName = trimmed.isEmpty ? "Map from \(OfflineFormat.date(.now))" : trimmed
            kind = .area
            regionId = nil
            bounds = a
        case .region(let r):
            finalName = trimmed.isEmpty ? r.name : trimmed
            kind = .region
            regionId = r.id
            bounds = r.bounds
        case .country(let c):
            finalName = trimmed.isEmpty ? OfflineRegionCatalog.displayName(c) : trimmed
            kind = .region
            regionId = c.id
            bounds = c.bounds
        }
        appState.mapManager.startDownload(name: finalName, kind: kind, regionId: regionId, bounds: bounds, plan: plan)
        Haptics.success()
        ToastCenter.shared.show("Downloading \(finalName)", style: .info, haptic: false)
        dismiss()
    }

    private func corners(_ r: GeoRect) -> [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: r.maxLat, longitude: r.minLon),
         CLLocationCoordinate2D(latitude: r.maxLat, longitude: r.maxLon),
         CLLocationCoordinate2D(latitude: r.minLat, longitude: r.maxLon),
         CLLocationCoordinate2D(latitude: r.minLat, longitude: r.minLon)]
    }
}
