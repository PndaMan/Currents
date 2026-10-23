import SwiftUI

// MARK: - Friend profiles

/// Friend profiles in friend-list order: cached first (instant), then fresh
/// from iCloud with a placeholder for any that can't be fetched, so a friend
/// never vanishes from the list while still counting against grants.
@MainActor
enum CrewFriendsLoader {
    static func cached() -> [CommunityService.Profile] {
        let svc = CommunityService.shared
        return ordered(svc.cachedProfiles(for: svc.friends), codes: svc.friends)
    }

    /// Batched, concurrent and TTL'd (fresh disk copies skip the network), so
    /// opening the tab doesn't re-download every avatar every time. Fully
    /// offline with cached names on screen keeps the cache rather than
    /// replacing every row with placeholders.
    static func load() async -> [CommunityService.Profile] {
        let svc = CommunityService.shared
        let codes = svc.friends
        guard !codes.isEmpty else { return [] }
        let cachedList = svc.cachedProfiles(for: codes)
        let fetched = await svc.profiles(for: codes, maxAge: 900)
        var result: [CommunityService.Profile] = []
        var resolved = 0
        for code in codes {
            if let p = fetched[code] {
                result.append(p)
                resolved += 1
            } else if let c = cachedList.first(where: { $0.id == code }) {
                result.append(c)
            } else {
                result.append(placeholder(code))
            }
        }
        if resolved == 0 && !cachedList.isEmpty { return ordered(cachedList, codes: codes) }
        return result
    }

    static func placeholder(_ code: String) -> CommunityService.Profile {
        .init(id: code, name: "Angler \(code)", bio: "", region: "", homeWater: "", avatar: nil,
              memberSince: .now, totalCatches: 0, speciesCount: 0, bestWeightKg: 0,
              bestLengthCm: 0, favoriteSpecies: "")
    }

    /// The nickname you gave them, else their first name.
    static func shortName(_ p: CommunityService.Profile) -> String {
        let nick = CommunityService.shared.privacy(for: p.id).nickname
        if !nick.isEmpty { return nick }
        return p.name.split(separator: " ").first.map(String.init) ?? p.name
    }

    /// "Nickname (Name)" or the name.
    static func fullName(_ p: CommunityService.Profile) -> String {
        let nick = CommunityService.shared.privacy(for: p.id).nickname
        return nick.isEmpty ? p.name : "\(nick) (\(p.name))"
    }

    private static func ordered(_ list: [CommunityService.Profile], codes: [String]) -> [CommunityService.Profile] {
        let order = Dictionary(codes.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        return list.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}

// MARK: - Friends page

/// Everyone you've added: requests waiting on you, search, and a way to add
/// more. Pushed from "Friends" on the Crew tab.
struct CrewFriendsPage: View {
    @StateObject private var svc = CommunityService.shared
    @State private var friends: [CommunityService.Profile] = []
    @State private var requests: [CommunityService.FriendRequest] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var showingAdd = false
    @State private var confirmRemove: CommunityService.Profile?
    @ObservedObject private var connection = CrewConnection.shared

    private var filtered: [CommunityService.Profile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return friends }
        return friends.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || CrewFriendsLoader.fullName($0).localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero
                actions
                    .padding(.top, DS.Space.s5)
                // With nothing saved, the empty friends list says it instead.
                if connection.isOffline && !friends.isEmpty {
                    EventNotice("Offline. Showing your friends as last saved.",
                                systemImage: "wifi.slash") { EmptyView() }
                        .padding(.top, DS.Space.s5)
                }
                if !requests.isEmpty {
                    CrewSection(title: "Requests", detail: "\(requests.count)") {
                        ForEach(requests) { req in
                            CrewRequestRow(request: req) { await load() }
                        }
                    }
                }
                friendsSection
                CrewSection(title: "You") {
                    NavigationLink(value: CrewRoute.myProfile) {
                        ArtRow(title: "Your angler profile", subtitle: svc.myName, chevron: true) {
                            CrewAvatar(image: svc.myAvatar, name: svc.myName, size: 56)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .detailTint(nil)
        .eventPageTitle("Friends")
        .sheet(isPresented: $showingAdd, onDismiss: { Task { await load() } }) {
            CrewAddFriendSheet()
        }
        .confirmationDialog("Remove \(confirmRemove?.name ?? "friend")?",
                            isPresented: Binding(get: { confirmRemove != nil },
                                                 set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmRemove) { f in
            Button("Remove friend", role: .destructive) {
                Haptics.warning()
                svc.removeFriend(f.id)
                ToastCenter.shared.show("Friend removed", style: .info, haptic: false)
                Task { await load() }
            }
        } message: { _ in
            Text("They stop seeing your catches and shared spots. You can add them again later.")
        }
        .task { await load() }
        .onChange(of: svc.revision) { _, _ in Task { await load() } }
    }

    /// Today's hero: your code over the title, the count, and your friends'
    /// faces stacked on the right.
    private var hero: some View {
        CommunityHero(label: "Your code \(svc.friendCode)", title: "Friends", line: heroLine) {
            if friends.isEmpty {
                ThumbView(systemImage: "person.2.fill", tint: CrewTint.people, size: 92)
            } else {
                EventAvatarStack(images: friends.prefix(3).map(\.avatar), size: 56)
            }
        }
        .padding(.top, DS.Space.s2)
    }

    private var heroLine: String {
        let n = svc.friends.count
        let base = n == 0 ? "No friends yet" : (n == 1 ? "1 friend" : "\(n) friends")
        guard !requests.isEmpty else { return base }
        return "\(base), \(requests.count) waiting"
    }

    private var actions: some View {
        ActionTriple {
            Button { showingAdd = true } label: {
                Label("Add friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(ActionTileStyle(.primary))
            Button {
                UIPasteboard.general.string = svc.friendCode
                ToastCenter.shared.show("Angler code copied", style: .success)
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            .buttonStyle(ActionTileStyle())
            ShareLink(item: svc.friendInviteMessage()) {
                ActionTileLabel("Invite", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dim)
        }
    }

    private var friendsSection: some View {
        CrewSection(title: "Your friends", detail: svc.friends.isEmpty ? nil : "\(svc.friends.count)") {
            if svc.friends.count > 6 {
                PFSearchField(prompt: "Search friends", text: $query)
                    .padding(.bottom, DS.Space.s2)
            }
            friendsList
        }
    }

    @ViewBuilder private var friendsList: some View {
        if svc.friends.isEmpty {
            InlineEmpty(systemImage: "person.2",
                        text: "No friends yet. Add one with their angler code.",
                        actionTitle: "Add a friend") { showingAdd = true }
        } else if isLoading && friends.isEmpty {
            FishLoader(message: "Loading friends")
                .frame(height: 88).frame(maxWidth: .infinity)
        } else if friends.isEmpty {
            InlineEmpty(systemImage: "wifi.slash",
                        text: connection.isOffline ? "Offline. Your friends load when you're back online."
                                                   : "Couldn't load your friends. Check your connection and come back.")
        } else if filtered.isEmpty {
            InlineEmpty(systemImage: "magnifyingglass", text: "No friends match \"\(query)\".")
        } else {
            ForEach(filtered) { f in
                friendRow(f)
            }
        }
    }

    private func friendRow(_ f: CommunityService.Profile) -> some View {
        NavigationLink(value: CrewRoute.friend(f.id)) {
            ArtRow(title: CrewFriendsLoader.fullName(f), subtitle: friendLine(f), chevron: true) {
                CrewAvatar(image: f.avatar, name: f.name, size: 56)
                    .frame(width: 64, height: 64)
            }
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            Button(role: .destructive) { confirmRemove = f } label: {
                Label("Remove friend", systemImage: "person.badge.minus")
            }
        }
    }

    private func friendLine(_ f: CommunityService.Profile) -> String {
        let catches = f.totalCatches == 1 ? "1 catch" : "\(f.totalCatches) catches"
        let species = f.speciesCount == 1 ? "1 species" : "\(f.speciesCount) species"
        return "\(catches), \(species)"
    }

    private func load() async {
        let cached = CrewFriendsLoader.cached()
        if !cached.isEmpty { friends = cached; isLoading = false }
        requests = await svc.refreshFriendRequests()
        friends = await CrewFriendsLoader.load()
        isLoading = false
    }
}

// MARK: - Requests page

/// Friend requests and trip invites waiting on you. The bell on the Crew tab
/// pushes here.
struct CrewRequestsPage: View {
    @StateObject private var svc = CommunityService.shared
    @State private var requests: [CommunityService.FriendRequest] = []
    @State private var invites: [CommunityService.TripInvite] = []
    @State private var loaded = false
    @State private var openedTrip: CrewOpenedTrip?
    @ObservedObject private var connection = CrewConnection.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CommunityHero(label: "Friends and trips", title: "Requests", line: subtitle) {
                    ThumbView(systemImage: "bell.fill", tint: CrewTint.trophy, size: 92)
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s2)
                if connection.isOffline {
                    EventNotice("Offline. New requests and invites show when you're back online.",
                                systemImage: "wifi.slash") { EmptyView() }
                        .padding(.top, DS.Space.s2)
                }
                if !loaded {
                    FishLoader(message: "Checking for requests")
                        .frame(height: 88).frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s6)
                } else if requests.isEmpty && invites.isEmpty {
                    caughtUp
                        .padding(.top, DS.Space.s4)
                } else {
                    if !requests.isEmpty {
                        CrewSection(title: "Friend requests") {
                            ForEach(requests) { req in
                                CrewRequestRow(request: req) { await load() }
                            }
                        }
                    }
                    if !invites.isEmpty {
                        CrewSection(title: "Trip invites") {
                            ForEach(invites) { inv in inviteRow(inv) }
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .eventPageTitle("Requests")
        .navigationDestination(item: $openedTrip) { trip in
            GroupTripView(tripId: svc.tripId(forGroupCode: trip.code), tripName: trip.name, initialCode: trip.code)
        }
        .task { await load() }
        .onChange(of: svc.revision) { _, _ in Task { await load() } }
    }

    /// Nothing waiting: a green check tile on a card, not a system screen.
    private var caughtUp: some View {
        HStack(spacing: DS.Space.s3) {
            ThumbView(systemImage: "checkmark", tint: .dsScoreGood, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're all caught up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.dsText)
                Text("Friend requests and trip invites show up here.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        guard loaded else { return nil }
        let n = requests.count + invites.count
        return n == 0 ? nil : (n == 1 ? "1 waiting for you" : "\(n) waiting for you")
    }

    private func inviteRow(_ inv: CommunityService.TripInvite) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ArtRow(over: "Invited by \(inv.fromName)", title: inv.tripName,
                   subtitle: inv.date.formatted(.relative(presentation: .named))) {
                ThumbView(systemImage: "person.3.fill", tint: CrewTint.region)
            }
            CrewAcceptDecline(acceptTitle: "Join trip") {
                await svc.acceptInvite(inv)
                ToastCenter.shared.show("Joined the trip", style: .success)
                openedTrip = CrewOpenedTrip(code: inv.groupCode, name: inv.tripName)
                await load()
            } onDecline: {
                Haptics.warning()
                await svc.declineInvite(inv)
                ToastCenter.shared.show("Invite declined", style: .info, haptic: false)
                await load()
            }
            .padding(.leading, DS.gutter + 64 + 14)
            .padding(.trailing, DS.gutter)
            .padding(.bottom, DS.Space.s2)
        }
    }

    private func load() async {
        requests = await svc.refreshFriendRequests()
        invites = await svc.refreshTripInvites()
        loaded = true
    }
}

struct CrewOpenedTrip: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
}

/// One friend request: who it's from (tap for their profile) and the two
/// answers.
struct CrewRequestRow: View {
    let request: CommunityService.FriendRequest
    let reload: () async -> Void
    @State private var avatar: UIImage?
    private var svc: CommunityService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            NavigationLink(value: CrewRoute.friend(request.fromCode)) {
                ArtRow(over: request.date.formatted(.relative(presentation: .named)),
                       title: request.fromName, subtitle: "Wants to be friends", chevron: true) {
                    CrewAvatar(image: avatar, name: request.fromName, size: 56)
                        .frame(width: 64, height: 64)
                }
            }
            .buttonStyle(.dsRow)
            CrewAcceptDecline(acceptTitle: "Accept") {
                await svc.acceptFriendRequest(request)
                ToastCenter.shared.show("You're now friends with \(request.fromName)", style: .success)
                await reload()
            } onDecline: {
                Haptics.warning()
                await svc.declineFriendRequest(request)
                ToastCenter.shared.show("Request declined", style: .info, haptic: false)
                await reload()
            }
            .padding(.leading, DS.gutter + 64 + 14)
            .padding(.trailing, DS.gutter)
            .padding(.bottom, DS.Space.s2)
        }
        .task(id: request.fromCode) {
            avatar = svc.cachedProfiles(for: [request.fromCode]).first?.avatar
            if avatar == nil { avatar = await svc.fetchProfile(code: request.fromCode)?.avatar }
        }
    }
}

/// Accept (primary) and decline (tonal), side by side, each busy while its
/// call runs.
struct CrewAcceptDecline: View {
    var acceptTitle = "Accept"
    let onAccept: () async -> Void
    let onDecline: () async -> Void
    @State private var busy = false

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Button(acceptTitle) {
                busy = true
                Task { await onAccept(); busy = false }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            Button("Decline") {
                busy = true
                Task { await onDecline(); busy = false }
            }
            .buttonStyle(TonalButtonStyle(fullWidth: true))
        }
        .disabled(busy)
    }
}

// MARK: - Add sheet (the plus on the Crew tab)

enum CrewAddChoice {
    case newCrew, groupTrip, addFriend
}

/// What the plus on the Crew tab can start.
struct CrewAddSheet: View {
    let onChoose: (CrewAddChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                option(.newCrew, title: "New crew", subtitle: "A group with a shared feed, challenges and tournaments",
                       systemImage: "person.3.fill", tint: DS.accent)
                option(.groupTrip, title: "Group trip", subtitle: "Fish together now or plan a day",
                       systemImage: "calendar.badge.plus", tint: .dsScoreLow)
                option(.addFriend, title: "Add a friend", subtitle: "Send a request with their angler code",
                       systemImage: "person.badge.plus", tint: .dsScoreGood)
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dsScreenBackground()
            .navigationTitle("Start something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func option(_ choice: CrewAddChoice, title: String, subtitle: String,
                        systemImage: String, tint: Color) -> some View {
        Button { onChoose(choice) } label: {
            ArtRow(title: title, subtitle: subtitle, chevron: true) {
                ThumbView(systemImage: systemImage, tint: tint, size: 56)
            }
        }
        .buttonStyle(.dsRow)
    }
}

// MARK: - Add a friend

/// Your code to share, and a field for theirs.
struct CrewAddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @State private var addCode = ""
    @State private var sending = false
    @State private var error: String?
    @ObservedObject private var connection = CrewConnection.shared

    private var codeReady: Bool {
        addCode.trimmingCharacters(in: .whitespaces).count == 6 || addCode == "90210"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    CommunityHero(label: "Swap codes", title: "Add a friend",
                                  line: "Type the code from their profile.") {
                        ThumbView(systemImage: "person.badge.plus", tint: .dsScoreGood, size: 72)
                    }
                    .padding(.horizontal, -DS.gutter)
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        CodeField(text: $addCode, placeholder: "Their angler code")
                            .onChange(of: addCode) { _, _ in error = nil }
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.dsScoreSlow)
                        }
                        Button {
                            send()
                        } label: {
                            if sending { ProgressView() } else { Text("Send request") }
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(sending || !codeReady)
                    }

                    yourCode
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Your code, labelled like the field above it, with the invite beside
    /// it when it fits and under it at large text sizes.
    private var yourCode: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your angler code")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
            ViewThatFits(in: .horizontal) {
                HStack {
                    CopyableCode(code: svc.friendCode, font: .title2.bold().monospacedDigit())
                    Spacer(minLength: DS.Space.s3)
                    shareInvite
                }
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    CopyableCode(code: svc.friendCode, font: .title2.bold().monospacedDigit())
                    shareInvite
                }
            }
            .padding(DS.Space.s4)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            Text("Friends see your best catches. You choose which spots they see.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .padding(.top, DS.Space.s1)
        }
    }

    private var shareInvite: some View {
        ShareLink(item: svc.friendInviteMessage()) {
            Label("Share invite", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(TonalButtonStyle(fullWidth: false))
    }

    private func send() {
        let code = addCode
        // The Beverly Hills handshake: 90210 isn't a friend code, it's the
        // hidden Bass Daddy achievement.
        if code == "90210" {
            addCode = ""
            let fresh = !BadgeDefinition.bassDaddyUnlocked
            BadgeDefinition.unlockBassDaddy()
            if fresh { Haptics.celebrate(.achievement) } else { Haptics.success() }
            ToastCenter.shared.show(fresh ? "Mythic achievement unlocked: Bass Daddy"
                                          : "Still the Bass Daddy",
                                    style: .success, haptic: false, icon: "crown.fill")
            return
        }
        sending = true
        Task {
            let ok = await svc.sendFriendRequest(to: code)
            sending = false
            if ok {
                addCode = ""
                ToastCenter.shared.show("Friend request sent", style: .success)
                dismiss()
            } else {
                Haptics.error()
                error = connection.isOffline
                    ? "You're offline. Send it again when you're back online."
                    : "No angler matches that code. Check it with your friend."
            }
        }
    }
}
