import SwiftUI
import MapKit

// MARK: - Add spot

/// The new spot form in a sheet of its own. The location inspector pushes
/// `AddSpotForm` inside its own stack instead, so it never stacks sheets.
struct AddSpotSheet: View {
    private let prefillCoordinate: CLLocationCoordinate2D?

    init(prefillCoordinate: CLLocationCoordinate2D? = nil) {
        self.prefillCoordinate = prefillCoordinate
    }

    var body: some View {
        NavigationStack {
            AddSpotForm(prefillCoordinate: prefillCoordinate)
        }
        .dsSheet([.large])
    }
}

/// New spot form: name, location (the dropped pin, or where the angler is
/// standing), type, notes. Cancel and Save sit in the toolbar, so Save stays
/// above the keyboard. Pushed inside another sheet, Cancel goes back.
struct AddSpotForm: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var isPrivate = true
    @State private var spotType: Spot.SpotType = .general
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var isSaving = false

    private let isPushed: Bool
    private let onSaved: (Spot) -> Void

    /// `isPushed` hides the back button, so Cancel is the one way out and a
    /// swipe never drops what was typed. `onSaved` runs after a save that
    /// worked, before the form closes.
    init(prefillCoordinate: CLLocationCoordinate2D? = nil, isPushed: Bool = false,
         onSaved: @escaping (Spot) -> Void = { _ in }) {
        _pinCoordinate = State(initialValue: prefillCoordinate)
        self.isPushed = isPushed
        self.onSaved = onSaved
    }

    private var coordinate: CLLocationCoordinate2D? {
        pinCoordinate ?? appState.locationManager.currentLocation?.coordinate
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { !trimmedName.isEmpty && coordinate != nil && !isSaving }

    private var hasChanges: Bool {
        !trimmedName.isEmpty || !notes.isEmpty || spotType != .general
    }

    var body: some View {
        SpotFormBody(
            name: $name, notes: $notes, isPrivate: $isPrivate, spotType: $spotType,
            coordinate: Binding(get: { coordinate }, set: { pinCoordinate = $0 }),
            usingCurrentLocation: pinCoordinate == nil
        )
        .navigationTitle("New spot")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isPushed)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private func save() {
        guard canSave, let coord = coordinate else { return }
        isSaving = true
        var spot = Spot(
            name: trimmedName,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: notes.isEmpty ? nil : notes,
            isPrivate: isPrivate,
            spotType: spotType
        )
        do {
            try appState.spotRepository.save(&spot)
            ToastCenter.shared.show("\(trimmedName) saved", icon: "mappin.and.ellipse")
            onSaved(spot)
            dismiss()
        } catch {
            isSaving = false
            ToastCenter.shared.show("Couldn't save the spot", style: .error)
        }
    }
}

// MARK: - Edit spot

/// Edits every field of a saved spot, including moving it on the map and
/// its picture. `onSave` stores the change; when it throws, the sheet stays
/// open with an error, so nothing typed is lost.
struct EditSpotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    let onSave: (Spot) throws -> Void

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var isPrivate: Bool = true
    @State private var spotType: Spot.SpotType = .general
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var cover: Spot.Cover = .map
    @State private var coverPhotoPath: String?
    /// Photos stored while picking; the ones not kept go when the sheet closes.
    @State private var pickedPaths: [String] = []
    @State private var saved = false
    @State private var loaded = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasChanges: Bool {
        guard loaded else { return false }
        let moved = coordinate.map { $0.latitude != spot.latitude || $0.longitude != spot.longitude } ?? false
        return trimmedName != spot.name || notes != (spot.notes ?? "") || isPrivate != spot.isPrivate
            || spotType != spot.type || cover != spot.cover || coverPhotoPath != spot.coverPhotoPath || moved
    }

    var body: some View {
        NavigationStack {
            SpotFormBody(
                name: $name, notes: $notes, isPrivate: $isPrivate, spotType: $spotType,
                coordinate: $coordinate,
                usingCurrentLocation: false,
                moveTitle: "Move on map",
                picture: SpotPictureField(spot: spot, cover: $cover, photoPath: $coverPhotoPath,
                                          pickedPaths: $pickedPaths)
            )
            .navigationTitle("Edit spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .task {
                guard !loaded else { return }
                name = spot.name
                notes = spot.notes ?? ""
                isPrivate = spot.isPrivate
                spotType = spot.type
                cover = spot.cover
                coverPhotoPath = spot.coverPhotoPath
                if coordinate == nil {
                    coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                }
                loaded = true
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .dsSheet([.large])
        .onDisappear(perform: clearPickedPhotos)
    }

    /// Removes the photos picked here that the spot does not use, and on
    /// save the photo a new one replaced.
    private func clearPickedPhotos() {
        let kept = saved ? coverPhotoPath : spot.coverPhotoPath
        for path in pickedPaths where path != kept { PhotoManager.delete(path) }
        if saved, let old = spot.coverPhotoPath, old != kept { PhotoManager.delete(old) }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        var updated = spot
        updated.name = trimmedName
        updated.notes = notes.isEmpty ? nil : notes
        updated.isPrivate = isPrivate
        updated.type = spotType
        updated.coverPhotoPath = coverPhotoPath
        updated.cover = cover
        if let coord = coordinate {
            updated.latitude = coord.latitude
            updated.longitude = coord.longitude
            updated.geohash = Geohash.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 7)
        }
        do {
            try onSave(updated)
            saved = true
            dismiss()
        } catch {
            ToastCenter.shared.show("Couldn't save the spot", style: .error)
        }
    }
}

// MARK: - Shared form

private struct SpotFormBody: View {
    @Binding var name: String
    @Binding var notes: String
    @Binding var isPrivate: Bool
    @Binding var spotType: Spot.SpotType
    @Binding var coordinate: CLLocationCoordinate2D?
    let usingCurrentLocation: Bool
    var moveTitle = "Change"
    /// Editing only: a new spot has no catches or picture yet.
    var picture: SpotPictureField? = nil

    @State private var showingLocationPicker = false
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false

    /// Where the spot is kept, which is also the iCloud account when sync is on.
    private var savedWhere: String {
        cloudSyncEnabled && CloudCapability.isAvailable
            ? "Saved on this phone and your iCloud."
            : "Saved on this phone."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                field("Name") {
                    TextField("Spot name", text: $name)
                        .font(.body)
                        .submitLabel(.done)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(minHeight: 50)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                }

                if let picture {
                    field("Picture") { picture }
                }

                field("Location") {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        if let coordinate {
                            MapCover(coordinate: coordinate, distance: 2500)
                                .id("\(coordinate.latitude),\(coordinate.longitude)")
                        }
                        HStack(spacing: DS.Space.s3) {
                            Image(systemName: usingCurrentLocation ? "location.fill" : "mappin.circle.fill")
                                .foregroundStyle(.dsText2)
                            VStack(alignment: .leading, spacing: 2) {
                                if let coordinate {
                                    Text(ExploreFormat.coords(coordinate))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.dsText)
                                    if usingCurrentLocation {
                                        Text("Where you are now")
                                            .font(.footnote)
                                            .foregroundStyle(.dsText2)
                                    }
                                } else {
                                    Text("Waiting for location")
                                        .font(.subheadline)
                                        .foregroundStyle(.dsText2)
                                }
                            }
                            Spacer(minLength: 0)
                            Button(coordinate == nil ? "Choose on map" : moveTitle) {
                                showingLocationPicker = true
                            }
                            .buttonStyle(TonalButtonStyle(fullWidth: false))
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                }

                field("Type") {
                    FilterChips(Spot.SpotType.allCases, selection: $spotType,
                                title: { $0.label }, systemImage: { $0.icon })
                }

                field("Notes") {
                    TextField("What works here, access, parking", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                }

                if FeatureFlags.spotPrivacy {
                    CardGroup {
                        CardToggleRow("Private spot", systemImage: "lock.fill", tint: .indigo, isOn: $isPrivate)
                    }
                }

                ExploreFootnote(savedWhere)
            }
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailScrollEdge()
        .scrollDismissesKeyboard(.interactively)
        .background(Color.dsBackground)
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerSheet(coordinate: $coordinate, pinLabel: "Spot")
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter)
            content()
        }
    }
}
