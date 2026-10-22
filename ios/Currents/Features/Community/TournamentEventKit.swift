import SwiftUI
import UIKit

// Shared pieces for the event pages (tournament, team, group trip and the
// leaderboard): podium, rank rows, live tag, countdown, key-value list and
// the fading page title.

// MARK: - Ordinals

/// "1st", "2nd", "3rd", localised.
func eventOrdinal(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
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
    }
}

extension View {
    /// Luma's pushed-page title: hidden while the large title block is on
    /// screen, faded into the bar once it scrolls away.
    func eventPageTitle(_ title: String) -> some View {
        modifier(EventPageTitle(title: title))
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

// MARK: - Section

/// A page section: title3 heading then content, with Luma's spacing.
struct EventSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    private let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title, detail: detail)
            content
        }
        .padding(.top, DS.Space.s8)
    }
}

/// A short secondary note under a section.
struct EventFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.dsText2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
    }
}

/// Inline empty state inside a section: icon and one line.
struct EventInlineEmpty: View {
    let text: String
    var systemImage: String = "fish"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.dsText3)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Key-value list

/// The grouped label and value rows used for rules, totals and sessions.
struct EventKeyValueList: View {
    struct Row {
        let label: String
        let value: String
        var emphasized = false
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                    Text(row.label)
                        .foregroundStyle(Color.dsText)
                        .fontWeight(row.emphasized ? .semibold : .regular)
                    Spacer(minLength: DS.Space.s4)
                    Text(row.value)
                        .foregroundStyle(row.emphasized ? Color.dsText : Color.dsText2)
                        .fontWeight(row.emphasized ? .semibold : .regular)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.numericText())
                }
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 13)
                .accessibilityElement(children: .combine)
                if i < rows.count - 1 {
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                        .padding(.leading, DS.Space.s4)
                }
            }
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Countdown

/// Four ticking cells (days, hours, minutes, seconds) to a target date, with
/// rolling digits. Shows "Overtime" once the target has passed.
struct EventCountdown: View {
    let label: String
    let target: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var digitSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
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
                    HStack(spacing: DS.Space.s2) {
                        ForEach(parts, id: \.unit) { value, unit in
                            VStack(spacing: 2) {
                                Text(String(format: "%02d", value))
                                    .font(.system(size: digitSize, weight: .bold, design: .rounded)) // ui-lint: allow, countdown numeral scaled with @ScaledMetric // ui-lint: allow, countdown numeral
                                    .monospacedDigit()
                                    .foregroundStyle(Color.dsText)
                                    .contentTransition(.numericText(countsDown: true))
                                    .animation(reduceMotion ? nil : DS.Motion.easeOut, value: value)
                                Text(unit)
                                    .font(.footnote)
                                    .foregroundStyle(Color.dsText2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s3)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label) \(parts[0].value) days, \(parts[1].value) hours, \(parts[2].value) minutes")
                }
            }
        }
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
                    .font(.system(size: valueSize, weight: .bold, design: .rounded)) // ui-lint: allow, podium numeral scaled with @ScaledMetric // ui-lint: allow, big stat numeral
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit = e.unit {
                    Text(unit).font(.subheadline).foregroundStyle(Color.dsText2)
                }
            }
            .foregroundStyle(Color.dsText)
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

// MARK: - Banner

/// A one-line notice with an inline action ("You're watching this trip").
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
                .foregroundStyle(Color.dsText2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.dsText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s2)
            action
        }
        .padding(.leading, DS.Space.s4)
        .padding(.trailing, DS.Space.s3)
        .padding(.vertical, DS.Space.s3)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

/// A full-width destructive tonal button at the foot of a page
/// ("Leave trip", "End tournament").
struct EventDangerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.dsScoreSlow)
        }
        .buttonStyle(.dsTonal)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
    }
}
