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
struct TodayLocationSheet: View {
    let spots: [Spot]
    let selectedSpotId: String
    let locationAuthorized: Bool
    let onSelect: (String) -> Void
    let onRequestLocation: () -> Void
    let onOpenExplore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if locationAuthorized {
                            onSelect("")
                            dismiss()
                        } else {
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
                        ContentUnavailableView {
                            Label("No saved spots", systemImage: "mappin.slash")
                        } description: {
                            Text("Save a spot on the Explore map to get its forecast here.")
                        } actions: {
                            Button("Open Explore") {
                                dismiss()
                                onOpenExplore()
                            }
                            .buttonStyle(.dsTonal)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(spots) { spot in
                            Button {
                                onSelect(spot.id)
                                dismiss()
                            } label: {
                                ArtRow(title: spot.name, subtitle: spot.type.rawValue) {
                                    ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: 44)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Live session

/// The running session: timer, catches and the actions for it.
struct TodaySessionSheet: View {
    let trip: Trip
    let catches: Int
    let onLogCatch: () -> Void
    let onOpenMap: () -> Void
    let onEnd: () -> Void
    @AppStorage("use24HourTime") private var use24 = true
    @State private var confirmEnd = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Session running", systemImage: "record.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsScoreSlow)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                Text(trip.name)
                    .font(.title2.bold())
                    .foregroundStyle(.dsText)
            }

            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    stat("Time out", elapsed(since: trip.currentDayStart ?? trip.startDate, now: context.date))
                }
                stat("Started", ForecastFormat.time(trip.startDate, use24: use24))
                stat("Catches", "\(catches)")
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
            .padding(.horizontal, -DS.gutter)
        }
        .padding(DS.gutter)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.dsText2)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}
