import SwiftUI
import MapKit

// The pickers that open over the log catch composer: Caught at, Water, Gear,
// Session and Spot. Each edits the composer's state through bindings.

// MARK: - Shared chrome

/// Title, close button and an optional Done button pinned to the bottom.
struct LogCatchSheetChrome<Content: View>: View {
    let title: String
    var showsDone: Bool = true
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .scrollEdgeEffectStyle(.hard, for: .top)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if showsDone {
                        Button("Done") { dismiss() }
                            .buttonStyle(.dsPrimary)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s2)
                            .padding(.bottom, DS.Space.s2)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// A grouped list row: tinted icon, title, trailing value, optional chevron.
struct LogCatchListRow: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .dsText2
    var value: String? = nil
    var chevron: Bool = false
    var checked: Bool = false
    /// A lure or bait name to show as a small picture before the value.
    var lureArt: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
            }
            Text(title)
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if let lureArt, !lureArt.isEmpty {
                LureArtView(name: lureArt, size: 28)
                    .accessibilityHidden(true)
            }
            if let value {
                Text(value)
                    .foregroundStyle(Color.dsText2)
                    .lineLimit(1)
            }
            if checked {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.dsText3)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// Small footnote with a leading icon, used under sections.
struct LogCatchFootnote: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .dsText2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(tint == .dsText2 ? Color.dsText2 : tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The map tile used on the composer and in the spot sheet. Not interactive.
struct LogCatchMapPreview: View {
    let coordinate: CLLocationCoordinate2D?
    var isPin: Bool = false
    var height: CGFloat = 120

    var body: some View {
        Group {
            if let coordinate {
                Map(position: .constant(.camera(.init(centerCoordinate: coordinate, distance: 2500)))) {
                    Annotation("", coordinate: coordinate) {
                        if isPin {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, Color.dsScoreSlow)
                        } else {
                            Circle()
                                .fill(DS.accent)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
            } else {
                ZStack {
                    Color.dsFill
                    Label("Waiting for your location", systemImage: "location.slash")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - Caught at

struct LogCatchTimeSheet: View {
    @Binding var caughtAt: Date
    let photoDate: Date?
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52

    private var days: [Date] {
        (0..<4).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    var body: some View {
        LogCatchSheetChrome(title: "Caught at") {
            ScrollView {
                VStack(spacing: DS.Space.s4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            ForEach(days, id: \.self) { day in
                                Chip(dayLabel(day), isSelected: Calendar.current.isDate(day, inSameDayAs: caughtAt)) {
                                    setDay(day)
                                }
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }

                    HStack(spacing: 22) {
                        stepButton(-60, systemImage: "minus", label: "An hour earlier")
                        Text(caughtAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: clockSize, weight: .bold, design: .rounded)) // ui-lint: allow, clock numeral scaled with @ScaledMetric
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(DS.Motion.easeOut, value: caughtAt)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        stepButton(60, systemImage: "plus", label: "An hour later")
                    }
                    .padding(.top, DS.Space.s2)

                    HStack(spacing: DS.Space.s2) {
                        ForEach([-15, -5, 5, 15], id: \.self) { m in
                            Button { shift(minutes: m) } label: {
                                Text("\(m > 0 ? "+" : "−")\(abs(m)) min")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.dsText)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(Color.dsTonal, in: Capsule())
                            }
                            .buttonStyle(.dim)
                        }
                    }
                    .padding(.horizontal, DS.gutter)

                    VStack(spacing: 0) {
                        DatePicker(selection: $caughtAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]) {
                            Label("Another day", systemImage: "calendar")
                                .foregroundStyle(Color.dsText)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        if let photoDate {
                            Divider().padding(.leading, 14)
                            Button {
                                caughtAt = min(photoDate, .now)
                                ToastCenter.shared.show("Time set from the photo", icon: "photo")
                            } label: {
                                LogCatchListRow(title: "Use the photo's time", systemImage: "photo", tint: DS.accent,
                                                value: photoDate.formatted(date: .omitted, time: .shortened))
                            }
                            .buttonStyle(.dim)
                        }
                    }
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .padding(.horizontal, DS.gutter)

                    LogCatchFootnote(text: "Conditions and the bite score update to match.")
                        .padding(.horizontal, DS.gutter)
                }
                .padding(.vertical, DS.Space.s3)
            }
            .sensoryFeedback(.selection, trigger: caughtAt)
        }
        .presentationDetents([.medium, .large])
    }

    private func stepButton(_ minutes: Int, systemImage: String, label: String) -> some View {
        Button { shift(minutes: minutes) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .frame(width: 44, height: 40)
                .background(Color.dsFill2, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.dim)
        .accessibilityLabel(label)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func shift(minutes: Int) {
        let t = caughtAt.addingTimeInterval(Double(minutes) * 60)
        guard t <= .now else {
            ToastCenter.shared.show("A catch can't be in the future", style: .info, icon: "clock")
            return
        }
        caughtAt = t
    }

    private func setDay(_ day: Date) {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: caughtAt)
        var parts = cal.dateComponents([.year, .month, .day], from: day)
        parts.hour = time.hour
        parts.minute = time.minute
        guard let date = cal.date(from: parts) else { return }
        caughtAt = min(date, .now)
    }
}

// MARK: - Water

struct LogCatchWaterSheet: View {
    @Binding var clarity: WaterClarity?
    @Binding var depthText: String
    let imperial: Bool

    private var depthLabel: String {
        guard let d = depthText.measurementValue, d > 0 else { return "Not set" }
        return "\(String(format: d == d.rounded() ? "%.0f" : "%.1f", d)) \(imperial ? "ft" : "m")"
    }

    var body: some View {
        LogCatchSheetChrome(title: "Water") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Clarity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dsText2)
                    ClarityPicker(selection: $clarity, allowsDeselect: true)

                    Text("Depth")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dsText2)
                        .padding(.top, DS.Space.s3)
                    HStack {
                        Text(depthLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(depthText.measurementValue == nil ? Color.dsText2 : Color.dsText)
                            .contentTransition(.numericText())
                        Spacer()
                        depthButton(-1, systemImage: "minus", label: "Shallower")
                        depthButton(1, systemImage: "plus", label: "Deeper")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))

                    LogCatchFootnote(text: "Optional. Recording clarity sharpens your lure and colour suggestions.")
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, DS.Space.s3)
            }
            .sensoryFeedback(.selection, trigger: clarity)
        }
        .presentationDetents([.medium, .large])
    }

    private func depthButton(_ direction: Double, systemImage: String, label: String) -> some View {
        Button {
            let step = imperial ? 1.0 : 0.5
            let next = max(0, (depthText.measurementValue ?? 0) + direction * step)
            withAnimation(DS.Motion.easeOut) {
                depthText = next > 0 ? String(format: next == next.rounded() ? "%.0f" : "%.1f", next) : ""
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .frame(width: 44, height: 36)
                .background(Color.dsFill2, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        }
        .buttonStyle(.dim)
        .accessibilityLabel(label)
    }
}

// MARK: - Gear

struct LogCatchGearSheet: View {
    let presets: [GearLoadout]
    let ownedGear: [OwnedGear]
    @Binding var selectedGearId: String?
    @Binding var rod: String
    @Binding var reel: String
    @Binding var lure: String
    @Binding var lureColor: String
    @Binding var technique: String

    var body: some View {
        LogCatchSheetChrome(title: "Gear") {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            Chip("None", isSelected: selectedGearId == nil && isEmpty) { applyNone() }
                            ForEach(presets) { preset in
                                Chip(preset.name, isSelected: selectedGearId == preset.id) { apply(preset) }
                            }
                            if selectedGearId == nil && !isEmpty {
                                Chip("Custom", isSelected: true) {}
                            }
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s2)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Preset")
                }

                Section {
                    field(.rod, selection: $rod, placeholder: "Rod")
                    field(.reel, selection: $reel, placeholder: "Reel")
                }

                Section {
                    if !lureCandidates.isEmpty {
                        lureCarousel
                            .listRowInsets(EdgeInsets())
                    }
                    TextField(lureCandidates.isEmpty ? "Lure or bait" : "Or type one", text: $lure)
                    if !lure.isEmpty {
                        TextField("Lure colour", text: $lureColor)
                    }
                } header: {
                    Text("Lure or bait")
                }

                Section {
                    TechniquePicker(selection: $technique)
                } footer: {
                    Text("Changes here only apply to this catch.")
                }
            }
            .sensoryFeedback(.selection, trigger: selectedGearId)
        }
        .presentationDetents([.large])
    }

    private struct LureChoice: Identifiable {
        let name: String
        let owned: Bool
        var id: String { name.lowercased() }
    }

    /// What can be picked with one tap: the lures and bait in the tackle
    /// box, then lures saved in presets.
    private var lureCandidates: [LureChoice] {
        var seen = Set<String>()
        var out: [LureChoice] = []
        let owned = ownedGear.filter { $0.category == .lure || $0.category == .bait }.map(\.displayName)
        let fromPresets = presets.compactMap(\.lure).filter { !$0.isEmpty }
        for name in owned where seen.insert(name.lowercased()).inserted {
            out.append(LureChoice(name: name, owned: true))
        }
        for name in fromPresets where seen.insert(name.lowercased()).inserted {
            out.append(LureChoice(name: name, owned: false))
        }
        return out
    }

    private var lureCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(lureCandidates) { item in
                    lureTile(item.name, owned: item.owned)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
        }
    }

    private func lureTile(_ name: String, owned: Bool) -> some View {
        let selected = lure == name
        return Button {
            withAnimation(DS.Motion.easeOut) { lure = selected ? "" : name }
        } label: {
            VStack(spacing: DS.Space.s1) {
                LureArtView(name: name, size: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                            .strokeBorder(selected ? DS.accent : Color.clear, lineWidth: 3)
                    }
                Text(name)
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.dsText : Color.dsText2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if owned {
                    Text("In your box")
                        .font(.caption)
                        .foregroundStyle(Color.dsScoreGood)
                }
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .accessibilityLabel(owned ? "\(name), in your tackle box" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var isEmpty: Bool {
        rod.isEmpty && reel.isEmpty && lure.isEmpty && lureColor.isEmpty && technique.isEmpty
    }

    private func apply(_ preset: GearLoadout) {
        selectedGearId = preset.id
        rod = preset.rod ?? ""
        reel = preset.reel ?? ""
        lure = preset.lure ?? ""
        lureColor = preset.lureColor ?? ""
        technique = preset.technique ?? ""
    }

    private func applyNone() {
        selectedGearId = nil
        rod = ""; reel = ""; lure = ""; lureColor = ""; technique = ""
    }

    @ViewBuilder
    private func field(_ category: OwnedGear.Category, selection: Binding<String>, placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            TextField(placeholder, text: selection)
        } else {
            GearFieldPicker(placeholder: placeholder, items: items, selection: selection)
        }
    }
}

// MARK: - Session

struct LogCatchSessionSheet: View {
    let trips: [Trip]
    let activeTrip: Trip?
    @Binding var selectedTripId: String?
    let canStart: Bool
    var onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var recent: [Trip] {
        trips.filter { !$0.isPlanned && $0.id != activeTrip?.id }
            .sorted { $0.startDate > $1.startDate }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        LogCatchSheetChrome(title: "Session", showsDone: false) {
            List {
                if let activeTrip {
                    Section {
                        row(activeTrip.id, title: "Current session",
                            subtitle: "Started \(activeTrip.startDate.formatted(date: .omitted, time: .shortened))")
                    } footer: {
                        Text("Catches made while it records join it.")
                    }
                } else {
                    Section {
                        ForEach(recent) { trip in
                            row(trip.id, title: trip.name, subtitle: range(trip))
                        }
                        row(nil, title: "None", subtitle: "Keep it as a single catch")
                    }
                    if canStart {
                        Section {
                            Button {
                                onStart()
                                dismiss()
                            } label: {
                                Label("Start a session now", systemImage: "play.fill")
                                    .foregroundStyle(Color.dsText)
                            }
                            .tint(Color.dsScoreGood)
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedTripId)
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ id: String?, title: String, subtitle: String) -> some View {
        Button {
            selectedTripId = id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.dsText)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.dsText2)
                }
                Spacer()
                if (activeTrip?.id ?? selectedTripId) == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .disabled(activeTrip != nil)
    }

    private func range(_ trip: Trip) -> String {
        let day = trip.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let start = trip.startDate.formatted(date: .omitted, time: .shortened)
        guard let end = trip.endDate else { return "\(day), \(start)" }
        return "\(day), \(start) to \(end.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Spot

struct LogCatchSpotSheet: View {
    @Binding var mode: LogCatchView.LocationMode
    let spots: [Spot]
    @Binding var selectedSpotId: String?
    @Binding var pinCoordinate: CLLocationCoordinate2D?
    let currentLocation: CLLocation?
    @Binding var newSpotName: String
    var onSaveSpot: () -> Void

    @State private var showingPinPicker = false
    @State private var naming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        LogCatchSheetChrome(title: "Spot") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Picker("Location", selection: $mode) {
                        ForEach(LogCatchView.LocationMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .current: hereContent
                    case .spot: savedContent
                    case .pin: pinContent
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, DS.Space.s3)
            }
            .sensoryFeedback(.selection, trigger: mode)
            .sheet(isPresented: $showingPinPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var hereContent: some View {
        LogCatchMapPreview(coordinate: currentLocation?.coordinate, height: 200)
        if let loc = currentLocation {
            LogCatchFootnote(text: "Using your location. Accurate to \(max(1, Int(loc.horizontalAccuracy))) m.",
                             systemImage: "location.fill")
        } else {
            LogCatchFootnote(text: "Waiting for your location. You can also drop a pin.", systemImage: "location.slash")
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if spots.isEmpty {
            ContentUnavailableView("No saved spots yet", systemImage: "bookmark",
                                   description: Text("Drop a pin and save it as a new spot."))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button {
                        selectedSpotId = spot.id
                    } label: {
                        LogCatchListRow(title: spot.name, systemImage: "bookmark.fill", tint: DS.accent,
                                        checked: selectedSpotId == spot.id)
                    }
                    .buttonStyle(.dim)
                }
            }
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .sensoryFeedback(.selection, trigger: selectedSpotId)
        }
    }

    @ViewBuilder
    private var pinContent: some View {
        Button { showingPinPicker = true } label: {
            LogCatchMapPreview(coordinate: pinCoordinate ?? currentLocation?.coordinate, isPin: true, height: 200)
        }
        .buttonStyle(.dim)
        .accessibilityLabel("Move the pin")
        Button { showingPinPicker = true } label: {
            Label(pinCoordinate == nil ? "Choose on the map" : "Move the pin", systemImage: "hand.point.up.left")
        }
        .buttonStyle(.dsTonal)

        if naming {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "bookmark")
                    .foregroundStyle(Color.dsText2)
                TextField("Name this spot", text: $newSpotName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            Button(action: save) {
                Label("Save spot", systemImage: "bookmark.fill")
            }
            .buttonStyle(.dsTonal)
            .disabled(newSpotName.trimmingCharacters(in: .whitespaces).isEmpty || pinCoordinate == nil)
        } else {
            Button {
                naming = true
                nameFocused = true
            } label: {
                LogCatchListRow(title: "Save as a new spot", systemImage: "bookmark", tint: DS.accent, chevron: true)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.dim)
            .disabled(pinCoordinate == nil)
        }
    }

    private func save() {
        guard !newSpotName.trimmingCharacters(in: .whitespaces).isEmpty, pinCoordinate != nil else { return }
        onSaveSpot()
        naming = false
    }
}
