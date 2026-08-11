import SwiftUI

// MARK: - Community section: my Crews

/// A "Crew" is a persistent circle of friends with a shared, ongoing catch
/// feed — the way you keep up with what your friends are catching. Catches you
/// log flow in automatically (per-crew toggle), members can react and caption,
/// and a crew can optionally start a live trip when you fish together.
struct CrewsSection: View {
    @StateObject private var svc = CommunityService.shared

    var body: some View {
        Section("Crews") {
            if svc.myCrews.isEmpty {
                Text("Start a crew to share catches with your friends — everyone's catches land in one feed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(svc.myCrews) { crew in
                NavigationLink {
                    CrewDetailView(code: crew.code)
                } label: {
                    HStack(spacing: 12) {
                        Text(crew.emoji)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(CurrentsTheme.accent.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(crew.name).font(.subheadline.bold())
                            Text(crew.createdByCode == svc.friendCode
                                 ? "You started this · \(crew.code)"
                                 : "Started by \(crew.createdByName) · \(crew.code)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink {
                CrewSetupView()
            } label: {
                Label("New crew", systemImage: "plus.circle.fill")
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }
}

// MARK: - Create or join a crew

struct CrewSetupView: View {
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var emoji = "🎣"
    @State private var joinCode = ""
    @State private var busy = false

    private let emojis = ["🎣", "🐟", "🐠", "🦈", "🌊", "⚓️", "🛥️", "🏆"]

    var body: some View {
        Form {
            Section {
                TextField("Crew name (e.g. The Usual Suspects)", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(emoji == e ? CurrentsTheme.accent.opacity(0.2) : Color(.secondarySystemBackground),
                                            in: Circle())
                                .overlay(Circle().stroke(emoji == e ? CurrentsTheme.accent : .clear, lineWidth: 2))
                                .onTapGesture { Haptics.tap(); emoji = e }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    Task {
                        busy = true
                        let crew = await svc.createCrew(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
                        busy = false
                        if crew != nil {
                            Haptics.success()
                            ToastCenter.shared.show("Crew created 🎣")
                            dismiss()
                        } else {
                            ToastCenter.shared.show("Couldn't create the crew", style: .error)
                        }
                    }
                } label: {
                    Label("Create crew", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Start a crew")
            } footer: {
                Text("Invite friends afterwards. Everyone's catches show up in the crew's feed automatically — you can turn that off per crew.")
            }

            Section {
                CodeField(text: $joinCode, placeholder: "CREW CODE")
                Button {
                    Task {
                        busy = true
                        let crew = await svc.joinCrew(code: joinCode)
                        busy = false
                        if crew != nil {
                            Haptics.success()
                            ToastCenter.shared.show("Joined the crew 🎣")
                            dismiss()
                        } else {
                            ToastCenter.shared.show("Couldn't find that crew", style: .error)
                        }
                    }
                } label: {
                    Label("Join by code", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
            } header: {
                Text("Join a crew")
            } footer: {
                Text("Enter the 6-character code a friend shared with you.")
            }
        }
        .navigationTitle("New Crew")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Crew detail (feed-first)

struct CrewDetailView: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @State private var crew: CommunityService.Crew?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var memberAvatars: [String: UIImage] = [:]
    @State private var feed: [CommunityService.CrewPost] = []
    @State private var isLoading = true
    @State private var showingLeave = false

    private var isMine: Bool { crew?.createdByCode == svc.friendCode }
    private var liveTrip: CommunityService.GroupRef? { svc.activeTrip(forCrew: code) }
    /// The live trip as the server sees it — covers crewmates who haven't
    /// joined yet, for whom the local `activeTrip` lookup knows nothing.
    @State private var serverLiveTrip: CommunityService.GroupTrip?

    var body: some View {
        List {
            headerSection
            if liveTrip != nil { liveTripBanner }
            controlsSection
            feedSection
        }
        .navigationTitle(crew?.name ?? "Crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let crew {
                    ShareLink(item: svc.crewInviteMessage(code: code, name: crew.name)) {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .task {
            // Instant from cache, then refresh.
            crew = svc.crew(withCode: code)
            members = svc.cachedCrewMembers(code)
            feed = svc.cachedCrewFeed(code)
            if !feed.isEmpty || !members.isEmpty { isLoading = false }
            await refresh()
            await pollLoop()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if !Task.isCancelled { await refresh() }
        }
    }

    private func refresh() async {
        if let fresh = await svc.fetchCrew(code: code) { crew = fresh }
        members = await svc.crewMembers(code: code)
        feed = await svc.crewFeed(code: code)
        // Re-read the linked live trip too — groupTrip() records endedAt
        // locally, which is what clears the "is live" banner after the host
        // ends the trip. Without this the banner pulsed forever.
        if let live = svc.activeTrip(forCrew: code) {
            _ = await svc.groupTrip(code: live.code)
        }
        // And ask the server: a crewmate who never joined the trip has no
        // local ref at all, so this is what makes "join an ongoing trip"
        // discoverable to the rest of the crew.
        serverLiveTrip = await svc.liveCrewTrip(crewCode: code)
        isLoading = false
        await loadAvatars()
    }

    /// Fetch each member's profile picture (concurrently) so the roster shows
    /// real avatars, not placeholders.
    private func loadAvatars() async {
        // Instant: whatever's already cached.
        for m in members where memberAvatars[m.id] == nil {
            if let a = svc.cachedProfiles(for: [m.id]).first?.avatar { memberAvatars[m.id] = a }
        }
        // Fresh: fetch any we still don't have.
        let missing = members.map(\.id).filter { memberAvatars[$0] == nil }
        let tasks = missing.map { c in Task { (c, await svc.fetchProfile(code: c)?.avatar) } }
        for t in tasks {
            let (c, avatar) = await t.value
            if let avatar { memberAvatars[c] = avatar }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                Text(crew?.emoji ?? "🎣").font(.system(size: 46))
                Text(crew?.name ?? "Crew").font(.title2.bold())
                Text("\(members.count) member\(members.count == 1 ? "" : "s")\(isMine ? " · you started this" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                if !members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(members) { m in
                                memberChip(m)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func memberChip(_ m: CommunityService.GroupMember) -> some View {
        let chip = VStack(spacing: 4) {
            AnglerAvatar(image: memberAvatars[m.id], size: 48)
            Text(m.id == svc.friendCode ? "You" : m.name)
                .font(.caption2).lineLimit(1).frame(maxWidth: 64)
                .foregroundStyle(.primary)
        }
        // Tapping a crewmate opens their profile; you can't open your own.
        if m.id == svc.friendCode {
            chip
        } else {
            NavigationLink { FriendProfileView(code: m.id) } label: { chip }
                .buttonStyle(.plain)
        }
    }

    // MARK: Live trip banner

    private var liveTripBanner: some View {
        // Prefer my own ref (knows isHost); fall back to the server's view so
        // crewmates who haven't joined still get the banner.
        let mine = liveTrip
        let tripCode = mine?.code ?? serverLiveTrip?.id
        let tripName = mine?.name ?? serverLiveTrip?.name ?? "Live trip"
        let hostName = mine?.hostName ?? serverLiveTrip?.hostName ?? ""
        let amIn = mine != nil

        return Section {
            if let tripCode {
                NavigationLink {
                    GroupTripView(tripId: svc.tripId(forGroupCode: tripCode),
                                  tripName: tripName, initialCode: tripCode)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.red, in: Circle())
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(tripName) is live").font(.subheadline.bold())
                            Text(mine?.isHost == true ? "You're hosting · tap to open"
                                 : amIn ? "You're in · tap to open"
                                 : "Hosted by \(hostName) · tap to join")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !amIn {
                            Text("JOIN")
                                .font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var controlsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { crew?.autoPost ?? true },
                set: { on in
                    svc.setAutoPost(on, forCrew: code)
                    crew?.autoPost = on
                    Haptics.tap()
                    ToastCenter.shared.show(on ? "Auto-posting to this crew" : "Auto-post off for this crew",
                                            style: .info, haptic: false)
                }
            )) {
                Label("Post my catches here", systemImage: "arrow.up.circle.fill")
            }
            .tint(CurrentsTheme.accent)

            NavigationLink {
                GroupTripSetupView(crewCode: code)
            } label: {
                Label(liveTrip == nil && serverLiveTrip == nil ? "Start a live trip" : "Start another trip",
                      systemImage: "dot.radiowaves.left.and.right")
            }

            Button(role: .destructive) {
                showingLeave = true
            } label: {
                Label("Leave crew", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Leave this crew?", isPresented: $showingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task {
                        await svc.leaveCrew(code: code)
                        Haptics.warning()
                        ToastCenter.shared.show("Left the crew", style: .info, haptic: false)
                        dismiss()
                    }
                }
            } message: {
                Text("You'll stop seeing this crew's feed. You can re-join with the code.")
            }
        } footer: {
            Text("A live trip is optional — start one when you're fishing together and everyone's catches post here in real time.")
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feedSection: some View {
        Section("Catches") {
            if feed.isEmpty {
                if isLoading {
                    FishLoader(message: "Loading the feed…")
                        .frame(height: 90).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "No catches yet",
                        systemImage: "fish",
                        description: Text("When you or a crewmate log a catch, it shows up here."))
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(feed) { post in
                    CrewPostCard(post: post, crewCode: code) { await refresh() }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
        }
    }
}

// MARK: - Feed post card

/// A crew catch as a social card: the photo IS the card, species and size on
/// a scrim, and a plain always-visible emoji row for reactions — no menus.
struct CrewPostCard: View {
    let post: CommunityService.CrewPost
    let crewCode: String
    let reload: () async -> Void

    private var svc: CommunityService { .shared }
    @State private var photo: UIImage?
    @State private var editingCaption = false
    @State private var captionDraft = ""
    /// Optimistic reactions, shown the instant you tap and replaced by the
    /// server's truth on the next reload.
    @State private var localReactions: [CommunityService.CrewReaction]?

    private var isMine: Bool { post.authorCode == svc.friendCode }
    private var reactions: [CommunityService.CrewReaction] { localReactions ?? post.reactions }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if post.hasPhoto { photoHero } else { textHero }
            if !post.caption.isEmpty {
                Text(post.caption).font(.subheadline)
            } else if isMine {
                Button("Add a caption…") { startEditingCaption() }
                    .font(.caption).foregroundStyle(CurrentsTheme.accent)
                    .buttonStyle(.plain)
            }
            reactionRow
        }
        .padding(.vertical, 4)
        .task(id: post.id) {
            if post.hasPhoto, photo == nil {
                photo = await svc.crewPostPhoto(recordName: post.id)
            }
        }
        .onChange(of: post.reactions) { _, _ in localReactions = nil }
        .alert("Caption", isPresented: $editingCaption) {
            TextField("Say something…", text: $captionDraft)
            Button("Save") {
                let text = captionDraft
                Task { await svc.setCrewCaption(text, postId: post.id); await reload() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AnglerAvatar(image: svc.cachedProfiles(for: [post.authorCode]).first?.avatar, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMine ? "You" : post.authorName).font(.subheadline.bold())
                Text(post.caughtAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isMine {
                Menu {
                    Button { startEditingCaption() } label: {
                        Label(post.caption.isEmpty ? "Add caption" : "Edit caption",
                              systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    /// Full-bleed photo with the species and size on a bottom scrim, trip tag
    /// floating top-right — the catch is the hero, not a row of metadata.
    private var photoHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.gray.opacity(0.15)).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.species).font(.title3.bold()).foregroundStyle(.white)
                if let size = sizeText {
                    Text(size).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(12)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if !post.tripName.isEmpty {
                Label(post.tripName, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
    }

    /// Photo-less posts still get a proper hero, not a bare text line.
    private var textHero: some View {
        HStack(spacing: 10) {
            Image(systemName: "fish.fill")
                .foregroundStyle(CurrentsTheme.accent)
                .frame(width: 40, height: 40)
                .background(CurrentsTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(post.species).font(.headline)
                if let size = sizeText {
                    Text(size).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !post.tripName.isEmpty {
                Label(post.tripName, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold()).foregroundStyle(CurrentsTheme.accent)
            }
        }
    }

    private var sizeText: String? {
        let parts = [post.weightKg.map { Units.weight(kg: $0) },
                     post.lengthCm.map { Units.length(cm: $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// All five emojis, always visible, tap to toggle. Counts appear beside an
    /// emoji once someone's used it; yours gets the tinted capsule. No menus,
    /// no "React" labels.
    private var reactionRow: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emoji)
        let mine = reactions.first { $0.reactorCode == svc.friendCode }?.emoji
        return HStack(spacing: 6) {
            ForEach(CommunityService.crewReactionEmojis, id: \.self) { emoji in
                let count = grouped[emoji]?.count ?? 0
                let selected = mine == emoji
                Button { toggle(emoji) } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 16))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(selected ? CurrentsTheme.accent : .secondary)
                        }
                    }
                    .padding(.horizontal, count > 0 ? 10 : 8)
                    .padding(.vertical, 6)
                    .background(selected ? AnyShapeStyle(CurrentsTheme.accent.opacity(0.18))
                                         : AnyShapeStyle(.gray.opacity(0.12)),
                                in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(selected ? CurrentsTheme.accent.opacity(0.6) : .clear,
                                               lineWidth: 1)
                    }
                    .opacity(count > 0 || selected ? 1 : 0.65)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ emoji: String) {
        Haptics.tap()
        // Optimistic: the tap shows immediately; the reload swaps in truth.
        var rs = reactions
        if let i = rs.firstIndex(where: { $0.reactorCode == svc.friendCode }) {
            let had = rs[i].emoji
            rs.remove(at: i)
            if had != emoji {
                rs.append(.init(id: "local-\(emoji)", reactorCode: svc.friendCode,
                                reactorName: svc.myName, emoji: emoji))
            }
        } else {
            rs.append(.init(id: "local-\(emoji)", reactorCode: svc.friendCode,
                            reactorName: svc.myName, emoji: emoji))
        }
        localReactions = rs
        Task {
            await svc.toggleCrewReaction(emoji: emoji, postId: post.id,
                                         crewCode: crewCode, postAuthorCode: post.authorCode)
            await reload()
            localReactions = nil
        }
    }

    private func startEditingCaption() {
        captionDraft = post.caption
        editingCaption = true
    }
}

// MARK: - Join a crew from an invite link

/// Presented when the app opens a `currents://crew/<CODE>` deep link. Confirms
/// the crew, then joins with one tap (setting up a Community profile first if
/// the angler hasn't got one yet).
struct JoinCrewConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared

    @State private var crew: CommunityService.Crew?
    @State private var members = 0
    @State private var loading = true
    @State private var joining = false
    @State private var joined = false
    @State private var joinName = ""

    private var alreadyIn: Bool { svc.myCrews.contains { $0.code == code.uppercased() } }

    var body: some View {
        Group {
            if svc.joined { confirmBody } else { joinGate }
        }
        .navigationTitle(svc.joined ? "Join Crew" : "Join Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task {
            crew = await svc.fetchCrew(code: code)
            members = await svc.crewMembers(code: code).count
            loading = false
        }
    }

    private var joinGate: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(crew?.emoji ?? "🎣").font(.system(size: 44))
                    Text("Join “\(crew?.name ?? "a crew")”").font(.title3.bold())
                    Text("Set up your free Currents profile — no account or password, just a name — to join this crew and share catches.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Your angler name") {
                TextField("Name", text: $joinName).textContentType(.givenName)
            }
            Section {
                Button {
                    joining = true
                    Task {
                        await svc.join(name: joinName, region: svc.myRegion)
                        Haptics.success()
                        joining = false
                    }
                } label: {
                    HStack {
                        if joining { ProgressView().tint(.white) }
                        Label("Join & Continue", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(joining || joinName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var confirmBody: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(crew?.emoji ?? "🎣").font(.system(size: 52))
                    Text(crew?.name ?? "Crew").font(.title2.bold())
                    if loading {
                        ProgressView()
                    } else {
                        Text("\(members) member\(members == 1 ? "" : "s") · started by \(crew?.createdByName ?? "an angler")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                if joined || alreadyIn {
                    Label("You're in this crew", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        joining = true
                        Task {
                            let ok = await svc.joinCrew(code: code) != nil
                            joining = false
                            if ok {
                                joined = true
                                Haptics.success()
                                ToastCenter.shared.show("Joined the crew 🎣")
                            } else {
                                ToastCenter.shared.show("Couldn't join that crew", style: .error)
                            }
                        }
                    } label: {
                        HStack {
                            if joining { ProgressView().tint(.white) }
                            Label("Join crew", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                    .disabled(joining || crew == nil)
                }
            } footer: {
                Text("Open the crew from Community once you've joined.")
            }
        }
    }
}
