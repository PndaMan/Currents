import SwiftUI
import CoreLocation

// MARK: - Clarity

/// Clear, stained or muddy as a segmented control with a sliding thumb.
struct ClaritySegments: View {
    let selection: WaterClarity
    let onSelect: (WaterClarity) -> Void
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WaterClarity.allCases) { c in
                let on = c == selection
                Button {
                    if !on { Haptics.selection() }
                    withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { onSelect(c) }
                } label: {
                    Label(c.label, systemImage: c.icon)
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.dsText : Color.dsText2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: DS.Radius.thumb - 2, style: .continuous)
                                    .fill(Color.dsFill2)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.thumb + 1, style: .continuous))
    }
}

// MARK: - Location

/// Where Today's forecast is for: the phone's location or a saved spot.
/// A tap applies straight away, so the sheet only needs "Done".
struct TodayLocationSheet: View {
    let spots: [Spot]
    let selectedSpotId: String
    let locationAuthorized: Bool
    let onSelect: (String) -> Void
    let onRequestLocation: () -> Void
    let onOpenExplore: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Set when "Current location" was tapped with location off, so the row
    /// is chosen as soon as permission comes through.
    @State private var wantsCurrentLocation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if locationAuthorized {
                            onSelect("")
                            dismiss()
                        } else {
                            wantsCurrentLocation = true
                            onRequestLocation()
                        }
                    } label: {
                        ArtRow(title: "Current location",
                               subtitle: locationAuthorized ? "Follows you" : "Location is off. Tap to turn it on") {
                            ThumbView(systemImage: "location.fill", tint: DS.accent, size: 44)
                        } trailing: {
                            if selectedSpotId.isEmpty && locationAuthorized {
                                Image(systemName: "checkmark").foregroundStyle(DS.accent)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(.dsRow)
                    .buttonHaptic(.selection)

                    SectionTitle("Saved spots", detail: spots.isEmpty ? nil : "\(spots.count)")
                        .padding(.top, 20)

                    if spots.isEmpty {
                        InlineEmpty(systemImage: "mappin.slash",
                                    text: "Save a spot on the Explore map to get its forecast here.",
                                    actionTitle: "Open Explore") {
                            dismiss()
                            onOpenExplore()
                        }
                    } else {
                        ForEach(spots) { spot in
                            Button {
                                onSelect(spot.id)
                                dismiss()
                            } label: {
                                ArtRow(title: spot.name, subtitle: spot.type.label) {
                                    PlaceSnapshotThumb(spot: spot, size: 44)
                                } trailing: {
                                    if spot.id == selectedSpotId {
                                        Image(systemName: "checkmark").foregroundStyle(DS.accent)
                                            .accessibilityLabel("Selected")
                                    }
                                }
                            }
                            .buttonStyle(.dsRow)
                            .buttonHaptic(.selection)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("Forecast for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
        .onChange(of: locationAuthorized) { _, granted in
            guard granted, wantsCurrentLocation else { return }
            wantsCurrentLocation = false
            onSelect("")
            dismiss()
        }
        .dsSheet([.medium, .large])
    }
}

// MARK: - Live session

/// The running session: time, catches and the actions for it. Between the
/// days of a multi-day session it shows the day as done, with its time
/// stopped, and a button to start the next one.
struct TodaySessionSheet: View {
    let trip: Trip
    let catches: Int
    let onLogCatch: () -> Void
    let onOpenMap: () -> Void
    let onEnd: () -> Void
    /// False between the days of a multi-day session.
    var isDayActive: Bool = true
    var onStartNextDay: () -> Void = {}
    @AppStorage("use24HourTime") private var use24 = true
    @State private var confirmEnd = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dayDone: Bool { !isDayActive && !trip.decodedDays.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(dayDone ? "Day \(trip.decodedDays.count) done" : "Session running",
                          systemImage: dayDone ? "pause.circle" : "record.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dayDone ? DS.accent : Color.dsScoreSlow)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && !dayDone)
                        .padding(.horizontal, DS.gutter)

                    stats

                    if dayDone {
                        Button("Start day \(trip.decodedDays.count + 1)", action: onStartNextDay)
                            .buttonStyle(.dsPrimary)
                            .padding(.horizontal, DS.gutter)
                    }

                    ActionTriple {
                        Button {
                            dismiss()
                            onLogCatch()
                        } label: {
                            Label("Log catch", systemImage: "plus")
                        }
                        .buttonStyle(ActionTileStyle(.primary))

                        Button {
                            dismiss()
                            onOpenMap()
                        } label: {
                            Label("Live map", systemImage: "map")
                        }
                        .buttonStyle(ActionTileStyle(.tonal))

                        Button { confirmEnd = true } label: {
                            Label("End session", systemImage: "stop.fill")
                        }
                        .buttonStyle(ActionTileStyle(.destructive))
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, 24)
            }
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
        .dsSheet([.medium, .large])
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) {
                dismiss()
                onEnd()
            }
            Button("Keep fishing", role: .cancel) {}
        } message: {
            Text("It will be saved to your Logbook.")
        }
    }

    /// Time fishing counts by the minute while a day runs, and holds still
    /// between days.
    private var stats: some View {
        // Three across, stacked at accessibility sizes.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s3))
        return layout {
            if dayDone {
                StatTile("Time fishing", systemImage: "clock", tint: .blue,
                         value: ForecastFormat.elapsed(trip.totalDurationSeconds), width: nil)
            } else {
                // Redrawn each minute; the total runs to now across every day.
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    StatTile("Time fishing", systemImage: "clock", tint: .blue,
                             value: ForecastFormat.elapsed(trip.totalDurationSeconds), width: nil)
                }
            }
            StatTile("Started", systemImage: "play.circle", tint: .green,
                     value: ForecastFormat.time(trip.startDate, use24: use24), width: nil)
            StatTile("Catches", systemImage: "fish", tint: DS.ink(.orange),
                     value: "\(catches)", width: nil)
        }
        .padding(.horizontal, DS.gutter)
    }
}

/// What the session sheet shows if its session ends while it is open, for
/// the moment before it closes.
struct TodaySessionEndedSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                InlineEmpty(systemImage: "checkmark.circle",
                            text: "This session has ended. You will find it in your Logbook.")
                    .padding(.top, DS.Space.s2)
            }
            .dsScreenBackground()
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
        .dsSheet([.medium, .large])
    }
}
