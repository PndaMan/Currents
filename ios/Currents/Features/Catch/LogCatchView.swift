import SwiftUI
import PhotosUI
import MapKit
import ImageIO

/// One photo in the composer: a fresh image, or one already saved with the
/// catch being edited.
struct LogCatchPhoto: Identifiable {
    let id = UUID()
    var image: UIImage
    var savedPath: String? = nil
}

/// The log catch composer: one full-screen form. The camera opens first, the
/// photo shrinks into the cover while species ID runs, and the identified
/// species becomes the title. Editing an existing catch reuses it.
struct LogCatchView: View {
    /// When set, the saved catch publishes into this group trip's live feed —
    /// used by the group screen so members who joined mid-trip (no linked GPS
    /// session) still put fish on the board.
    let groupCodeOverride: String?
    private let presetSpecies: Species?
    private let editing: CatchDetail?
    private let onEditSave: ((Catch) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("units") private var units = "metric"
    /// Length/weight fields hold values in the user's chosen unit; converted to
    /// metric (the stored canonical) at save.
    private var imperial: Bool { units == "imperial" }
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 40

    /// New catch. `presetSpecies` opens the composer with that species chosen
    /// and skips the camera (used from a species page).
    init(groupCodeOverride: String? = nil, presetSpecies: Species? = nil) {
        self.groupCodeOverride = groupCodeOverride
        self.presetSpecies = presetSpecies
        self.editing = nil
        self.onEditSave = nil
        _showingCamera = State(initialValue: presetSpecies == nil)
    }

    /// Edit an existing catch. `onSave` receives the updated record to persist
    /// and re-publish, as EditCatchSheet did.
    init(editing detail: CatchDetail, onSave: @escaping (Catch) -> Void) {
        self.groupCodeOverride = nil
        self.presetSpecies = nil
        self.editing = detail
        self.onEditSave = onSave
        _showingCamera = State(initialValue: false)
    }

    private var isEditing: Bool { editing != nil }

    // Photos (up to 10)
    @State private var photos: [LogCatchPhoto] = []
    @State private var unloadablePaths: [String] = []
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var showingCamera: Bool
    @State private var cameraAdding = false
    @State private var frozenFrame: UIImage?
    @State private var photoDate: Date?
    @State private var showingARMeasure = false
    @State private var measured = false
    @Namespace private var coverSpace

    // ML — BioCLIP only; no guessing fallbacks.
    @State private var speciesMatches: [SpeciesMatch] = []
    @State private var isClassifying = false
    @State private var autoSelectedFromML = false
    @State private var modelReady = true
    @State private var hasScanned = false
    /// The top match was weak or too close to the runner-up — don't auto-fill;
    /// ask the angler to confirm.
    @State private var lowConfidence = false

    // Catch data
    @State private var selectedSpeciesId: Int64?
    @State private var selectedSpeciesName: String = ""
    @State private var selectedSpotId: String?
    @State private var selectedTripId: String?
    @State private var lengthCm: String = ""
    @State private var weightKg: String = ""
    @State private var waterClarity: WaterClarity?
    @State private var depthText: String = ""
    @State private var released = true
    @State private var isFavorite = false
    @State private var selectedGearId: String?
    @State private var notes: String = ""
    @State private var caughtAt = Date.now
    @State private var isSaving = false   // guards against double-tap → duplicate catches

    // Gear fields
    @State private var gearRod = ""
    @State private var gearReel = ""
    @State private var gearLure = ""
    @State private var gearLureColor = ""
    @State private var gearTechnique = ""

    // Location
    @State private var locationMode: LocationMode = .current
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var newSpotName = ""

    // Sharing (new catches only)
    @State private var crews: [CommunityService.Crew] = []
    @State private var crewShare: [String: Bool] = [:]
    @State private var shareToINat = true

    // Presentation
    @State private var activeSheet: ComposerSheet?
    @State private var showingDiscard = false
    @State private var baseline: String?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?

    // Data
    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var allTrips: [Trip] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var caughtIds: Set<Int64> = []
    @State private var priors: [Catch] = []
    @State private var conditions: Conditions?

    enum LocationMode: String, CaseIterable {
        case current = "Here"
        case spot = "Saved spot"
        case pin = "Drop pin"
    }

    private enum ComposerSheet: String, Identifiable {
        case species, time, gear, water, session, spot
        var id: String { rawValue }
    }

    private enum Field: Hashable { case length, weight, notes }

    private struct Conditions {
        var waterC: Double?
        var windKmh: Double?
        var windDeg: Double?
        var pressureHpa: Double?
        var score: Int?
    }

    private var selectedSpecies: Species? {
        guard let id = selectedSpeciesId else { return nil }
        return allSpecies.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cover
                    titleBlock
                        .padding(.top, 18)
                    actionRow
                        .padding(.top, DS.Space.s4)
                    sizeSection
                        .padding(.top, 28)
                    spotSection
                        .padding(.top, 28)
                    detailsSection
                        .padding(.top, 28)
                    conditionsSection
                        .padding(.top, 28)
                    notesSection
                        .padding(.top, 28)
                    sharingSection
                }
                .padding(.bottom, DS.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
            .detailTint(pageTint)
            .navigationTitle(isEditing ? "Edit catch" : "New catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openCamera() } label: { Image(systemName: "camera") }
                        .accessibilityLabel("Add a photo")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .overlay {
            if showingCamera {
                cameraLayer
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(isEditing ? "Discard your changes?" : "Discard this catch?",
                            isPresented: $showingDiscard, titleVisibility: .visible) {
            Button(isEditing ? "Discard changes" : "Discard catch", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(isEditing ? "The catch stays as it was." : "Nothing has been saved yet.")
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .fullScreenCover(isPresented: $showingARMeasure) {
            ARMeasureView { cm in
                lengthCm = formatNumber(imperial ? cm / 2.54 : cm)
                measured = true
                ToastCenter.shared.show("Length set to \(Units.length(cm: cm, imperial: imperial))", icon: "ruler")
            }
        }
        .task { await load() }
        .task(id: conditionsKey) { await refreshConditions() }
        .onChange(of: libraryItems) { _, items in loadPhotos(items) }
        .onChange(of: selectedSpeciesId) { _, _ in loadPriors() }
        // Declarative feedback for the discrete toggles.
        .sensoryFeedback(.selection, trigger: released)
        .sensoryFeedback(.selection, trigger: isFavorite)
        .sensoryFeedback(.success, trigger: selectedSpeciesId) { old, new in old == nil && new != nil }
    }

    // MARK: - Camera

    private var cameraLayer: some View {
        ZStack {
            LogCatchCameraView(
                adding: cameraAdding,
                photoCount: photos.count,
                libraryItems: $libraryItems,
                librarySlots: 10 - photos.count,
                onCapture: handleCapture,
                onClose: {
                    if cameraAdding { hideCamera() } else { close() }
                },
                onSkip: {
                    hideCamera()
                    if !cameraAdding && selectedSpeciesId == nil {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            activeSheet = .species
                        }
                    }
                }
            )
            if let frozenFrame {
                Image(uiImage: frozenFrame)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .matchedGeometryEffect(id: "cover", in: coverSpace)
                    .ignoresSafeArea()
            }
        }
    }

    private func openCamera() {
        guard photos.count < 10 else {
            ToastCenter.shared.show("Up to 10 photos per catch", style: .info, icon: "photo.on.rectangle")
            return
        }
        focusedField = nil
        cameraAdding = !photos.isEmpty
        frozenFrame = nil
        withAnimation(DS.Motion.softSpring) { showingCamera = true }
    }

    private func hideCamera() {
        withAnimation(.easeOut(duration: DS.Motion.med)) { showingCamera = false }
    }

    /// A shutter press. The first photo freezes in the viewfinder, then
    /// shrinks into the cover while species ID runs.
    private func handleCapture(_ image: UIImage) {
        guard photos.count < 10 else {
            ToastCenter.shared.show("Up to 10 photos per catch", style: .info, icon: "photo.on.rectangle")
            return
        }
        let photo = LogCatchPhoto(image: image)
        if cameraAdding || !photos.isEmpty {
            photos.append(photo)
            hideCamera()
            ToastCenter.shared.show("Photo added, \(photos.count) of 10", icon: "photo")
            return
        }
        if reduceMotion {
            photos.append(photo)
            hideCamera()
        } else {
            frozenFrame = image
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.44)) {
                    photos.append(photo)
                    showingCamera = false
                    frozenFrame = nil
                }
            }
        }
        classifyImage(image)
    }

    // MARK: - Cover

    @ViewBuilder
    private var cover: some View {
        if photos.isEmpty {
            emptyCover
                .padding(.horizontal, DS.gutter)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(photos) { photo in
                        photoCard(photo)
                            .containerRelativeFrame(.horizontal) { width, _ in width - DS.gutter * 2 }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)

            HStack {
                Text(photos.count == 1 ? "1 photo" : "\(photos.count) photos, swipe to see them all")
                    .font(.footnote)
                    .foregroundStyle(Color.dsText2)
                Spacer()
                if photos.count < 10 {
                    Button { openCamera() } label: {
                        Label("Add photo", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.accent)
                    }
                    .buttonStyle(.dim)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
        }
    }

    private var emptyCover: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: "camera")
                .font(.title2)
                .foregroundStyle(Color.dsText2)
            Text("Add a photo")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.dsText)
            Text("Currents names the fish for you, on your phone.")
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            HStack(spacing: DS.Space.s2) {
                Button { openCamera() } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                PhotosPicker(selection: $libraryItems, maxSelectionCount: 10, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
            .padding(.top, DS.Space.s2)
        }
        .padding(DS.Space.s6)
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 0.86, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color.dsText3, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private func photoCard(_ photo: LogCatchPhoto) -> some View {
        let index = photos.firstIndex { $0.id == photo.id } ?? 0
        return Color.dsFill
            .aspectRatio(1 / 0.86, contentMode: .fit)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(alignment: .top) {
                if index == 0 && isClassifying && !reduceMotion {
                    LogCatchScanLine()
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { removePhoto(photo) } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.dsText)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.dim)
                .padding(10)
                .accessibilityLabel("Remove photo \(index + 1)")
            }
            .matchedGeometryEffect(id: index == 0 ? "cover" : photo.id.uuidString, in: coverSpace)
            .accessibilityLabel("Photo \(index + 1)")
    }

    private func removePhoto(_ photo: LogCatchPhoto) {
        withAnimation(DS.Motion.softSpring) {
            photos.removeAll { $0.id == photo.id }
            if photos.isEmpty {
                speciesMatches = []
                hasScanned = false
                lowConfidence = false
                if autoSelectedFromML {
                    selectedSpeciesId = nil
                    selectedSpeciesName = ""
                    autoSelectedFromML = false
                }
            }
        }
        ToastCenter.shared.show("Photo removed", style: .info, icon: "trash")
    }

    // MARK: - Title block

    private enum OverLine {
        case plain(String)
        case progress(String)
        case icon(String, String)
        case confidence(String, Color)
    }

    private var isDownloadingModel: Bool {
        hasScanned && !modelReady && speciesMatches.isEmpty && !photos.isEmpty
    }

    private var noConfidentMatch: Bool {
        hasScanned && !photos.isEmpty && modelReady && (lowConfidence || speciesMatches.isEmpty)
    }

    private var overLine: OverLine {
        if isClassifying { return .progress("Identifying on your phone") }
        if let id = selectedSpeciesId {
            if let match = speciesMatches.first(where: { $0.species.id == id }) {
                let pct = Int(match.confidence * 100)
                return .confidence("\(confidenceLabel(match.confidence)), \(pct)%", DS.scoreInk(pct))
            }
            if let editing, editing.catchRecord.speciesId == id { return .plain(loggedLine(editing.catchRecord.caughtAt)) }
            return .plain("Picked by you")
        }
        if isDownloadingModel { return .icon("icloud.and.arrow.down", "Species ID is still downloading") }
        if noConfidentMatch { return .icon("questionmark.circle", "No confident match") }
        return .plain("Species")
    }

    private func loggedLine(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Logged today" }
        if Calendar.current.isDateInYesterday(date) { return "Logged yesterday" }
        return "Logged on \(date.formatted(.dateTime.day().month(.wide)))"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            overLineView
                .font(.subheadline)
                .frame(minHeight: 20)

            Button { activeSheet = .species } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(selectedSpecies?.commonName ?? (selectedSpeciesName.isEmpty ? "Choose species" : selectedSpeciesName))
                        .font(.largeTitle.bold())
                        .foregroundStyle(selectedSpeciesId == nil ? Color.dsText2 : Color.dsText)
                        .multilineTextAlignment(.leading)
                        .id(selectedSpeciesId)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.dsText3)
                }
            }
            .buttonStyle(.dim)
            .accessibilityHint("Opens the species list")

            if let species = selectedSpecies {
                Text(species.scientificName)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(Color.dsText2)
            } else if noConfidentMatch {
                Text("Pick the closest match from the list.")
                    .font(.callout)
                    .foregroundStyle(Color.dsText2)
            }

            if isDownloadingModel {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(Color.dsText2)
                    Text("The ID model is about 90 MB and needs internet once. Pick the species yourself for now.")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Try again") { retryDownload() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .buttonStyle(.dim)
                }
                .padding(14)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.top, DS.Space.s3)
            }

            if showsNewTag || bestLength != nil {
                HStack(spacing: DS.Space.s2) {
                    if showsNewTag {
                        tag("New to your Fishdex", systemImage: "book", color: .dsScoreGood)
                    }
                    if let best = bestLength {
                        tag("Longer than your best, \(Units.length(cm: best, imperial: imperial))",
                            systemImage: "trophy", color: .dsScoreFair)
                    }
                }
                .padding(.top, DS.Space.s2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: selectedSpeciesId)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isClassifying)
    }

    @ViewBuilder
    private var overLineView: some View {
        switch overLine {
        case .plain(let text):
            Text(text).foregroundStyle(Color.dsText2)
        case .progress(let text):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(Color.dsText2)
            }
        case .icon(let symbol, let text):
            Label(text, systemImage: symbol).foregroundStyle(Color.dsText2)
        case .confidence(let text, let color):
            Text(text).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func tag(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
    }

    private var showsNewTag: Bool {
        !isEditing && selectedSpeciesId != nil && !caughtIds.contains(selectedSpeciesId ?? -1) && priors.isEmpty
    }

    /// The previous best length when this fish beats it.
    private var bestLength: Double? {
        guard selectedSpeciesId != nil, let len = lengthInCm, len > 0,
              let best = priors.compactMap(\.lengthCm).max(), best > 0, len > best else { return nil }
        return best
    }

    // MARK: - Actions

    private var actionRow: some View {
        ActionTriple {
            Button {
                if ARMeasureView.isSupported { showingARMeasure = true } else { focusedField = .length }
            } label: {
                Label(measured ? "Measured" : "Measure", systemImage: "ruler")
            }
            .buttonStyle(ActionTileStyle(measured ? .primary : .tonal))

            Button {
                withAnimation(DS.Motion.easeOut) { released.toggle() }
            } label: {
                Label(released ? "Released" : "Kept", systemImage: released ? "water.waves" : "frying.pan")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ActionTileStyle(.tonal))
            .accessibilityHint("Switches between released and kept")

            Button {
                isFavorite.toggle()
            } label: {
                Label("Favourite", systemImage: isFavorite ? "star.fill" : "star")
                    .symbolEffect(.bounce, value: isFavorite)
            }
            .buttonStyle(ActionTileStyle(.tonal))
            .accessibilityAddTraits(isFavorite ? .isSelected : [])
        }
    }

    // MARK: - Size

    private var lengthInCm: Double? {
        lengthCm.measurementValue.map { imperial ? $0 * 2.54 : $0 }
    }

    /// Length-based weight estimate in the display unit, offered when there is
    /// a length but no weight yet (uses the selected species' body shape).
    private var estimateDisplay: Double? {
        guard let len = lengthInCm, len > 0, weightKg.measurementValue == nil,
              let kg = WeightEstimator.estimateKg(lengthCm: len, species: selectedSpecies) else { return nil }
        return imperial ? kg * 2.2046226 : kg
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Size")
            HStack(spacing: 10) {
                sizeTile(label: "Length", text: $lengthCm, placeholder: "0", unit: imperial ? "in" : "cm",
                         field: .length, minusLabel: "Shorter", plusLabel: "Longer") { stepLength($0) }
                sizeTile(label: weightKg.isEmpty && estimateDisplay != nil ? "Weight, estimated" : "Weight",
                         text: $weightKg,
                         placeholder: estimateDisplay.map { String(format: "%.1f", $0) } ?? "0.0",
                         unit: imperial ? "lb" : "kg",
                         field: .weight, minusLabel: "Lighter", plusLabel: "Heavier") { stepWeight($0) }
            }
            .padding(.horizontal, DS.gutter)

            VStack(alignment: .leading, spacing: 10) {
                if let est = estimateDisplay {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "scalemass")
                            .font(.footnote)
                            .foregroundStyle(Color.dsText2)
                        Text("Worked out from the length.")
                            .font(.footnote)
                            .foregroundStyle(Color.dsText2)
                        Spacer(minLength: DS.Space.s2)
                        Button("Use \(String(format: "%.1f", est)) \(imperial ? "lb" : "kg")") {
                            withAnimation(DS.Motion.easeOut) { weightKg = String(format: "%.2f", est) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .buttonStyle(.dim)
                    }
                }
                if let note = regulationNote {
                    LogCatchFootnote(text: note.text, systemImage: note.icon, tint: note.warn ? .dsScoreSlow : .dsText2)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, 10)
        }
    }

    private func sizeTile(label: String, text: Binding<String>, placeholder: String, unit: String,
                          field: Field, minusLabel: String, plusLabel: String,
                          step: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                    .font(.system(size: numeralSize, weight: .bold, design: .rounded)) // ui-lint: allow, big numeral scaled with @ScaledMetric
                    .monospacedDigit()
                    .fixedSize()
                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsText2)
            }
            HStack(spacing: DS.Space.s2) {
                stepButton(systemImage: "minus", label: minusLabel) { step(-1) }
                stepButton(systemImage: "plus", label: plusLabel) { step(1) }
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.dsFill2, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        }
        .buttonStyle(.dim)
        .accessibilityLabel(label)
    }

    private func stepLength(_ direction: Double) {
        let step = imperial ? 0.5 : 1.0
        let start = lengthCm.measurementValue ?? (imperial ? 12 : 30) - direction * step
        lengthCm = formatNumber(max(step, start + direction * step))
        Haptics.selection()
    }

    private func stepWeight(_ direction: Double) {
        let start = weightKg.measurementValue ?? estimateDisplay ?? 1.0
        let next = max(0.1, ((start + direction * 0.1) * 10).rounded() / 10)
        weightKg = String(format: "%.1f", next)
        Haptics.selection()
    }

    private func formatNumber(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private var regulationNote: (text: String, icon: String, warn: Bool)? {
        guard let species = selectedSpecies else { return nil }
        let result = RegulationsService.shared.verdict(species: species, lengthCm: lengthInCm)
        guard let reg = result.reg else { return nil }
        let bag = reg.bagLimit.map { " Bag limit \($0) a day." } ?? ""
        switch result.verdict {
        case .legal:
            return ("Legal size to keep in \(reg.region).\(bag) Check local rules.", "checkmark.seal", false)
        case .tooSmall(let mn):
            let min = Units.length(cm: mn, imperial: imperial)
            return released
                ? ("Under the \(min) minimum in \(reg.region), so releasing it is right.", "checkmark.seal", false)
                : ("Undersized. The minimum in \(reg.region) is \(min).", "exclamationmark.triangle", true)
        case .tooBig(let mx):
            let max = Units.length(cm: mx, imperial: imperial)
            return released
                ? ("Over the \(max) slot in \(reg.region), so releasing it is right.", "checkmark.seal", false)
                : ("Over the slot. The maximum in \(reg.region) is \(max).", "exclamationmark.triangle", true)
        case .unknownSize:
            return ("Add a length to check the \(reg.region) limit.\(bag)", "ruler", false)
        case .noRegulation:
            return nil
        }
    }

    // MARK: - Spot

    private var spotTitle: String {
        switch locationMode {
        case .current: return "Current location"
        case .spot: return allSpots.first { $0.id == selectedSpotId }?.name ?? "Choose a saved spot"
        case .pin: return "Dropped pin"
        }
    }

    private var spotSubtitle: String {
        switch locationMode {
        case .current:
            if let loc = appState.locationManager.currentLocation {
                return "Your location, accurate to \(max(1, Int(loc.horizontalAccuracy))) m"
            }
            return "Waiting for your location"
        case .spot:
            return "Saved spot"
        case .pin:
            if let c = pinCoordinate { return String(format: "%.4f, %.4f", c.latitude, c.longitude) }
            return "Choose a place on the map"
        }
    }

    private var spotCoordinate: CLLocationCoordinate2D? {
        let (lat, lon) = resolveLocation()
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var spotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Spot")
            Button { activeSheet = .spot } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spotTitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.dsText)
                        Text(spotSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.dsText2)
                    }
                    Spacer()
                    Text("Change")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.dim)

            Button { activeSheet = .spot } label: {
                LogCatchMapPreview(coordinate: spotCoordinate, isPin: locationMode == .pin)
            }
            .buttonStyle(.dim)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Change the spot")
        }
    }

    // MARK: - Details

    private var caughtValue: String {
        let time = caughtAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(caughtAt) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(caughtAt) { return "Yesterday, \(time)" }
        return "\(caughtAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))), \(time)"
    }

    private var gearValue: String {
        if let id = selectedGearId, let preset = allGear.first(where: { $0.id == id }) { return preset.name }
        for value in [gearLure, gearRod, gearReel, gearTechnique] where !value.isEmpty { return value }
        return "None"
    }

    private var waterValue: String {
        let clarity = waterClarity?.label
        let depth = depthText.measurementValue.map { "\(formatNumber($0)) \(imperial ? "ft" : "m")" }
        switch (clarity, depth) {
        case let (c?, d?): return "\(c), \(d)"
        case let (c?, nil): return c
        case let (nil, d?): return d
        default: return "Not set"
        }
    }

    private var sessionValue: String {
        if !isEditing, appState.tripTracker.activeTrip != nil { return "Current session" }
        if let id = selectedTripId, let trip = allTrips.first(where: { $0.id == id }) { return trip.name }
        return "None"
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Details")
            VStack(spacing: 0) {
                detailRow("Caught", systemImage: "clock", tint: .dsScoreLow, value: caughtValue, sheet: .time)
                Divider().padding(.leading, 52)
                detailRow("Gear", systemImage: "shippingbox", tint: .purple, value: gearValue, sheet: .gear)
                Divider().padding(.leading, 52)
                detailRow("Water", systemImage: "drop", tint: DS.accent, value: waterValue, sheet: .water)
                if FeatureFlags.liveTrips {
                    Divider().padding(.leading, 52)
                    detailRow("Session", systemImage: "figure.fishing", tint: .dsScoreGood, value: sessionValue, sheet: .session)
                }
            }
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
        }
    }

    private func detailRow(_ title: String, systemImage: String, tint: Color, value: String,
                           sheet: ComposerSheet) -> some View {
        Button {
            focusedField = nil
            activeSheet = sheet
        } label: {
            LogCatchListRow(title: title, systemImage: systemImage, tint: tint, value: value, chevron: true)
        }
        .buttonStyle(.dim)
    }

    // MARK: - Conditions

    private var conditionsKey: String {
        guard !isEditing, let c = spotCoordinate else { return "none" }
        let hour = Int(caughtAt.timeIntervalSince1970 / 3600)
        return String(format: "%.2f,%.2f,", c.latitude, c.longitude) + "\(hour),\(selectedSpeciesId ?? 0)"
    }

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Conditions")
            let c = conditions
            HStack(spacing: DS.Space.s2) {
                conditionTile(systemImage: "thermometer.medium", tint: .dsScoreLow,
                              value: c?.waterC.map { Units.temperature($0, imperial: imperial) } ?? "–",
                              label: "Water")
                conditionTile(systemImage: "wind", tint: .cyan,
                              value: c?.windKmh.map { formatNumber((imperial ? $0 * 0.62137119 : $0).rounded()) } ?? "–",
                              label: c?.windDeg.map { "\(Units.speedSymbol) \(compass($0))" } ?? Units.speedSymbol)
                conditionTile(systemImage: "gauge.medium", tint: .purple,
                              value: c?.pressureHpa.map { "\(Int($0.rounded()))" } ?? "–",
                              label: "hPa")
                conditionTile(systemImage: "fish", tint: .dsScoreGood,
                              value: c?.score.map { "\($0)" } ?? "–",
                              label: "Bite")
            }
            .padding(.horizontal, DS.gutter)

            LogCatchFootnote(text: conditionsFootnote, systemImage: c == nil ? "info.circle" : "checkmark.circle")
                .padding(.horizontal, DS.gutter)
                .padding(.top, 10)
        }
    }

    private var conditionsFootnote: String {
        if isEditing {
            return conditions == nil ? "No weather was saved with this catch." : "Recorded when the catch was logged."
        }
        if conditions == nil { return "Filled in from the forecast once your location is known." }
        return "Filled in from the forecast for \(caughtAt.formatted(date: .omitted, time: .shortened)). Saved with the catch."
    }

    private func conditionTile(systemImage: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(tint)
                .padding(.bottom, 4)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s3)
        .padding(.horizontal, DS.Space.s1)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func compass(_ deg: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i]
    }

    private func refreshConditions() async {
        guard !isEditing else { return }
        guard let coord = spotCoordinate else {
            conditions = nil
            return
        }
        let wx = await WeatherService.shared.current(for: coord)
        guard let wx else {
            conditions = nil
            return
        }
        let forecast = ForecastEngine.forecast(
            date: caughtAt,
            coordinate: coord,
            currentPressureHpa: wx.pressureHpa,
            pressureChange6h: wx.pressureChange6h,
            waterTempC: wx.waterTempC,
            windSpeedKmh: wx.windSpeedKmh,
            windDirection: wx.windDirectionDeg,
            species: selectedSpecies,
            isInSpawningZone: false
        )
        withAnimation(DS.Motion.easeOut) {
            conditions = Conditions(waterC: wx.waterTempC, windKmh: wx.windSpeedKmh,
                                    windDeg: wx.windDirectionDeg, pressureHpa: wx.pressureHpa,
                                    score: forecast.score)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Notes")
            TextField("What worked, what the water looked like", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
                .padding(14)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
        }
    }

    // MARK: - Sharing

    private var iNatAvailable: Bool {
        appState.inaturalist.isConnected && appState.inaturalist.isConfigured
    }

    @ViewBuilder
    private var sharingSection: some View {
        if !isEditing && (!crews.isEmpty || iNatAvailable) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Sharing")
                VStack(spacing: 0) {
                    ForEach(Array(crews.enumerated()), id: \.element.code) { index, crew in
                        if index > 0 { Divider().padding(.leading, 52) }
                        shareRow("Post to \(crew.name)", systemImage: "person.3", tint: .dsScoreGood,
                                 isOn: Binding(get: { crewShare[crew.code] ?? false },
                                               set: { crewShare[crew.code] = $0 }))
                    }
                    if iNatAvailable {
                        if !crews.isEmpty { Divider().padding(.leading, 52) }
                        shareRow("Add to iNaturalist", systemImage: "leaf", tint: .green, isOn: $shareToINat)
                    }
                }
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)

                LogCatchFootnote(text: "Crew posts and the leaderboard show the area, never the exact spot. Photos lose their location before they leave your phone.",
                                 systemImage: "lock.shield")
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 10)
            }
            .padding(.top, 28)
        }
    }

    private func shareRow(_ title: String, systemImage: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
                Text(title)
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
            }
        }
        .tint(Color.dsScoreGood)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 6) {
            Button {
                Task { await save() }
            } label: {
                Label(isEditing ? "Save changes" : "Save catch", systemImage: "checkmark")
            }
            .buttonStyle(.dsPrimary)
            .disabled(selectedSpeciesId == nil || isSaving)
            if selectedSpeciesId == nil {
                Text(isClassifying ? "Waiting for the species" : "Choose the species to save")
                    .font(.footnote)
                    .foregroundStyle(Color.dsText2)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ComposerSheet) -> some View {
        switch sheet {
        case .species:
            SpeciesPickerSheet(
                species: allSpecies,
                selectedId: $selectedSpeciesId,
                selectedName: $selectedSpeciesName,
                matches: photos.isEmpty ? [] : speciesMatches,
                matchesAreUncertain: lowConfidence,
                caughtIds: caughtIds,
                modelDownloading: isDownloadingModel,
                onRescan: photos.isEmpty ? nil : { rescan() },
                onRetryDownload: { retryDownload() }
            )
        case .time:
            LogCatchTimeSheet(caughtAt: $caughtAt, photoDate: photoDate)
        case .gear:
            LogCatchGearSheet(presets: allGear, ownedGear: ownedGear, selectedGearId: $selectedGearId,
                              rod: $gearRod, reel: $gearReel, lure: $gearLure,
                              lureColor: $gearLureColor, technique: $gearTechnique)
        case .water:
            LogCatchWaterSheet(clarity: $waterClarity, depthText: $depthText, imperial: imperial)
        case .session:
            LogCatchSessionSheet(trips: allTrips,
                                 activeTrip: isEditing ? nil : appState.tripTracker.activeTrip,
                                 selectedTripId: $selectedTripId,
                                 canStart: !isEditing) {
                let trip = appState.tripTracker.start(name: SessionFormat.defaultName(), spotId: selectedSpotId)
                selectedTripId = trip.id
                if !allTrips.contains(where: { $0.id == trip.id }) { allTrips.insert(trip, at: 0) }
                ToastCenter.shared.show("Session started", icon: "play.fill")
            }
        case .spot:
            LogCatchSpotSheet(mode: $locationMode, spots: allSpots, selectedSpotId: $selectedSpotId,
                              pinCoordinate: $pinCoordinate,
                              currentLocation: appState.locationManager.currentLocation,
                              newSpotName: $newSpotName,
                              onSaveSpot: saveNewSpot)
        }
    }

    // MARK: - Dirty state

    private var signature: String {
        let species: String = selectedSpeciesId.map { String($0) } ?? ""
        let minute: String = String(Int(caughtAt.timeIntervalSince1970 / 60))
        let clarity: String = waterClarity?.rawValue ?? ""
        let photoIds: String = photos.map { $0.id.uuidString }.joined(separator: ",")
        let pin: String = pinCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? ""
        var parts: [String] = [species, lengthCm, weightKg, String(released), String(isFavorite), notes]
        parts += [minute, clarity, depthText, photoIds]
        parts += [locationMode.rawValue, selectedSpotId ?? "", pin, selectedTripId ?? "", selectedGearId ?? ""]
        parts += [gearRod, gearReel, gearLure, gearLureColor, gearTechnique]
        return parts.joined(separator: "|")
    }

    private var isDirty: Bool {
        guard let baseline else { return false }
        return signature != baseline
    }

    private func close() {
        focusedField = nil
        if isDirty { showingDiscard = true } else { dismiss() }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        RegulationsService.shared.load()
        allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
        allSpots = (try? appState.spotRepository.fetchAll()) ?? []
        allGear = (try? appState.gearRepository.fetchPresets()) ?? []
        allTrips = (try? appState.tripRepository.fetchAll()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        caughtIds = Set(((try? appState.catchRepository.speciesCounts()) ?? []).map { $0.speciesId })

        if let editing {
            loadEditing(editing)
        } else {
            // Auto-select active trip so catches link automatically
            if selectedTripId == nil {
                selectedTripId = allTrips.first(where: { $0.endDate == nil })?.id
            }
            if let loc = appState.locationManager.currentLocation {
                pinCoordinate = loc.coordinate
            }
            if let presetSpecies {
                selectSpecies(presetSpecies)
            }
            if CommunityService.shared.joined {
                crews = CommunityService.shared.myCrews
                crewShare = Dictionary(uniqueKeysWithValues: crews.map { ($0.code, $0.autoPost) })
            }
        }
        loadPriors()
        baseline = signature
    }

    private func loadEditing(_ detail: CatchDetail) {
        let c = detail.catchRecord
        var loaded: [LogCatchPhoto] = []
        var missing: [String] = []
        for path in c.allPhotoPaths {
            if let image = PhotoManager.load(path) {
                loaded.append(LogCatchPhoto(image: image, savedPath: path))
            } else {
                missing.append(path)
            }
        }
        photos = loaded
        unloadablePaths = missing
        weightKg = c.weightKg.map { String(format: "%.2f", imperial ? $0 * 2.2046226 : $0) } ?? ""
        lengthCm = c.lengthCm.map { String(format: "%.1f", imperial ? $0 / 2.54 : $0) } ?? ""
        notes = c.notes ?? ""
        released = c.released
        isFavorite = c.isFavorite
        caughtAt = c.caughtAt
        waterClarity = c.clarity
        depthText = c.depthM.map { formatNumber(((imperial ? $0 * 3.2808399 : $0) * 10).rounded() / 10) } ?? ""
        selectedSpeciesId = c.speciesId
        selectedSpeciesName = detail.species?.commonName ?? ""
        selectedSpotId = c.spotId
        selectedTripId = c.tripId
        selectedGearId = c.gearLoadoutId
        pinCoordinate = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        locationMode = c.spotId != nil ? .spot : .pin
        if let loadout = detail.gearLoadout {
            gearRod = loadout.rod ?? ""
            gearReel = loadout.reel ?? ""
            gearLure = loadout.lure ?? ""
            gearLureColor = loadout.lureColor ?? ""
            gearTechnique = loadout.technique ?? ""
        }
        if let json = c.weatherSnapshot, let data = json.data(using: .utf8),
           let snap = try? JSONDecoder().decode(WxSnap.self, from: data) {
            conditions = Conditions(waterC: snap.waterTempC, windKmh: snap.windSpeedKmh,
                                    windDeg: snap.windDirectionDeg, pressureHpa: snap.pressureHpa,
                                    score: c.forecastScoreAtCapture)
        } else if let score = c.forecastScoreAtCapture {
            conditions = Conditions(score: score)
        }
    }

    private func loadPriors() {
        guard let id = selectedSpeciesId else {
            priors = []
            return
        }
        let excluding = editing?.catchRecord.id
        priors = ((try? appState.catchRepository.fetchForSpecies(id)) ?? [])
            .map(\.catchRecord)
            .filter { $0.id != excluding }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var newImages: [UIImage] = []
            var extractedDate: Date?
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    newImages.append(uiImage)
                    // Extract EXIF date from first photo
                    if extractedDate == nil {
                        extractedDate = Self.extractDateFromEXIF(data: data)
                    }
                }
            }
            libraryItems = []
            let room = max(0, 10 - photos.count)
            if newImages.count > room {
                ToastCenter.shared.show("Up to 10 photos per catch", style: .info, icon: "photo.on.rectangle")
            }
            let added = Array(newImages.prefix(room))
            guard !added.isEmpty else { return }
            let wasEmpty = photos.isEmpty
            withAnimation(DS.Motion.softSpring) {
                photos.append(contentsOf: added.map { LogCatchPhoto(image: $0) })
                showingCamera = false
            }
            if let date = extractedDate {
                photoDate = date
                if !isEditing { caughtAt = min(date, .now) }
            }
            if !wasEmpty || isEditing {
                ToastCenter.shared.show(added.count == 1 ? "Photo added" : "\(added.count) photos added", icon: "photo")
            }
            if wasEmpty, let first = added.first {
                classifyImage(first)
            }
        }
    }

    private static func extractDateFromEXIF(data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    // MARK: - Species ID

    private func confidenceLabel(_ c: Float) -> String {
        switch c {
        case 0.85...: "Very confident"
        case 0.6..<0.85: "Likely"
        case 0.4..<0.6: "Best guess"
        default: "Uncertain"
        }
    }

    private func selectSpecies(_ species: Species) {
        selectedSpeciesId = species.id
        selectedSpeciesName = species.commonName
    }

    private func rescan() {
        guard let first = photos.first else { return }
        if autoSelectedFromML {
            selectedSpeciesId = nil
            selectedSpeciesName = ""
        }
        classifyImage(first.image)
    }

    private func retryDownload() {
        ToastCenter.shared.show("Downloading the species model, about 90 MB", style: .info, icon: "icloud.and.arrow.down")
        if let first = photos.first { classifyImage(first.image) }
    }

    private func classifyImage(_ image: UIImage) {
        isClassifying = true
        autoSelectedFromML = false
        lowConfidence = false
        Task {
            // BioCLIP is the only identifier — the old artwork-similarity and
            // Vision fallbacks produced junk guesses and were removed. Nudge
            // the model download in case the launch attempt had no network.
            await appState.fishModelDownloader.ensureModelDownloaded()

            let byId = Dictionary(uniqueKeysWithValues: allSpecies.map { ($0.id, $0) })

            // Region/season prior: nudge scores toward species whose thermal
            // band brackets the local water temperature. Best-effort — no
            // location or offline just means no nudge.
            let (lat, lon) = resolveLocation()
            var waterTemp: Double?
            if lat != 0 || lon != 0 {
                waterTemp = await WeatherService.shared.current(
                    for: CLLocationCoordinate2D(latitude: lat, longitude: lon))?.waterTempC
            }
            let prior = thermalPrior(waterTempC: waterTemp)

            let ranked = await appState.embeddingIdentifier.identify(image: image, prior: prior)
            let matches = ranked.compactMap { r in
                byId[r.speciesId].map { SpeciesMatch(species: $0, confidence: r.confidence) }
            }

            // "Not sure" guardrail: skip auto-selecting when the top match is
            // weak, or barely ahead of the runner-up — a confident wrong guess
            // is worse than asking.
            var unsure = false
            if let top = matches.first {
                let second = matches.dropFirst().first?.confidence ?? 0
                unsure = top.confidence < 0.30 || (top.confidence - second) < 0.08
            }

            let ready = await appState.fishModelDownloader.isModelAvailable
            withAnimation(reduceMotion ? nil : DS.Motion.easeOut) {
                speciesMatches = matches
                lowConfidence = unsure
                modelReady = ready
                hasScanned = true
                isClassifying = false
                if let top = matches.first, selectedSpeciesId == nil, !unsure {
                    selectSpecies(top.species)
                    autoSelectedFromML = true
                }
            }
        }
    }

    /// A gentle per-species multiplier (~0.55…1) from how well the local water
    /// temperature sits inside each species' known thermal band. Empty when the
    /// temperature is unknown, so the identifier falls back to vision only.
    private func thermalPrior(waterTempC t: Double?) -> [Int64: Float] {
        guard let t else { return [:] }
        var out: [Int64: Float] = [:]
        for sp in allSpecies {
            guard let lo = sp.minTempC, let hi = sp.maxTempC, hi >= lo else { continue }
            if t >= lo && t <= hi {
                out[sp.id] = 1.0
            } else {
                let dist = t < lo ? (lo - t) : (t - hi)
                // ~1 °C outside barely matters; ~9 °C+ outside hits the floor.
                out[sp.id] = Float(max(0.55, 1.0 - dist / 20.0))
            }
        }
        return out
    }

    // MARK: - Save

    private func saveNewSpot() {
        let name = newSpotName.trimmingCharacters(in: .whitespaces)
        guard let coord = pinCoordinate, !name.isEmpty else { return }
        var spot = Spot(
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            isPrivate: true
        )
        try? appState.spotRepository.save(&spot)
        allSpots.insert(spot, at: 0)
        selectedSpotId = spot.id
        locationMode = .spot
        newSpotName = ""
        ToastCenter.shared.show("\(name) saved to your spots", icon: "bookmark.fill")
    }

    /// Codable matching CatchDetailView's WeatherSnapshot keys so the stored
    /// conditions decode back on the catch detail.
    private struct WxSnap: Codable {
        var temperatureC: Double?
        var waterTempC: Double?
        var windSpeedKmh: Double?
        var windDirectionDeg: Double?
        var pressureHpa: Double?
        var condition: String?
    }

    /// The gear the catch is saved with. Starting from any chosen preset, the
    /// user can still fill fields the preset didn't cover (or tweak ones it
    /// did). If the effective gear differs from the preset, snapshot it onto a
    /// HIDDEN loadout so the catch keeps exactly what was used — the named
    /// preset stays untouched, and the Presets tab isn't polluted.
    private func resolveGearId() -> String? {
        let hasIndividualGear = !gearRod.isEmpty || !gearReel.isEmpty || !gearLure.isEmpty || !gearTechnique.isEmpty
        if let selected = selectedGearId,
           let preset = allGear.first(where: { $0.id == selected }) {
            let matchesPreset =
                gearRod == (preset.rod ?? "") &&
                gearReel == (preset.reel ?? "") &&
                gearLure == (preset.lure ?? "") &&
                gearLureColor == (preset.lureColor ?? "") &&
                gearTechnique == (preset.technique ?? "")
            if matchesPreset { return selected }
            var hidden = GearLoadout(
                name: preset.name,
                rod: gearRod.isEmpty ? nil : gearRod,
                reel: gearReel.isEmpty ? nil : gearReel,
                lineLb: preset.lineLb,
                leaderLb: preset.leaderLb,
                lure: gearLure.isEmpty ? nil : gearLure,
                lureColor: gearLureColor.isEmpty ? nil : gearLureColor,
                lureWeightG: preset.lureWeightG,
                technique: gearTechnique.isEmpty ? nil : gearTechnique,
                isAutoCreated: true
            )
            try? appState.gearRepository.save(&hidden)
            return hidden.id
        }
        if hasIndividualGear {
            var hidden = GearLoadout(
                name: "Catch gear",
                rod: gearRod.isEmpty ? nil : gearRod,
                reel: gearReel.isEmpty ? nil : gearReel,
                lure: gearLure.isEmpty ? nil : gearLure,
                lureColor: gearLureColor.isEmpty ? nil : gearLureColor,
                technique: gearTechnique.isEmpty ? nil : gearTechnique,
                isAutoCreated: true
            )
            try? appState.gearRepository.save(&hidden)
            return hidden.id
        }
        return nil
    }

    private func save() async {
        if let editing {
            saveEdits(editing)
        } else {
            await saveCatch()
        }
    }

    /// Same contract as the old EditCatchSheet: the caller persists and
    /// re-publishes the updated record.
    private func saveEdits(_ detail: CatchDetail) {
        guard !isSaving else { return }
        isSaving = true
        var updated = detail.catchRecord

        // Photos: delete removed originals, persist newly-added images, then
        // combine in the order shown. New files get unique names so they
        // never overwrite an existing photo of this catch.
        let kept = Set(photos.compactMap(\.savedPath) + unloadablePaths)
        for path in detail.catchRecord.allPhotoPaths where !kept.contains(path) { PhotoManager.delete(path) }
        var allPhotos: [String] = []
        for photo in photos {
            if let path = photo.savedPath {
                allPhotos.append(path)
            } else if let path = try? PhotoManager.save(photo.image,
                                                         id: "\(updated.id)_\(UUID().uuidString.prefix(8))") {
                allPhotos.append(path)
            }
        }
        allPhotos.append(contentsOf: unloadablePaths)
        updated.photoPath = allPhotos.first
        updated.photoPaths = Catch.encodePhotoPaths(allPhotos)

        updated.weightKg = weightKg.measurementValue.map { imperial ? $0 / 2.2046226 : $0 }
        updated.lengthCm = lengthCm.measurementValue.map { imperial ? $0 * 2.54 : $0 }
        updated.notes = notes.isEmpty ? nil : notes
        updated.released = released
        updated.isFavorite = isFavorite
        updated.caughtAt = caughtAt
        updated.speciesId = selectedSpeciesId
        updated.spotId = locationMode == .spot ? selectedSpotId : nil
        updated.tripId = selectedTripId
        updated.clarity = waterClarity
        updated.depthM = depthText.measurementValue.map { imperial ? $0 * 0.3048 : $0 }
        let (lat, lon) = resolveLocation()
        if lat != 0 || lon != 0 {
            updated.latitude = lat
            updated.longitude = lon
            updated.geohash = Geohash.encode(latitude: lat, longitude: lon, precision: 7)
        }
        updated.gearLoadoutId = resolveGearId()

        onEditSave?(updated)
        ToastCenter.shared.show("Catch updated")
        dismiss()
    }

    private func saveCatch() async {
        // Re-entrancy guard: a rapid double-tap creates two Tasks; the second
        // sees isSaving == true (set synchronously before any await) and bails,
        // so we never save the same catch twice.
        guard !isSaving else { return }
        isSaving = true
        let (lat, lon) = resolveLocation()
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let catchId = UUID().uuidString

        // Save multiple photos
        var photoPaths: [String] = []
        if !photos.isEmpty {
            photoPaths = (try? PhotoManager.saveMultiple(photos.map(\.image), catchId: catchId)) ?? []
        }

        // Capture the actual conditions at the catch (weather + real bite score).
        let wx = await WeatherService.shared.current(for: coord)
        let species = allSpecies.first(where: { $0.id == selectedSpeciesId })
        let forecast = ForecastEngine.forecast(
            date: caughtAt,
            coordinate: coord,
            currentPressureHpa: wx?.pressureHpa,
            pressureChange6h: wx?.pressureChange6h,
            waterTempC: wx?.waterTempC,
            windSpeedKmh: wx?.windSpeedKmh,
            windDirection: wx?.windDirectionDeg,
            species: species,
            isInSpawningZone: false
        )
        let weatherJSON: String? = wx.flatMap {
            let snap = WxSnap(temperatureC: $0.temperatureC, waterTempC: $0.waterTempC,
                              windSpeedKmh: $0.windSpeedKmh, windDirectionDeg: $0.windDirectionDeg,
                              pressureHpa: $0.pressureHpa, condition: $0.condition)
            return (try? JSONEncoder().encode(snap)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Any fish logged while a session is recording belongs to that session.
        let tripId = appState.tripTracker.activeTrip?.id ?? selectedTripId
        let gearId = resolveGearId()

        var catchRecord = Catch(
            id: catchId,
            speciesId: selectedSpeciesId,
            spotId: locationMode == .spot ? selectedSpotId : nil,
            caughtAt: caughtAt,
            latitude: lat,
            longitude: lon,
            lengthCm: lengthCm.measurementValue.map { imperial ? $0 * 2.54 : $0 },
            weightKg: weightKg.measurementValue.map { imperial ? $0 / 2.2046226 : $0 },
            released: released,
            photoPath: photoPaths.first,
            photoPaths: Catch.encodePhotoPaths(photoPaths),
            mlConfidence: speciesMatches.first.map { Double($0.confidence) },
            forecastScoreAtCapture: forecast.score,
            weatherSnapshot: weatherJSON,
            gearLoadoutId: gearId,
            tripId: tripId,
            notes: notes.isEmpty ? nil : notes,
            isFavorite: isFavorite,
            waterClarity: waterClarity,
            // Stored in metres regardless of the angler's display units.
            depthM: depthText.measurementValue.map { imperial ? $0 * 0.3048 : $0 }
        )

        // Judge first-species / personal-best BEFORE the save, against what's
        // in the log right now — so a deleted-and-relogged species celebrates
        // again (it genuinely is the only one in the log).
        let priorCatches = (try? appState.catchRepository.fetchForSpecies(selectedSpeciesId ?? -1))?
            .map(\.catchRecord) ?? []
        let celebration = CelebrationJudge.judge(
            speciesName: species?.commonName, speciesId: selectedSpeciesId,
            weightKg: catchRecord.weightKg, lengthCm: catchRecord.lengthCm,
            excludingCatchId: catchId, existing: priorCatches)

        try? appState.catchRepository.save(&catchRecord)

        // Reset the cold-streak nudge — you just caught something.
        if tripId != nil, appState.tripTracker.isTracking {
            await NotificationManager.shared.scheduleColdStreakNudge()
        }

        // Share to iNaturalist when the user has connected their account and
        // left the toggle on. No-op otherwise, so nothing leaves the device by default.
        if shareToINat {
            appState.inaturalist.uploadIfConnected(
                catchRecord,
                species: species,
                catchRepository: appState.catchRepository
            )
        }

        // Publish a measured catch to the community leaderboard / group feed in
        // the BACKGROUND — never block the save + dismiss on a CloudKit round
        // trip. No-op unless joined. Group-tagged catches publish even
        // unmeasured, so a quick "fish on" still lands in the trip feed.
        let resolvedGroup = tripId.flatMap { CommunityService.shared.groupCode(forTripId: $0) }
            ?? groupCodeOverride
        if catchRecord.weightKg != nil || catchRecord.lengthCm != nil || resolvedGroup != nil {
            let name = species?.commonName ?? "Fish"
            let region = CommunityService.shared.myRegion
            let groupCode = resolvedGroup
            let rec = catchRecord
            Task { await CommunityService.shared.publish(
                catchRecord: rec, speciesName: name, region: region, groupCode: groupCode) }
        }

        // Post to the crews left on in Sharing (each crew's auto-post setting is
        // the default). Always in the background; no-op unless joined.
        let crewName = species?.commonName ?? "Fish"
        let crewCatch = catchRecord
        let shareCrews = crews.filter { crewShare[$0.code] ?? false }
        if !shareCrews.isEmpty {
            let codes = shareCrews.map(\.code)
            Task {
                for code in codes {
                    // Tag the post with the crew's live trip, if one is running.
                    let trip = CommunityService.shared.activeTrip(forCrew: code)?.name ?? ""
                    await CommunityService.shared.postCatch(crewCatch, speciesName: crewName,
                                                            toCrew: code, caption: "", tripName: trip)
                }
            }
        }

        if let celebration {
            // The celebration plays over the screen underneath once the
            // composer closes.
            CelebrationCenter.shared.show(celebration)
        } else if shareCrews.count == 1, let crew = shareCrews.first {
            ToastCenter.shared.show("Saved and posted to \(crew.name)")
        } else {
            let size = catchRecord.lengthCm.map { ", \(Units.length(cm: $0, imperial: imperial))" } ?? ""
            ToastCenter.shared.show("\(crewName) saved\(size)")
        }
        // Rate or support prompt: after the first catch ever, once any
        // celebration is dismissed, then not again for 30 days.
        let logged = UserDefaults.standard.integer(forKey: "totalCatchesLogged") + 1
        UserDefaults.standard.set(logged, forKey: "totalCatchesLogged")
        ReviewPrompt.maybeAsk(afterCatchCount: logged)
        dismiss()
    }

    private func resolveLocation() -> (Double, Double) {
        switch locationMode {
        case .current:
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        case .spot:
            if let spot = allSpots.first(where: { $0.id == selectedSpotId }) {
                return (spot.latitude, spot.longitude)
            }
            if let editing {
                return (editing.catchRecord.latitude, editing.catchRecord.longitude)
            }
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        case .pin:
            if let coord = pinCoordinate {
                return (coord.latitude, coord.longitude)
            }
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        }
    }

    private var pageTint: Color? {
        selectedSpecies?.artTint
    }
}

/// The scan line that sweeps the cover photo while species ID runs.
private struct LogCatchScanLine: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(DS.accent)
                .frame(height: 3)
                .offset(y: down ? geo.size.height - 3 : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { down = true }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Location Picker Sheet (Pin Drop with Search)

struct LocationPickerSheet: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    /// What the pin is FOR — "Forecast Location" in the trip planner, "Spot"
    /// on the map — so the label under the pin never lies about its purpose.
    let pinLabel: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var pinPosition: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var searchModel = MapSearchCompleter()
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    init(coordinate: Binding<CLLocationCoordinate2D?>, pinLabel: String = "Catch Location") {
        _coordinate = coordinate
        self.pinLabel = pinLabel
        // Open centred on the existing pin when there is one (e.g. editing a
        // spot or catch far from where the user is standing right now),
        // otherwise on the user's current location.
        //
        // We deliberately pin an EXPLICIT coordinate rather than using
        // `.userLocation(fallback:)`: that mode keeps re-centring as the async
        // location fix resolves, and a late fix would clobber a location the
        // user had already panned to — dropping the pin far from where they
        // placed it. Seeding `pinPosition` up front also means Confirm can
        // never save a nil/stale coordinate.
        let start = coordinate.wrappedValue
            ?? LocationPickerSheet.lastKnownCoordinate
        if let start {
            _cameraPosition = State(initialValue: .camera(.init(
                centerCoordinate: start,
                distance: 3000
            )))
            _pinPosition = State(initialValue: start)
        } else {
            _cameraPosition = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    /// Best-effort last known device location, captured synchronously at init
    /// so the picker can seed its pin without waiting on an async fix.
    private static var lastKnownCoordinate: CLLocationCoordinate2D? {
        CLLocationManager().location?.coordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let pin = pinPosition {
                        Annotation(pinLabel, coordinate: pin) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                // Center crosshair
                VStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(CurrentsTheme.accent)
                    Spacer()
                }

                // Search bar + type-ahead results overlay (same behaviour as
                // the main map: results show while the keyboard is up, and
                // there's an explicit keyboard-dismiss button).
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search location...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit {
                                if let first = searchModel.completions.first {
                                    select(first)
                                }
                                searchFocused = false
                            }
                            .onChange(of: searchText) { _, newValue in
                                searchModel.update(
                                    query: newValue,
                                    near: pinPosition ?? appState.locationManager.currentLocation?.coordinate
                                )
                            }
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchModel.clear()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if searchFocused {
                            Button {
                                searchFocused = false
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .foregroundStyle(CurrentsTheme.accent)
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial) // ui-lint: allow, floating panel over the map
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if !searchModel.completions.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(searchModel.completions.prefix(6).enumerated()), id: \.offset) { index, completion in
                                Button {
                                    select(completion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(completion.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                }
                                if index < min(searchModel.completions.count, 6) - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(.ultraThinMaterial) // ui-lint: allow, floating panel over the map
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb))
                        .padding(.horizontal)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Drop Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        coordinate = pinPosition
                        dismiss()
                    }
                    .bold()
                }
            }
            // Track the centre continuously so the pin always reflects the
            // live crosshair position — `.onEnd` can miss the final resting
            // spot and leave a stale coordinate behind on Confirm.
            .onMapCameraChange(frequency: .continuous) { context in
                pinPosition = context.camera.centerCoordinate
            }
        }
    }

    /// Resolve a tapped suggestion to coordinates, move the camera and pin.
    private func select(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        isSearching = true
        searchText = completion.title
        Task {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            let response = try? await search.start()
            if let coord = response?.mapItems.first?.placemark.location?.coordinate {
                cameraPosition = .camera(.init(centerCoordinate: coord, distance: 5000))
                pinPosition = coord
            }
            searchModel.clear()
            isSearching = false
        }
    }
}


// MARK: - Species Picker Sheet

/// The species list: on-device matches first (with a re-scan), then every
/// species, filtered by habitat and searchable. The old three-argument init
/// still works; the extras default to a plain list.
struct SpeciesPickerSheet: View {
    let species: [Species]
    @Binding var selectedId: Int64?
    @Binding var selectedName: String
    var matches: [SpeciesMatch] = []
    var matchesAreUncertain: Bool = false
    var caughtIds: Set<Int64> = []
    var modelDownloading: Bool = false
    var onRescan: (() -> Void)? = nil
    var onRetryDownload: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var habitat: HabitatFilter = .all

    enum HabitatFilter: String, CaseIterable, Hashable {
        case all = "All"
        case freshwater = "Freshwater"
        case marine = "Saltwater"
        case brackish = "Brackish"

        var habitat: Species.Habitat? {
            switch self {
            case .all: return nil
            case .freshwater: return .freshwater
            case .marine: return .marine
            case .brackish: return .brackish
            }
        }
    }

    private var filtered: [Species] {
        var result = species
        if let h = habitat.habitat {
            result = result.filter { $0.habitat == h }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText) ||
                $0.scientificName.localizedCaseInsensitiveContains(searchText) ||
                ($0.family ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var showsMatches: Bool { !matches.isEmpty && searchText.isEmpty && habitat == .all }

    var body: some View {
        NavigationStack {
            List {
                if showsMatches {
                    Section {
                        ForEach(Array(matches.prefix(4).enumerated()), id: \.element.species.id) { _, match in
                            row(match.species, confidence: match.confidence)
                        }
                    } header: {
                        HStack {
                            Text(matchesAreUncertain ? "Closest matches, none are certain" : "Matched on your phone")
                            Spacer()
                            if let onRescan {
                                Button("Scan again") {
                                    onRescan()
                                    dismiss()
                                }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                            }
                        }
                    }
                } else if modelDownloading && searchText.isEmpty {
                    Section {
                        HStack(alignment: .top, spacing: DS.Space.s3) {
                            Image(systemName: "icloud.and.arrow.down")
                                .foregroundStyle(Color.dsText2)
                            Text("Species ID is still downloading. It needs internet once, then works anywhere.")
                                .font(.subheadline)
                                .foregroundStyle(Color.dsText2)
                            Spacer(minLength: 0)
                            if let onRetryDownload {
                                Button("Try again") {
                                    onRetryDownload()
                                    dismiss()
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No species found", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try the common or scientific name.")
                    }
                    .listRowBackground(Color.clear)
                } else if caughtIds.isEmpty {
                    Section(filtered.count == 1 ? "1 species" : "\(filtered.count) species") {
                        ForEach(filtered) { row($0) }
                    }
                } else {
                    let caught = filtered.filter { caughtIds.contains($0.id) }
                    let notYet = filtered.filter { !caughtIds.contains($0.id) }
                    if !caught.isEmpty {
                        Section("In your Fishdex") {
                            ForEach(caught) { row($0) }
                        }
                    }
                    if !notYet.isEmpty {
                        Section("Not caught yet") {
                            ForEach(notYet) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) {
                FilterChips(HabitatFilter.allCases, selection: $habitat, title: { $0.rawValue })
                    .padding(.vertical, DS.Space.s2)
            }
            .navigationTitle("Species")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search \(species.count) species")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                if selectedId != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            selectedId = nil
                            selectedName = ""
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func habitatLine(_ sp: Species) -> String {
        let place: String
        switch sp.habitat {
        case .freshwater: place = "Freshwater"
        case .marine: place = "Saltwater"
        case .brackish: place = "Brackish"
        default: place = sp.family ?? "Fish"
        }
        if let lo = sp.minTempC, let hi = sp.maxTempC, hi > lo {
            return "\(place), best in \(Units.temperature(lo)) to \(Units.temperature(hi))"
        }
        return place
    }

    private func row(_ sp: Species, confidence: Float? = nil) -> some View {
        Button {
            selectedId = sp.id
            selectedName = sp.commonName
            dismiss()
        } label: {
            HStack(spacing: DS.Space.s3) {
                ThumbView(tint: sp.artTint, size: 48) {
                    SpeciesArtworkView(species: sp, caught: true, size: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(sp.commonName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.dsText)
                    Text(confidence == nil ? habitatLine(sp) : sp.scientificName)
                        .font(.subheadline)
                        .italic(confidence != nil)
                        .foregroundStyle(Color.dsText2)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if let confidence {
                    let pct = Int(confidence * 100)
                    Text("\(pct)%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DS.scoreInk(pct))
                }
                if selectedId == sp.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
    }
}

// MARK: - Camera Picker

/// Full-screen system camera for capturing a catch photo directly, so users
/// aren't forced through the photo library.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

