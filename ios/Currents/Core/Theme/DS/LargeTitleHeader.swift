import SwiftUI

/// A tab root's header: avatar (pushes profile), large title, and an optional
/// glass capsule of icon buttons on the right. Put it first in the root's
/// scroll content and hide the navigation bar on that root:
/// `.toolbar(.hidden, for: .navigationBar)`.
struct LargeTitleHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing
    private let showsCapsule: Bool

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
        self.showsCapsule = true
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ProfileAvatarButton()
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if showsCapsule {
                HStack(spacing: 0) { trailing }
                    .padding(2)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s1)
    }
}

extension LargeTitleHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
        self.showsCapsule = false
    }
}

/// The icon used inside a `LargeTitleHeader` capsule (42 x 40), with an
/// optional red unread dot. Use as a NavigationLink or Menu label.
struct HeaderIconLabel: View {
    let systemImage: String
    var showsDot: Bool = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.dsText)
            .frame(width: 42, height: 40)
            .overlay(alignment: .topTrailing) {
                if showsDot {
                    Circle()
                        .fill(Color.dsScoreSlow)
                        .frame(width: 8, height: 8)
                        .padding(.top, 9)
                        .padding(.trailing, 10)
                }
            }
            .contentShape(Rectangle())
    }
}

/// An icon-only button for a `LargeTitleHeader` capsule. `label` is read by
/// VoiceOver.
struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    var showsDot: Bool = false
    let action: () -> Void

    init(_ label: String, systemImage: String, showsDot: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.showsDot = showsDot
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HeaderIconLabel(systemImage: systemImage, showsDot: showsDot)
        }
        .buttonStyle(.dim)
        .accessibilityLabel(label)
    }
}
