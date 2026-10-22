import SwiftUI
import CoreLocation

// MARK: - One recommendation

struct LureRow: View {
    let suggestion: LureEngine.Suggestion
    /// 1-based position, so the ordering is explicit.
    var rank: Int? = nil
    /// Compact rows (Today) show the lure, colour and depth only.
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ThumbView(tint: DS.scoreColor(Int(suggestion.score * 100)), size: compact ? 52 : 56) {
                LureColorSwatch(name: suggestion.color, size: compact ? 26 : 28)
            }
            .overlay(alignment: .topLeading) {
                if let rank {
                    Text("\(rank)")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(Color.dsOnPrimary)
                        .frame(width: 20, height: 20)
                        .background(Color.dsPrimaryButton, in: Circle())
                        .offset(x: -5, y: -5)
                        .accessibilityLabel("Rank \(rank)")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.lure)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.dsText)
                Text(compact ? "\(suggestion.color), \(suggestion.depth.lowercased())" : suggestion.color)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                if suggestion.isOwned {
                    Label("In your tackle box", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.dsScoreGood)
                }
                if !compact {
                    Text(suggestion.technique)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    FlowChips(items: [suggestion.depth] + suggestion.reasons.prefix(2))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Chips that wrap instead of clipping; reason text varies in length.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(items, id: \.self) { chip($0) } }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { chip($0) }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.dsFill, in: Capsule())
            .foregroundStyle(.dsText2)
            .lineLimit(1)
    }
}

// MARK: - Full list

struct WhatToThrowDetailView: View {
    let suggestions: [LureEngine.Suggestion]
    let clarity: WaterClarity
    let species: Species?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                        VStack(alignment: .leading, spacing: 8) {
                            LureRow(suggestion: s, rank: index + 1)
                            if s.personalCatches > 0 {
                                Label(s.personalCatches == 1 ? "1 of your catches came on this"
                                                             : "\(s.personalCatches) of your catches came on this",
                                      systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.footnote)
                                    .foregroundStyle(Color.dsScoreGood)
                                    .padding(.leading, 70)
                            }
                            if let owned = s.ownedName {
                                Label(owned, systemImage: "shippingbox")
                                    .font(.footnote)
                                    .foregroundStyle(.dsText2)
                                    .padding(.leading, 70)
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                        .padding(.vertical, 12)
                        .dsListRow()
                    }
                } header: {
                    Text("\(clarity.label) water, \(clarity.detail.lowercased())")
                } footer: {
                    Text("Ranked for current water temperature, clarity, light, wind and pressure\(species.map { ", targeting \($0.commonName)" } ?? ""). Lures you own rank first.")
                }

                Section("Colours for \(clarity.label.lowercased()) water") {
                    ForEach(LureEngine.colors(for: clarity, lowLight: false), id: \.self) { name in
                        HStack(spacing: 12) {
                            LureColorSwatch(name: name, size: 22)
                            Text(name).font(.body).foregroundStyle(.dsText)
                        }
                        .padding(.horizontal, DS.gutter)
                        .padding(.vertical, 10)
                        .dsListRow()
                    }
                }
            }
            .dsPlainList()
            .overlay {
                if suggestions.isEmpty {
                    ContentUnavailableView("No suggestions yet", systemImage: "fish",
                                           description: Text("Suggestions appear once the weather has loaded."))
                }
            }
            .navigationTitle("What to throw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Clarity

/// Clear, stained or muddy as a segmented control with a sliding thumb.
struct ClaritySegments: View {
    let selection: WaterClarity
    let onSelect: (WaterClarity) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WaterClarity.allCases) { c in
                let on = c == selection
                Button {
                    withAnimation(DS.Motion.softSpring) { onSelect(c) }
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
        .sensoryFeedback(.selection, trigger: selection)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    .dsListRow()
                }

                Section {
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
                        .dsListRow()
                    }
                } header: {
                    Text("Saved spots")
                } footer: {
                    if spots.isEmpty {
                        Text("Spots you save on the Explore map show up here.")
                    }
                }
            }
            .dsPlainList()
            .navigationTitle("Forecast for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
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
        .presentationDetents([.height(320)])
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
