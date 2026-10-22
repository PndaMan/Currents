import SwiftUI

/// A tab root's header: avatar (pushes profile), large title, and an optional
/// glass capsule of icon buttons on the right. Put it first in the root's
/// scroll content and apply `.largeTitleChrome("Title")` to that ScrollView,
/// which hides the navigation bar and backs the status bar once scrolled.
/// At accessibility text sizes the title moves under the avatar row.
struct LargeTitleHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing
    private let showsCapsule: Bool

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
        self.showsCapsule = true
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(spacing: DS.Space.s3) {
                        ProfileAvatarButton()
                        Spacer(minLength: 0)
                        capsule
                    }
                    titleText.lineLimit(2)
                }
            } else {
                HStack(spacing: DS.Space.s3) {
                    ProfileAvatarButton()
                    titleText.lineLimit(1)
                    capsule
                }
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s1)
    }

    private var titleText: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(.dsText)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var capsule: some View {
        if showsCapsule {
            HStack(spacing: 0) { trailing }
                .padding(2)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
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
        // Bar icons keep their size at large text; a long press shows the
        // enlarged icon and name instead, as system bars do.
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }
}
