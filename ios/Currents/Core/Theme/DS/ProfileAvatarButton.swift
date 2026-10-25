import SwiftUI

/// The angler's avatar at the left of every tab's large title. Pushes
/// Profile and settings (`AppRoute.profile`) in the current tab's stack.
struct ProfileAvatarButton: View {
    var size: CGFloat = 38
    @ObservedObject private var community = CommunityService.shared
    @AppStorage("communityName") private var name = ""

    var body: some View {
        NavigationLink(value: AppRoute.profile) {
            avatar
        }
        .buttonStyle(.dim)
        .accessibilityLabel("Profile and settings")
    }

    private var initial: String? {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
    }

    @ViewBuilder
    private var avatar: some View {
        // Re-read the avatar file whenever the profile changes.
        let _ = community.revision
        ZStack {
            Circle().fill(.tint)
            if let image = community.myAvatar {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let initial {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "figure.fishing")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
