import SwiftUI
import UIKit

// Shared pieces for the event pages (tournament, team, group trip and the
// leaderboard): rank rows, live tag, cover art, form fields, notices and
// the fading page title.

// MARK: - Ordinals

/// "1st", "2nd", "3rd", localised.
func eventOrdinal(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Times

/// "18:00" today, "Sat 18:00" within the week, "2 Nov, 18:00" further out,
/// day before month whatever the region. Views pass their
/// `@AppStorage("use24HourTime")` value so they redraw when the setting
/// changes.
func eventTimeText(_ date: Date, now: Date = .now, use24: Bool = ForecastFormat.use24) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) {
        return ForecastFormat.time(date, use24: use24)
    }
    // The time part follows the 24-hour setting; only the day comes from
    // the system formatter.
    if abs(date.timeIntervalSince(now)) < 6 * 86_400 {
        return "\(ForecastFormat.shortDay(date)) \(ForecastFormat.time(date, use24: use24))"
    }
    return "\(LogbookFormat.shortDay(date)), \(ForecastFormat.time(date, use24: use24))"
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
                .foregroundStyle(DS.ink(.dsScoreSlow))
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
    var threshold: CGFloat? = 110
    @State private var showsTitle = false

    func body(content: Content) -> some View {
        content
            .pageTitleTracking($showsTitle, threshold: threshold)
            // A firm edge under the bar once the page scrolls, so rows never
            // read through the title (Luma's bar turns solid at this point).
            .detailScrollEdge()
            // Outside the bar backdrop, so its hairline draws over it.
            .pageInlineTitle(title, shown: showsTitle)
    }
}

/// A sheet's inline title with the standard close button, and the same firm
/// edge under the bar as the pushed pages. Viewers get Done on the trailing
/// side, as the Explore sheets do; forms get Cancel on the leading side and
/// add their own commit button at `.confirmationAction`.
private struct EventSheetTitle: ViewModifier {
    let title: String
    let close: String
    @Environment(\.dismiss) private var dismiss

    private var isDone: Bool { close == "Done" }

    func body(content: Content) -> some View {
        content
            .detailScrollEdge()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDone {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton()
                    }
                }
                if !isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(close) { dismiss() }
                    }
                }
            }
    }
}

extension View {
    /// Luma's pushed-page title: hidden while the large title block is on
    /// screen, faded into the bar once it scrolls away. `threshold` is the
    /// scroll, in points, at which that block has gone; pass nil when a
    /// `DetailHeader` is at the top, to follow its measured height.
    func eventPageTitle(_ title: String, threshold: CGFloat? = 110) -> some View {
        modifier(EventPageTitle(title: title, threshold: threshold))
    }

    /// Title and close button for a sheet's root, inside its NavigationStack.
    /// Forms pass `close: "Cancel"` and add a named commit button at
    /// `.confirmationAction`. The sheet's root still ends with `.dsSheet`.
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
/// the label above, the control on a filled rounded box.
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
/// Always three equal columns: a place nobody holds yet shows its plinth
/// dimmed. Entries are keyed by id, so when the order changes under an
/// animation the anglers slide to their new places and the plinths resize.
struct EventPodium<Destination: View>: View {
    let entries: [EventPodiumEntry]
    let destination: (EventPodiumEntry) -> Destination

    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 22

    init(entries: [EventPodiumEntry], @ViewBuilder destination: @escaping (EventPodiumEntry) -> Destination) {
        self.entries = entries
        self.destination = destination
    }

    /// One place on the podium, held or not yet held.
    private struct Slot: Identifiable {
        let place: Int
        let entry: EventPodiumEntry?
        var id: String { entry?.id ?? "empty-\(place)" }
    }

    private var slots: [Slot] {
        let top = Array(entries.prefix(3))
        return [2, 1, 3].map { place in
            Slot(place: place, entry: place <= top.count ? top[place - 1] : nil)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s2) {
            ForEach(slots) { slot in
                if let entry = slot.entry {
                    NavigationLink {
                        destination(entry)
                    } label: {
                        EventPodiumColumn(entry: entry, place: slot.place, valueSize: valueSize)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("\(eventOrdinal(slot.place)), \(entry.name), \(entry.value) \(entry.unit ?? "")")
                } else {
                    EventPodiumPlinth(place: slot.place)
                        .opacity(0.4)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
    }
}

/// One podium place: crown (first only), ringed avatar, name, value and the
/// numbered plinth in the medal colour.
struct EventPodiumColumn: View {
    let entry: EventPodiumEntry
    let place: Int
    var valueSize: CGFloat = 22

    static func medal(_ place: Int) -> Color {
        switch place {
        case 1: return .dsScoreFair
        // Opaque, so the ring reads as a ring over the photo, not a haze.
        case 2: return .gray
        default: return .dsScoreLow
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Image(systemName: "crown.fill")
                .font(.title3)
                .foregroundStyle(DS.ink(.dsScoreFair))
                .opacity(place == 1 ? 1 : 0)
            EventAvatarStack(images: entry.images, size: place == 1 ? 76 : 62, ring: Self.medal(place))
                .padding(.bottom, DS.Space.s1)
            Text(entry.isMe ? "\(entry.name) (you)" : entry.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            valueLine
            EventPodiumPlinth(place: place)
        }
        .frame(maxWidth: .infinity)
    }

    private var valueLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(entry.value)
                .font(.system(size: valueSize, weight: .bold)) // ui-lint: allow, podium numeral scaled with @ScaledMetric
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit = entry.unit {
                Text(unit).font(.subheadline).foregroundStyle(Color.dsText2)
            }
        }
        .foregroundStyle(Color.dsText)
        // Three columns share the width; big numbers shrink, never wrap.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// The numbered block under a podium place, in the medal colour and
/// stepped by place.
private struct EventPodiumPlinth: View {
    let place: Int

    private var fill: Color {
        switch place {
        case 1: return Color.dsScoreFair.opacity(0.28)
        case 2: return .dsFill2
        default: return Color.dsScoreLow.opacity(0.26)
        }
    }

    private var height: CGFloat {
        switch place {
        case 1: return 112
        case 2: return 80
        default: return 56
        }
    }

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: DS.Radius.button, topTrailingRadius: DS.Radius.button,
                               style: .continuous)
            .fill(fill)
            .frame(height: height)
            .overlay(alignment: .top) {
                Text("\(place)")
                    .font(.title2.bold())
                    .foregroundStyle(Color.dsText)
                    .padding(.top, DS.Space.s2)
            }
    }
}

// MARK: - Rank row

/// A ranked row: number, avatar, name with a subtitle, value on the right,
/// and a chevron when the row opens a profile. Your own row sits on a
/// rounded accent band inset from the page edge; the numbers stay on the
/// gutter in every row.
struct EventRankRow: View {
    let rank: Int
    let name: String
    var subtitle: String? = nil
    let value: String
    var images: [UIImage?] = []
    var isMe = false
    var showsChevron = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if let subtitle, !subtitle.isEmpty {
                    // Two lines, as ArtRow's subtitle, so a figure is never cut.
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
            }
            Spacer(minLength: DS.Space.s2)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText)
                .contentTransition(.numericText())
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsText3)
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.accent.opacity(0.12))
            }
        }
        .padding(.horizontal, DS.gutter - DS.Space.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notice

/// A one-line notice with an optional action, in the same box as Today's
/// location notice ("Offline. Standings as of 10:42." and Try again). The
/// action is a small tonal button, so it reads as a button; at
/// accessibility sizes it moves under the text.
struct EventNotice<Action: View>: View {
    let text: String
    let systemImage: String
    private let action: Action
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ text: String, systemImage: String, @ViewBuilder action: () -> Action) {
        self.text = text
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
            : AnyLayout(HStackLayout(spacing: DS.Space.s3))
        layout {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: systemImage)
                    .foregroundStyle(.dsText2)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            action
                .buttonStyle(TonalButtonStyle(fullWidth: false))
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
    return "Offline. \(what) as of \(ForecastFormat.time(since))."
}
