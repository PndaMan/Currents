import SwiftUI
import MapKit

// MARK: - Add spot

/// New spot form: name, location (the dropped pin, or where the angler is
/// standing), type, notes. Saves to this phone only.
struct AddSpotSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var isPrivate = true
    @State private var spotType: Spot.SpotType = .general
    @State private var pinCoordinate: CLLocationCoordinate2D?

    init(prefillCoordinate: CLLocationCoordinate2D? = nil) {
        _pinCoordinate = State(initialValue: prefillCoordinate)
    }

    private var coordinate: CLLocationCoordinate2D? {
        pinCoordinate ?? appState.locationManager.currentLocation?.coordinate
    }

    var body: some View {
        NavigationStack {
            SpotFormBody(
                name: $name, notes: $notes, isPrivate: $isPrivate, spotType: $spotType,
                coordinate: Binding(get: { coordinate }, set: { pinCoordinate = $0 }),
                usingCurrentLocation: pinCoordinate == nil,
                saveTitle: "Save spot",
                onSave: save
            )
            .navigationTitle("New spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ToastCenter.shared.show("Give the spot a name", style: .info)
            return
        }
        guard let coord = coordinate else {
            ToastCenter.shared.show("Waiting for your location", style: .info)
            return
        }
        var spot = Spot(
            name: trimmed,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: notes.isEmpty ? nil : notes,
            isPrivate: isPrivate,
            spotType: spotType
        )
        do {
            try appState.spotRepository.save(&spot)
            ToastCenter.shared.show("\(trimmed) saved", icon: "mappin.and.ellipse")
            dismiss()
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
        }
    }
}

// MARK: - Edit spot

/// Edits every field of a saved spot, including moving it on the map and
/// its picture.
struct EditSpotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    let onSave: (Spot) -> Void

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

    var body: some View {
        NavigationStack {
            SpotFormBody(
                name: $name, notes: $notes, isPrivate: $isPrivate, spotType: $spotType,
                coordinate: $coordinate,
                usingCurrentLocation: false,
                moveTitle: "Move on map",
                saveTitle: "Save changes",
                onSave: save,
                picture: SpotPictureField(spot: spot, cover: $cover, photoPath: $coverPhotoPath,
                                          pickedPaths: $pickedPaths)
            )
            .navigationTitle("Edit spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                name = spot.name
                notes = spot.notes ?? ""
                isPrivate = spot.isPrivate
                spotType = spot.type
                cover = spot.cover
                coverPhotoPath = spot.coverPhotoPath
                if coordinate == nil {
                    coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                }
            }
        }
        .presentationDragIndicator(.visible)
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ToastCenter.shared.show("Give the spot a name", style: .info)
            return
        }
        var updated = spot
        updated.name = trimmed
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
        saved = true
        onSave(updated)
        dismiss()
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
    let saveTitle: String
    let onSave: () -> Void
    /// Editing only: a new spot has no catches or picture yet.
    var picture: SpotPictureField? = nil

    @State private var showingLocationPicker = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                field("Name") {
                    TextField("Spot name", text: $name)
                        .font(.body)
                        .focused($nameFocused)
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
                    Toggle("Private spot", isOn: $isPrivate)
                        .padding(.horizontal, DS.gutter)
                }

                VStack(spacing: DS.Space.s3) {
                    Button(saveTitle, action: onSave)
                        .buttonStyle(.dsPrimary)
                        .padding(.horizontal, DS.gutter)
                    ExploreFootnote("Saved on this phone only. Nothing is uploaded.")
                }
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
        .onAppear { if name.isEmpty { nameFocused = true } }
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
