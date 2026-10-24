import SwiftUI
import MapKit

// The pickers that open over the log catch composer: Caught at, Water, Gear,
// Session and Spot. Each edits the composer's state through bindings.

// MARK: - Shared chrome

/// The Explore sheet header: inline title, Cancel and Done, on the page
/// background with a grabber. Edits apply as they are made; Done keeps them
/// and Cancel runs `onCancel`, which puts back the values the sheet opened
/// with, then closes.
struct LogCatchSheetChrome<Content: View>: View {
    let title: String
    let detents: Set<PresentationDetent>
    let onCancel: () -> Void
    private let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, detents: Set<PresentationDetent> = [.large], onCancel: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detents = detents
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .detailTint(nil)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .dsSheet(detents)
    }
}

/// A selection mark for the trailing edge of a `CardRow`.
private struct RowCheckmark: View {
    let isOn: Bool

    var body: some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Selected")
        }
    }
}

/// The trailing value of a menu row, with the menu's up-down chevron.
private struct MenuValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.dsText3)
        }
    }
}

/// A text field laid out like a `CardRow`: icon tile, then the field.
private struct CardFieldRow: View {
    let placeholder: String
    let systemImage: String
    let tint: Color
    @Binding var text: String

    var body: some View {
        HStack(spacing: 14) {
            TintIcon(systemImage: systemImage, tint: tint)
            TextField(placeholder, text: $text)
                .font(.body)
                .foregroundStyle(Color.dsText)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
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
/// Under 100 pt tall it is a thumbnail, with the thumbnail radius.
struct LogCatchMapPreview: View {
    let coordinate: CLLocationCoordinate2D?
    var isPin: Bool = false
    var height: CGFloat = 120

    private var isThumbnail: Bool { height < 100 }

    var body: some View {
        Group {
            if let coordinate {
                Map(position: .constant(.camera(.init(centerCoordinate: coordinate, distance: isThumbnail ? 1500 : 2500)))) {
                    Annotation("", coordinate: coordinate) {
                        if isPin {
                            Image(systemName: "mappin.circle.fill")
                                .font(isThumbnail ? .body : .title)
                                .foregroundStyle(.white, Color.dsScoreSlow)
                        } else {
                            Circle()
                                .fill(DS.accent)
                                .frame(width: isThumbnail ? 12 : 18, height: isThumbnail ? 12 : 18)
                                .overlay(Circle().stroke(.white, lineWidth: isThumbnail ? 2 : 3))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
            } else {
                ZStack {
                    Color.dsFill
                    if isThumbnail {
                        Image(systemName: "location.slash")
                            .foregroundStyle(Color.dsText2)
                    } else {
                        Label("No location yet", systemImage: "location.slash")
                            .font(.subheadline)
                            .foregroundStyle(Color.dsText2)
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: isThumbnail ? DS.Radius.thumb : DS.Radius.card, style: .continuous))
    }
}

// MARK: - Caught at

struct LogCatchTimeSheet: View {
    @Binding var caughtAt: Date
    let photoDate: Date?
    /// Editing keeps the conditions saved with the catch, so the footnote
    /// promising an update is left out.
    var isEditing: Bool = false
    @AppStorage("use24HourTime") private var use24 = true
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52
    @State private var original: Date?

    private var days: [Date] {
        (0..<4).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    var body: some View {
        LogCatchSheetChrome(title: "Caught at", detents: [.medium, .large], onCancel: revert) {
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
                        Text(ForecastFormat.time(caughtAt, use24: use24))
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
                            .buttonHaptic(.selection)
                        }
                    }
                    .padding(.horizontal, DS.gutter)

                    VStack(alignment: .leading, spacing: 0) {
                        CardGroup {
                            DatePicker(selection: $caughtAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]) {
                                HStack(spacing: 14) {
                                    TintIcon(systemImage: "calendar", tint: .dsScoreLow)
                                    Text("Another day")
                                        .foregroundStyle(Color.dsText)
                                }
                            }
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.vertical, 10)
                            .frame(minHeight: 54)
                            if let photoDate {
                                Button {
                                    caughtAt = min(photoDate, .now)
                                    ToastCenter.shared.show("Time set from the photo", icon: "photo")
                                } label: {
                                    CardRow("Use the photo's time", systemImage: "photo", tint: DS.accent,
                                            value: ForecastFormat.time(photoDate, use24: use24))
                                }
                                .buttonStyle(.dsCardRow)
                            }
                        }
                        if !isEditing {
                            SectionFootnote("Conditions and the bite score update to match.")
                        }
                    }
                }
                .padding(.vertical, DS.Space.s3)
                .pageWidth()
            }
        }
        .onAppear { if original == nil { original = caughtAt } }
    }

    private func revert() {
        if let original { caughtAt = original }
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
        .buttonHaptic(.selection)
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
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 40
    @FocusState private var depthFocused: Bool
    @State private var original: (clarity: WaterClarity?, depth: String)?

    /// "Not set" first, so clarity can be cleared.
    private var clarityOptions: [WaterClarity?] {
        [nil] + WaterClarity.allCases.map { Optional($0) }
    }

    var body: some View {
        LogCatchSheetChrome(title: "Water", detents: [.medium, .large], onCancel: revert) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Clarity")
                    FilterChips(clarityOptions, selection: $clarity,
                                title: { $0?.label ?? "Not set" },
                                systemImage: { $0?.icon })
                    if let clarity {
                        SectionFootnote(clarity.detail)
                    }

                    SectionTitle("Depth")
                        .padding(.top, DS.Space.s6)
                    depthTile
                        .padding(.horizontal, DS.gutter)
                    if let problem = LogCatchView.depthIssue(text: depthText, imperial: imperial) {
                        LogCatchFootnote(text: problem, systemImage: "exclamationmark.triangle",
                                         tint: DS.ink(.dsScoreLow))
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s2)
                    }

                    SectionFootnote("Optional. Recording clarity sharpens your lure and colour suggestions.")
                        .padding(.top, DS.Space.s2)
                }
                .padding(.vertical, DS.Space.s3)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { depthFocused = false }
                }
            }
        }
        .onAppear { if original == nil { original = (clarity, depthText) } }
    }

    /// The size tile from the composer: type the number, or step it.
    private var depthTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Depth")
                .font(.footnote)
                .foregroundStyle(Color.dsText2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: $depthText)
                    .keyboardType(.decimalPad)
                    .focused($depthFocused)
                    .font(.system(size: numeralSize, weight: .bold, design: .rounded)) // ui-lint: allow, big numeral scaled with @ScaledMetric
                    .monospacedDigit()
                    .lineLimit(1)
                    // As wide as its digits, as in the composer's size tiles,
                    // so the unit sits right after the number.
                    .frame(minWidth: 0, maxWidth: CGFloat(max(depthText.count, 1)) * numeralSize * 0.64 + 6,
                           alignment: .leading)
                Text(imperial ? "ft" : "m")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsText2)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Space.s2) {
                depthButton(-1, systemImage: "minus", label: "Shallower")
                depthButton(1, systemImage: "plus", label: "Deeper")
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { depthFocused = true }
    }

    private func revert() {
        guard let original else { return }
        clarity = original.clarity
        depthText = original.depth
    }

    private func depthButton(_ direction: Double, systemImage: String, label: String) -> some View {
        Button {
            let step = imperial ? 1.0 : 0.5
            let next = max(0, (depthText.measurementValue ?? 0) + direction * step)
            withAnimation(DS.Motion.easeOut) {
                depthText = next > 0 ? LogCatchView.fieldText(next, maxDecimals: 1) : ""
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.dsFill2, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
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

    private struct Snapshot {
        var gearId: String?
        var rod, reel, lure, lureColor, technique: String
    }

    private enum Field: Hashable { case rod, reel, technique }

    @State private var original: Snapshot?
    /// Fields switched from the menu to typing, because the value isn't one
    /// of the listed choices.
    @State private var typing: Set<Field> = []

    var body: some View {
        LogCatchSheetChrome(title: "Gear", onCancel: revert) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Preset")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Chip("None", isSelected: selectedGearId == nil && isEmpty) { applyNone() }
                                ForEach(presets) { preset in
                                    Chip(preset.name, isSelected: selectedGearId == preset.id) { apply(preset) }
                                }
                            }
                            .padding(.horizontal, DS.gutter)
                            .padding(.vertical, 4)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }

                    CardSection("Rod and reel") {
                        gearRow(.rod, title: "Rod", systemImage: "line.diagonal", tint: .brown, selection: $rod)
                        if typing.contains(.rod) {
                            CardFieldRow(placeholder: "Type the rod", systemImage: "pencil", tint: .brown, text: $rod)
                        }
                        gearRow(.reel, title: "Reel", systemImage: "circle.circle", tint: .indigo, selection: $reel)
                        if typing.contains(.reel) {
                            CardFieldRow(placeholder: "Type the reel", systemImage: "pencil", tint: .indigo, text: $reel)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Lure or bait")
                        if !lureCandidates.isEmpty {
                            lureCarousel
                                .padding(.bottom, DS.Space.s2)
                        }
                        CardGroup {
                            CardFieldRow(placeholder: lureCandidates.isEmpty ? "Lure or bait" : "Or type one",
                                         systemImage: "fish", tint: .orange, text: $lure)
                            if !lure.isEmpty {
                                CardFieldRow(placeholder: "Lure colour", systemImage: "paintpalette.fill", tint: .pink,
                                             text: $lureColor)
                            }
                        }
                    }

                    CardSection("Technique", note: "Changes here only apply to this catch.") {
                        techniqueRow
                        if typing.contains(.technique) {
                            CardFieldRow(placeholder: "Type the technique", systemImage: "pencil", tint: .teal,
                                         text: $technique)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s3)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            guard original == nil else { return }
            original = Snapshot(gearId: selectedGearId, rod: rod, reel: reel, lure: lure,
                                lureColor: lureColor, technique: technique)
            // Resume typing for a value that isn't one of the listed choices.
            if !rod.isEmpty, !owned(.rod).contains(where: { $0.displayName == rod }) { typing.insert(.rod) }
            if !reel.isEmpty, !owned(.reel).contains(where: { $0.displayName == reel }) { typing.insert(.reel) }
            if !technique.isEmpty, !FishingTechniques.presets.contains(technique) { typing.insert(.technique) }
        }
    }

    private func revert() {
        guard let original else { return }
        selectedGearId = original.gearId
        rod = original.rod
        reel = original.reel
        lure = original.lure
        lureColor = original.lureColor
        technique = original.technique
    }

    private func owned(_ category: OwnedGear.Category) -> [OwnedGear] {
        ownedGear.filter { $0.category == category }
    }

    /// A rod or reel: a menu of the tackle box when there is any, otherwise
    /// a field to type in.
    @ViewBuilder
    private func gearRow(_ field: Field, title: String, systemImage: String, tint: Color,
                         selection: Binding<String>) -> some View {
        let category: OwnedGear.Category = field == .rod ? .rod : .reel
        let items = owned(category)
        if items.isEmpty {
            CardFieldRow(placeholder: title, systemImage: systemImage, tint: tint, text: selection)
        } else {
            Menu {
                Picker(title, selection: menuChoice(field, selection: selection,
                                                    known: items.map(\.displayName))) {
                    Text("None").tag("")
                    ForEach(items) { item in
                        Text(item.displayName).tag(item.displayName)
                    }
                    Text("Type one").tag(GearFieldTag.custom)
                }
            } label: {
                CardRow(title, systemImage: systemImage, tint: tint) {
                    MenuValue(text: typing.contains(field) ? "Typed"
                                  : (selection.wrappedValue.isEmpty ? "None" : selection.wrappedValue))
                }
            }
            .buttonStyle(.dsCardRow)
        }
    }

    private var techniqueRow: some View {
        Menu {
            Picker("Technique", selection: menuChoice(.technique, selection: $technique,
                                                      known: FishingTechniques.presets)) {
                Text("None").tag("")
                ForEach(FishingTechniques.presets, id: \.self) { technique in
                    Text(FishingTechniques.label(for: technique)).tag(technique)
                }
                Text("Type one").tag(GearFieldTag.custom)
            }
        } label: {
            CardRow("Technique", systemImage: "figure.fishing", tint: .teal) {
                MenuValue(text: typing.contains(.technique) ? "Typed"
                              : (technique.isEmpty ? "None" : FishingTechniques.label(for: technique)))
            }
        }
        .buttonStyle(.dsCardRow)
    }

    /// The menu's selection: "Type one" switches the field to typing and
    /// keeps a typed value; a listed choice switches typing off.
    private func menuChoice(_ field: Field, selection: Binding<String>, known: [String]) -> Binding<String> {
        Binding(
            get: { typing.contains(field) ? GearFieldTag.custom : selection.wrappedValue },
            set: { newValue in
                Haptics.selection()
                if newValue == GearFieldTag.custom {
                    typing.insert(field)
                    if known.contains(selection.wrappedValue) { selection.wrappedValue = "" }
                } else {
                    typing.remove(field)
                    selection.wrappedValue = newValue
                }
            }
        )
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
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, DS.Space.s1)
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
                        .foregroundStyle(DS.ink(.dsScoreGood))
                }
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
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
        typing = []
        if !rod.isEmpty, !owned(.rod).contains(where: { $0.displayName == rod }) { typing.insert(.rod) }
        if !reel.isEmpty, !owned(.reel).contains(where: { $0.displayName == reel }) { typing.insert(.reel) }
        if !technique.isEmpty, !FishingTechniques.presets.contains(technique) { typing.insert(.technique) }
    }

    private func applyNone() {
        selectedGearId = nil
        rod = ""; reel = ""; lure = ""; lureColor = ""; technique = ""
        typing = []
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
    @AppStorage("use24HourTime") private var use24 = true
    @State private var original: String??

    private var recent: [Trip] {
        trips.filter { !$0.isPlanned && $0.id != activeTrip?.id }
            .sorted { $0.startDate > $1.startDate }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        LogCatchSheetChrome(title: "Session", detents: [.medium, .large], onCancel: revert) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let activeTrip {
                        CardSection(note: "Catches made while it records join it.") {
                            CardRow("Current session",
                                    subtitle: "Started \(ForecastFormat.time(activeTrip.startDate, use24: use24))",
                                    systemImage: "record.circle", tint: .dsScoreGood) {
                                RowCheckmark(isOn: true)
                            }
                        }
                    } else {
                        CardSection(recent.isEmpty ? nil : "Recent sessions") {
                            ForEach(recent) { trip in
                                row(trip.id, title: trip.name, subtitle: range(trip),
                                    systemImage: "figure.fishing", tint: .dsScoreGood)
                            }
                            row(nil, title: "None", subtitle: "Keep it as a single catch",
                                systemImage: "fish.fill", tint: DS.accent)
                        }
                        if canStart {
                            Button {
                                onStart()
                                dismiss()
                            } label: {
                                Label("Start session", systemImage: "play.fill")
                            }
                            .buttonStyle(.dsTonal)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s6)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s3)
                .pageWidth()
            }
        }
        .onAppear { if original == nil { original = .some(selectedTripId) } }
    }

    private func revert() {
        if let original { selectedTripId = original }
    }

    private func row(_ id: String?, title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        Button {
            selectedTripId = id
        } label: {
            CardRow(title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
                RowCheckmark(isOn: selectedTripId == id)
            }
        }
        .buttonStyle(.dsCardRow)
        .buttonHaptic(.selection)
        .accessibilityAddTraits(selectedTripId == id ? .isSelected : [])
    }

    private func range(_ trip: Trip) -> String {
        let day = LogbookFormat.relativeDay(trip.startDate)
        let start = ForecastFormat.time(trip.startDate, use24: use24)
        guard let end = trip.endDate else { return "\(day), \(start)" }
        return "\(day), \(start) to \(ForecastFormat.time(end, use24: use24))"
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
    /// Spots named in this composer, written only with the catch.
    var pendingSpotIds: Set<String> = []
    /// Set when location is off: asks for it, or opens Settings.
    var onTurnOnLocation: (() -> Void)? = nil
    var onSaveSpot: () -> Void

    private struct Snapshot {
        var mode: LogCatchView.LocationMode
        var spotId: String?
        var pin: CLLocationCoordinate2D?
        var name: String
    }

    @State private var original: Snapshot?
    @State private var showingPinPicker = false
    @State private var naming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        LogCatchSheetChrome(title: "Spot", onCancel: revert) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    FilterChips(LogCatchView.LocationMode.allCases, selection: $mode,
                                title: { $0.rawValue }, systemImage: { modeIcon($0) })

                    switch mode {
                    case .current: hereContent
                    case .spot: savedContent
                    case .pin: pinContent
                    }
                }
                .padding(.vertical, DS.Space.s3)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .haptic(.selection, trigger: mode)
            .sheet(isPresented: $showingPinPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
        }
        .onAppear {
            if original == nil {
                original = Snapshot(mode: mode, spotId: selectedSpotId, pin: pinCoordinate, name: newSpotName)
            }
        }
    }

    private func revert() {
        guard let original else { return }
        mode = original.mode
        selectedSpotId = original.spotId
        pinCoordinate = original.pin
        newSpotName = original.name
    }

    private func modeIcon(_ mode: LogCatchView.LocationMode) -> String {
        switch mode {
        case .current: "location.fill"
        case .spot: "bookmark.fill"
        case .pin: "mappin"
        }
    }

    @ViewBuilder
    private var hereContent: some View {
        if let loc = currentLocation {
            LogCatchMapPreview(coordinate: loc.coordinate, height: 200)
                .padding(.horizontal, DS.gutter)
            LogCatchFootnote(text: "Using your location. Accurate to \(max(1, Int(loc.horizontalAccuracy))) m.",
                             systemImage: "location.fill")
                .padding(.horizontal, DS.gutter)
        } else if let onTurnOnLocation {
            CardGroup {
                Button(action: onTurnOnLocation) {
                    CardRow("Turn on location", subtitle: "Location is off, so the catch has no place yet.",
                            systemImage: "location.fill", tint: DS.accent, chevron: true)
                }
                .buttonStyle(.dsCardRow)
                Button { mode = .pin } label: {
                    CardRow("Drop a pin", systemImage: "mappin", tint: .dsScoreSlow, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            }
        } else {
            InlineEmpty(systemImage: "location", text: "Waiting for your location.",
                        actionTitle: "Drop a pin") { mode = .pin }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if spots.isEmpty {
            InlineEmpty(systemImage: "bookmark", text: "No saved spots yet. Drop a pin and name it as a new spot.",
                        actionTitle: "Drop a pin") { mode = .pin }
        } else {
            CardGroup {
                ForEach(spots) { spot in
                    Button {
                        selectedSpotId = spot.id
                    } label: {
                        CardRow(spot.name, subtitle: pendingSpotIds.contains(spot.id) ? "New, not saved yet" : nil,
                                systemImage: "bookmark.fill", tint: DS.accent) {
                            RowCheckmark(isOn: selectedSpotId == spot.id)
                        }
                    }
                    .buttonStyle(.dsCardRow)
                    .buttonHaptic(.selection)
                    .accessibilityAddTraits(selectedSpotId == spot.id ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var pinContent: some View {
        Button { showingPinPicker = true } label: {
            LogCatchMapPreview(coordinate: pinCoordinate ?? currentLocation?.coordinate, isPin: true, height: 200)
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.gutter)
        .accessibilityLabel("Move the pin")
        Button { showingPinPicker = true } label: {
            Label(pinCoordinate == nil ? "Choose on the map" : "Move the pin", systemImage: "hand.point.up.left")
        }
        .buttonStyle(.dsTonal)
        .padding(.horizontal, DS.gutter)

        VStack(alignment: .leading, spacing: 0) {
            CardGroup {
                if naming {
                    HStack(spacing: 14) {
                        TintIcon(systemImage: "bookmark", tint: DS.accent)
                        TextField("Name this spot", text: $newSpotName)
                            .font(.body)
                            .foregroundStyle(Color.dsText)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, 10)
                    .frame(minHeight: 54)
                } else {
                    Button {
                        naming = true
                        nameFocused = true
                    } label: {
                        CardRow("Save as a new spot", systemImage: "bookmark", tint: DS.accent, chevron: true)
                    }
                    .buttonStyle(.dsCardRow)
                    .disabled(pinCoordinate == nil)
                }
            }
            if naming {
                Button(action: save) {
                    Label("Save spot", systemImage: "bookmark.fill")
                }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
                .disabled(newSpotName.trimmingCharacters(in: .whitespaces).isEmpty || pinCoordinate == nil)
            }
            SectionFootnote("A new spot is saved when you save the catch.")
        }
        .padding(.top, DS.Space.s3)
    }

    private func save() {
        guard !newSpotName.trimmingCharacters(in: .whitespaces).isEmpty, pinCoordinate != nil else { return }
        onSaveSpot()
        naming = false
    }
}
