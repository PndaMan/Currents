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

    @StateObject private var svc = CommunityService.shared
    @State private var crew: CommunityService.Crew?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var memberAvatars: [String: UIImage] = [:]
    @State private var feed: [CommunityService.CrewPost] = []
    @State private var isLoading = true
    @State private var showingLeave = false

    private var isMine: Bool { crew?.createdByCode == svc.friendCode }
    private var liveTrip: CommunityService.GroupRef? { svc.activeTrip(forCrew: code) }

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
        Section {
            if let trip = liveTrip {
                NavigationLink {
                    GroupTripView(tripId: svc.tripId(forGroupCode: trip.code),
                                  tripName: trip.name, initialCode: trip.code)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.red, in: Circle())
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(trip.name) is live").font(.subheadline.bold())
                            Text(trip.isHost ? "You're hosting · tap to open"
                                             : "Hosted by \(trip.hostName) · tap to join")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
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
                Label(liveTrip == nil ? "Start a live trip" : "Start another trip",
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

struct CrewPostCard: View {
    let post: CommunityService.CrewPost
    let crewCode: String
    let reload: () async -> Void

    private var svc: CommunityService { .shared }
    @State private var photo: UIImage?
    @State private var editingCaption = false
    @State private var captionDraft = ""

    private var isMine: Bool { post.authorCode == svc.friendCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if post.hasPhoto {
                photoView
            }
            if !post.tripName.isEmpty {
                Label("on \(post.tripName)", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .foregroundStyle(CurrentsTheme.accent)
            }
            sizeLine
            if !post.caption.isEmpty {
                Text(post.caption).font(.subheadline)
            } else if isMine {
                Button("Add a caption…") { startEditingCaption() }
                    .font(.caption).foregroundStyle(CurrentsTheme.accent)
            }
            reactionBar
        }
        .padding(.vertical, 2)
        .task(id: post.id) {
            if post.hasPhoto, photo == nil {
                photo = await svc.crewPostPhoto(recordName: post.id)
            }
        }
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
            AnglerAvatar(image: svc.cachedProfiles(for: [post.authorCode]).first?.avatar, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMine ? "You" : post.authorName).font(.subheadline.bold())
                Text(post.caughtAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(post.species).font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(CurrentsTheme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(CurrentsTheme.accent)
        }
    }

    @ViewBuilder
    private var photoView: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 200)
                .overlay(ProgressView())
        }
    }

    @ViewBuilder
    private var sizeLine: some View {
        let parts = [
            post.weightKg.map { Units.weight(kg: $0) },
            post.lengthCm.map { Units.length(cm: $0) }
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // Reaction summary chips + a menu to add/toggle mine.
    private var reactionBar: some View {
        let grouped = Dictionary(grouping: post.reactions, by: { $0.emoji })
        let mine = post.reactions.first { $0.reactorCode == svc.friendCode }?.emoji
        return HStack(spacing: 6) {
            ForEach(CommunityService.crewReactionEmojis.filter { grouped[$0] != nil }, id: \.self) { emoji in
                let count = grouped[emoji]?.count ?? 0
                Button {
                    Task { await svc.toggleCrewReaction(emoji: emoji, postId: post.id, crewCode: crewCode); await reload() }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji)
                        Text("\(count)").font(.caption2.monospacedDigit())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(mine == emoji ? CurrentsTheme.accent.opacity(0.2) : Color(.secondarySystemBackground),
                                in: Capsule())
                    .overlay(Capsule().stroke(mine == emoji ? CurrentsTheme.accent : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Menu {
                ForEach(CommunityService.crewReactionEmojis, id: \.self) { emoji in
                    Button {
                        Task { await svc.toggleCrewReaction(emoji: emoji, postId: post.id, crewCode: crewCode); await reload() }
                        Haptics.tap()
                    } label: {
                        Text("\(emoji)  \(mine == emoji ? "Remove" : "React")")
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.subheadline)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
            Spacer()
            if isMine, !post.caption.isEmpty {
                Button {
                    startEditingCaption()
                } label: { Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
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
