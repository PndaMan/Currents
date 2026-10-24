import SwiftUI
import CoreLocation

// Shared pieces for the session sheets (plan, new, edit): a big name field,
// tick rows for picking one option, the nearest saved spots, and the bottom
// action bar.

/// The session's name as a large bold field on a fill.
struct TripNameField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.title2.weight(.bold))
            .foregroundStyle(.dsText)
            .submitLabel(.done)
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 14)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Session name")
    }
}

/// One option in a pick-one list: square thumb, title, subtitle, and a tick
/// when it is the chosen one. A saved spot leads with a map of where it is.
struct ChoiceRow<Thumb: View>: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void
    private let thumb: Thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, subtitle: String? = nil, selected: Bool,
         action: @escaping () -> Void, @ViewBuilder thumb: () -> Thumb) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.action = action
        self.thumb = thumb()
    }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : DS.Motion.press) { action() }
        } label: {
            ArtRow(title: title, subtitle: subtitle) {
                thumb
            } trailing: {
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.dsRow)
        .buttonHaptic(.selection)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ChoiceRow where Thumb == ThumbView<ThumbSymbol> {
    /// An option shown by a symbol, such as My location or Drop a pin.
    init(title: String, subtitle: String? = nil, systemImage: String, selected: Bool,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, selected: selected, action: action) {
            ThumbView(systemImage: systemImage, tint: DS.accent, size: 44)
        }
    }
}

extension ChoiceRow where Thumb == PlaceSnapshotThumb {
    /// A saved spot, led by a map of where it is.
    init(spot: Spot, subtitle: String?, selected: Bool, action: @escaping () -> Void) {
        self.init(title: spot.name, subtitle: subtitle, selected: selected, action: action) {
            PlaceSnapshotThumb(spot: spot, size: 44)
        }
    }
}

/// "No spot" plus the nearest saved spots as tick rows, with the rest one
/// tap away.
struct SpotChoices: View {
    @Binding var spotId: String?
    let spots: [Spot]
    var noneTitle = "No spot"
    var noneSubtitle: String? = "Tracks wherever you go"
    var noneIcon = "location.fill"
    @Environment(AppState.self) private var appState
    @State private var showingAll = false

    private static let shortList = 4

    private var here: CLLocation? { appState.locationManager.currentLocation }

    private var sorted: [Spot] {
        guard let here else { return spots }
        return spots.sorted { distance($0, here) < distance($1, here) }
    }

    private var shown: [Spot] {
        guard !showingAll else { return sorted }
        var list = Array(sorted.prefix(Self.shortList))
        // Keep the chosen spot on screen even when it is further away.
        if let id = spotId, !list.contains(where: { $0.id == id }),
           let chosen = spots.first(where: { $0.id == id }) {
            list.insert(chosen, at: 0)
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            ChoiceRow(title: noneTitle, subtitle: noneSubtitle, systemImage: noneIcon,
                      selected: spotId == nil) { spotId = nil }
            ForEach(shown) { spot in
                ChoiceRow(spot: spot, subtitle: subtitle(spot), selected: spotId == spot.id) { spotId = spot.id }
            }
            if showingAll || spots.count > shown.count {
                Button(showingAll ? "Show fewer spots" : "Show all \(spots.count) spots") {
                    withAnimation(DS.Motion.softSpring) { showingAll.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, DS.Space.s3)
            }
        }
    }

    private func distance(_ spot: Spot, _ from: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: from)
    }

    private func subtitle(_ spot: Spot) -> String? {
        guard let here else { return spot.type == .general ? nil : spot.type.label }
        return "\(Units.distance(m: distance(spot, here))) away"
    }
}

/// The sheet's main action, pinned above the home indicator on the page
/// background with a hairline over it.
struct SheetActionBar: View {
    let title: String
    let systemImage: String
    var disabled = false
    let action: () -> Void

    init(_ title: String, systemImage: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.dsPrimary)
        .disabled(disabled)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .frame(maxWidth: .infinity)
        .background {
            Color.dsBackground
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
        }
    }
}

/// A day's best bite windows as equal tiles: time of day, peak score and
/// range. The tile holding `hour` is outlined. With `onSelect` each tile is a
/// button that passes the window's first hour.
struct BiteWindowTiles: View {
    let windows: [BiteWindows.Window]
    let bestHour: Int
    var hour: Int? = nil
    var use24 = true
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        if windows.isEmpty {
            tile(isOn: false, select: bestHour) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(.dsText2)
                    Text("No strong windows. The best hour is \(ForecastFormat.hour(bestHour, use24: use24)).")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(windows) { w in
                    let on = hour.map { $0 >= w.startHour && $0 <= w.endHour } ?? false
                    tile(isOn: on, tint: DS.scoreColor(w.peakScore), select: w.startHour) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(ForecastFormat.windowName(w.startHour),
                                  systemImage: ForecastFormat.windowIcon(w.startHour))
                                .font(.subheadline)
                                .foregroundStyle(.dsText2)
                                .labelStyle(TintedIconLabelStyle(tint: DS.scoreInk(w.peakScore)))
                                .lineLimit(1)
                            Text("\(w.peakScore)")
                                .font(.title.bold())
                                .monospacedDigit()
                                .foregroundStyle(DS.scoreInk(w.peakScore))
                            Text(ForecastFormat.range(w, use24: use24))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.dsText2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func tile<Content: View>(isOn: Bool, tint: Color = .dsText, select: Int,
                                     @ViewBuilder content: () -> Content) -> some View {
        let card = content()
            .padding(12)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(tint, lineWidth: 1.5)
                }
            }
        if let onSelect {
            Button { onSelect(select) } label: { card }
                .buttonStyle(.dim)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Starts the plan at \(ForecastFormat.hour(select, use24: use24))")
        } else {
            card
                .accessibilityElement(children: .combine)
        }
    }
}
