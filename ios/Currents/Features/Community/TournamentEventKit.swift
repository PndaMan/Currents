import SwiftUI
import UIKit

// Shared pieces for the event pages (tournament, team, group trip and the
// leaderboard): podium, rank rows, live tag, countdown, cover art, form
// fields, notices and the fading page title.

// MARK: - Ordinals

/// "1st", "2nd", "3rd", localised.
func eventOrdinal(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Times

/// "18:00" today, "Sat 18:00" within the week, "2 Nov, 18:00" further out.
func eventTimeText(_ date: Date, now: Date = .now) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    if abs(date.timeIntervalSince(now)) < 6 * 86_400 {
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
    return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
}

// MARK: - Live tag

/// "Live" in red, with a softly pulsing dot. The pulse stops under Reduce Motion.
struct EventLiveTag: View {
    var title: String = "Live"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.dsScoreSlow)
                .frame(width: 7, height: 7)
                .scaleEffect(on ? 1 : 0.65)
                .opacity(on ? 1 : 0.55)
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.dsScoreSlow)
        }
        .onAppear {
            guard !reduceMotion else { on = true; return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - Page title

private struct EventPageTitle: ViewModifier {
    let title: String
    @State private var showsTitle = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(showsTitle ? 1 : 0)
                        .animation(.easeOut(duration: DS.Motion.fast), value: showsTitle)
                        .accessibilityHidden(!showsTitle)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 110
            } action: { _, new in
                showsTitle = new
            }
            // A firm edge under the bar once the page scrolls, so rows never
            // read through the title (Luma's bar turns solid at this point).
            .detailScrollEdge()
    }
}

/// A sheet's inline title with the crew sheets' text button on the leading
/// side ("Cancel" on forms, "Done" elsewhere), and the same firm edge under
/// the bar as the pushed pages.
private struct EventSheetTitle: ViewModifier {
    let title: String
    let close: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .detailScrollEdge()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(close) { dismiss() }
                }
            }
    }
}

extension View {
    /// Luma's pushed-page title: hidden while the large title block is on
    /// screen, faded into the bar once it scrolls away.
    func eventPageTitle(_ title: String) -> some View {
        modifier(EventPageTitle(title: title))
    }

    /// Title and close button for a sheet's root, inside its NavigationStack.
    /// Forms pass `close: "Cancel"`.
    func eventSheetTitle(_ title: String, close: String = "Done") -> some View {
        modifier(EventSheetTitle(title: title, close: close))
    }
}

// MARK: - Cover

/// Luma's cover art at the top of an event page: the event's best fish on its
/// art colour, or a large symbol on `tint` when there's no fish yet. The page
/// takes its `detailTint` from the same species, so a cover without a fish
/// sits on the plain background.
struct EventCover: View {
    var species: Species?
    var systemImage: String
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .aspectRatio(1.6, contentMode: .fit)
            .overlay {
                ZStack {
                    Color.dsFill
                    (species?.artTint ?? tint).opacity(DS.thumbTintOpacity(scheme))
                    if let species {
                        SpeciesArtworkView(species: species, caught: true, size: 140, fillWidth: true)
                            .padding(.horizontal, DS.Space.s8)
                    } else {
                        Image(systemName: systemImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .foregroundStyle(tint)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
            .accessibilityHidden(true)
    }
}

/// The heaviest (then longest) fish among `catches`, as a species for the
/// cover art. Nil when there are no catches or the name isn't in the guide.
@MainActor
func eventCoverSpecies(_ catches: [CommunityService.GroupCatch], appState: AppState) -> Species? {
    let best = catches.max { a, b in
        (a.weightKg ?? 0, a.lengthCm ?? 0) < (b.weightKg ?? 0, b.lengthCm ?? 0)
    }
    guard let name = best?.species else { return nil }
    return (try? appState.speciesRepository.fetchByCommonName(name)) ?? nil
}

// MARK: - Form fields

/// A labelled control in a sheet form, the same shape as `CrewTextField`:
/// the label above, the control on a filled rounded box. Stack several
/// `EventFormRow`s inside to share one box.
struct EventFormField<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
    }
}

/// One row inside an `EventFormField` box: label on the left, control on
/// the right, a hairline under it unless it's the last.
struct EventFormRow<Trailing: View>: View {
    let label: String
    var showsDivider = true
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: String, showsDivider: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.showsDivider = showsDivider
        self.trailing = trailing()
    }

    var body: some View {
        // At accessibility sizes the control drops under its label, so a
        // wide stepper or date never pushes the row past the screen edge.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: DS.Space.s4))
        VStack(spacing: 0) {
            layout {
                Text(label)
                    .foregroundStyle(Color.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                if !stacked { Spacer(minLength: DS.Space.s2) }
                trailing
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.vertical, stacked ? DS.Space.s3 : DS.Space.s1)
            .padding(.horizontal, DS.Space.s4)
            if showsDivider {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                    .padding(.leading, DS.Space.s4)
            }
        }
    }
}

/// Luma's compact stepper: minus, the value, plus. Swipe up or down with
/// VoiceOver to adjust.
struct EventStepper: View {
    let label: String
    let value: String
    var canDecrement = true
    var canIncrement = true
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            step("minus", enabled: canDecrement, action: decrement)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .contentTransition(.numericText())
            step("plus", enabled: canIncrement, action: increment)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { increment() }
            case .decrement: if canDecrement { decrement() }
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .frame(width: 40, height: 34)
                .background(Color.dsTonal, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Loading

/// Grey placeholder rows while a list loads. Luma never spins in content.
struct EventSkeletonRows: View {
    var count = 3
    var thumbSize: CGFloat = 44
    var label = "Loading"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                        .fill(Color.dsFill)
                        .frame(width: thumbSize, height: thumbSize)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Capsule().fill(Color.dsFill).frame(maxWidth: 180).frame(height: 13)
                        Capsule().fill(Color.dsFill).frame(maxWidth: 110).frame(height: 11)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 10)
            }
        }
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Header

/// The title block of an event page with a custom over line (a live tag, a
/// crew name). Same metrics as `DetailHeader`.
struct EventHeader<Over: View>: View {
    let title: String
    var subtitle: String?
    private let over: Over

    init(title: String, subtitle: String? = nil, @ViewBuilder over: () -> Over) {
        self.title = title
        self.subtitle = subtitle
        self.over = over()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { over }
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.dsText2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Countdown

/// Four ticking cells (days, hours, minutes, seconds) to a target date, with
/// rolling digits. Shows "Overtime" once the target has passed. The caller
/// titles it with a section; `label` is what VoiceOver reads.
struct EventCountdown: View {
    let label: String
    let target: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var digitSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(target.timeIntervalSince(ctx.date)))
                if left == 0 {
                    Text("Overtime. Waiting for an admin to end it.")
                        .font(.headline)
                        .foregroundStyle(Color.dsScoreLow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                } else {
                    let parts: [(value: Int, unit: String)] = [
                        (left / 86400, "Days"), (left / 3600 % 24, "Hours"),
                        (left / 60 % 60, "Minutes"), (left % 60, "Seconds")]
                    // Four across fit up to the largest standard size; the
                    // accessibility sizes get two rows of two so the digits
                    // never squeeze.
                    Group {
                        if typeSize.isAccessibilitySize {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2),
                                                GridItem(.flexible())],
                                      spacing: DS.Space.s2) {
                                ForEach(parts, id: \.unit) { cell(value: $0.value, unit: $0.unit) }
                            }
                        } else {
                            HStack(spacing: DS.Space.s2) {
                                ForEach(parts, id: \.unit) { cell(value: $0.value, unit: $0.unit) }
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label) \(parts[0].value) days, \(parts[1].value) hours, \(parts[2].value) minutes")
                }
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private func cell(value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.system(size: digitSize, weight: .bold, design: .rounded)) // ui-lint: allow, countdown numeral scaled with @ScaledMetric
                .monospacedDigit()
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion ? nil : DS.Motion.easeOut, value: value)
            Text(unit)
                .font(.footnote)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s3)
        .padding(.horizontal, DS.Space.s1)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
    }
}

// MARK: - Avatars

/// One or two overlapping angler avatars (a team shows its first two).
struct EventAvatarStack: View {
    let images: [UIImage?]
    var size: CGFloat = 32
    var ring: Color? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AnglerAvatar(image: images.first ?? nil, size: size)
                .overlay {
                    if let ring { Circle().strokeBorder(ring, lineWidth: max(2, size / 18)) }
                }
            if images.count > 1 {
                AnglerAvatar(image: images[1], size: size * 0.46)
                    .overlay(Circle().strokeBorder(Color.dsBackground, lineWidth: 2))
                    .offset(x: size * 0.1, y: size * 0.04)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Podium

struct EventPodiumEntry: Identifiable {
    let id: String
    let name: String
    let value: String
    var unit: String? = nil
    var images: [UIImage?] = []
    var isMe = false
}

/// The top three on plinths (2nd, 1st, 3rd) with a crown over the leader.
/// Entries are keyed by id, so when the order changes under an animation the
/// anglers slide to their new places and the plinths resize (Luma's FLIP).
struct EventPodium<Destination: View>: View {
    let entries: [EventPodiumEntry]
    let destination: (EventPodiumEntry) -> Destination

    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 22

    init(entries: [EventPodiumEntry], @ViewBuilder destination: @escaping (EventPodiumEntry) -> Destination) {
        self.entries = entries
        self.destination = destination
    }

    private var slots: [(entry: EventPodiumEntry, place: Int)] {
        let top = Array(entries.prefix(3))
        var out: [(entry: EventPodiumEntry, place: Int)] = []
        if top.count > 1 { out.append((top[1], 2)) }
        if !top.isEmpty { out.append((top[0], 1)) }
        if top.count > 2 { out.append((top[2], 3)) }
        return out
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            ForEach(slots, id: \.entry.id) { slot in
                NavigationLink {
                    destination(slot.entry)
                } label: {
                    column(slot.entry, place: slot.place)
                }
                .buttonStyle(.dim)
                .accessibilityLabel("\(eventOrdinal(slot.place)), \(slot.entry.name), \(slot.entry.value) \(slot.entry.unit ?? "")")
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
    }

    private func ring(_ place: Int) -> Color {
        switch place {
        case 1: return .dsScoreFair
        case 2: return .dsText3 // ui-lint: allow, silver medal
        default: return .dsScoreLow
        }
    }

    private func plinthFill(_ place: Int) -> Color {
        switch place {
        case 1: return Color.dsScoreFair.opacity(0.28)
        case 2: return .dsFill2
        default: return Color.dsScoreLow.opacity(0.26)
        }
    }

    private func column(_ e: EventPodiumEntry, place: Int) -> some View {
        VStack(spacing: DS.Space.s1) {
            Image(systemName: "crown.fill")
                .font(.title3)
                .foregroundStyle(Color.dsScoreFair)
                .opacity(place == 1 ? 1 : 0)
            EventAvatarStack(images: e.images, size: place == 1 ? 76 : 62, ring: ring(place))
                .padding(.bottom, DS.Space.s1)
            Text(e.isMe ? "\(e.name) (you)" : e.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(e.value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded)) // ui-lint: allow, podium numeral scaled with @ScaledMetric
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit = e.unit {
                    Text(unit).font(.subheadline).foregroundStyle(Color.dsText2)
                }
            }
            .foregroundStyle(Color.dsText)
            // Three columns share the width; big numbers shrink, never wrap.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.button, topTrailingRadius: DS.Radius.button,
                                   style: .continuous)
                .fill(plinthFill(place))
                .frame(height: place == 1 ? 112 : place == 2 ? 80 : 56)
                .overlay(alignment: .top) {
                    Text("\(place)")
                        .font(.title2.bold())
                        .foregroundStyle(Color.dsText)
                        .padding(.top, DS.Space.s2)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rank row

/// A ranked row: number, avatar, name with a subtitle, value on the right.
/// Your own row is tinted with the accent.
struct EventRankRow: View {
    let rank: Int
    let name: String
    var subtitle: String? = nil
    let value: String
    var images: [UIImage?] = []
    var isMe = false

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText2)
                .frame(minWidth: 22)
                .contentTransition(.numericText())
            EventAvatarStack(images: images, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMe ? DS.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notice

/// A one-line notice with an optional inline text action, in the same box
/// as Today's location notice ("Offline. Standings as of 10:42.  Try again").
struct EventNotice<Action: View>: View {
    let text: String
    let systemImage: String
    private let action: Action

    init(_ text: String, systemImage: String, @ViewBuilder action: () -> Action) {
        self.text = text
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: systemImage)
                .foregroundStyle(.dsText2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .buttonStyle(.dim)
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

/// The offline line for a page showing its last load: "Offline. Standings
/// as of 10:42." or, with nothing loaded yet, "Offline. Standings load when
/// you're back online."
func eventOfflineText(_ what: String, since: Date?) -> String {
    guard let since else { return "Offline. \(what) load when you're back online." }
    return "Offline. \(what) as of \(since.formatted(date: .omitted, time: .shortened))."
}
