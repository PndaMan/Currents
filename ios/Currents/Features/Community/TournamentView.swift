import SwiftUI
import UIKit

// MARK: - Team colour

/// A stable colour per team code — same djb2-into-palette approach the group
/// trip screen uses for members, so a team reads consistently everywhere.
private func teamColor(_ code: String) -> Color {
    let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]
    var h = 5381
    for u in code.unicodeScalars { h = (h &* 33) &+ Int(u.value) }
    return palette[abs(h) % palette.count]
}

/// "Ends in 3h 12m" / "Overtime" once past due.
private func countdownLabel(to end: Date, now: Date) -> String {
    let s = end.timeIntervalSince(now)
    guard s > 0 else { return "Overtime" }
    let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
    return h > 0 ? "Ends in \(h)h \(m)m" : "Ends in \(m)m"
}

// MARK: - Tournament setup

/// Start a crew tournament: a name, an optional end time, done. Teams are
/// live sessions crewmates create or join afterwards.
struct TournamentSetupView: View {
    let crew: CommunityService.Crew
    var onCreated: (CommunityService.Tournament) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var hasEnd = false
    @State private var endsAt = Date().addingTimeInterval(6 * 3600)
    @State private var busy = false
    @State private var customScoring = false
    @State private var perFish = TournamentPoints.standard.perFish
    @State private var perKg = TournamentPoints.standard.perKg
    @State private var speciesBonus = TournamentPoints.standard.newSpeciesBonus

    var body: some View {
        NavigationStack {
            Form {
                Section("Tournament name") {
                    TextField("e.g. Winter Classic", text: $name)
                }
                Section {
                    Toggle("Set an end time", isOn: $hasEnd.animation(.snappy))
                        .tint(CurrentsTheme.accent)
                    if hasEnd {
                        DatePicker("Ends", selection: $endsAt, in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    Text("Teams are live sessions — crewmates create or join one and every catch scores points. Without an end time, an admin ends the tournament manually.")
                }
                Section {
                    Toggle("Custom scoring", isOn: $customScoring.animation(.snappy))
                        .tint(CurrentsTheme.accent)
                    if customScoring {
                        Stepper(value: $perFish, in: 0...100) {
                            scoringRow("Per fish landed", value: perFish)
                        }
                        Stepper(value: $perKg, in: 0...50) {
                            scoringRow("Per kilogram (rounded)", value: perKg)
                        }
                        Stepper(value: $speciesBonus, in: 0...100) {
                            scoringRow("New species bonus", value: speciesBonus)
                        }
                    }
                } footer: {
                    Text(customScoring
                         ? "Weight a tournament toward what matters — set a rate to 0 to ignore it entirely."
                         : "Standard scoring: \(TournamentPoints.standard.perFish) per fish, +\(TournamentPoints.standard.perKg)/kg, +\(TournamentPoints.standard.newSpeciesBonus) for each new species.")
                }
                Section {
                    Button {
                        create()
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Label("Create tournament", systemImage: "trophy.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func scoringRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value) pt\(value == 1 ? "" : "s")")
                .foregroundStyle(CurrentsTheme.accent)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func create() {
        busy = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let rates = customScoring
            ? TournamentPoints.Rates(perFish: perFish, perKg: perKg, newSpeciesBonus: speciesBonus)
            : TournamentPoints.standard
        Task {
            let t = await svc.createTournament(name: trimmed, crew: crew,
                                               endsAt: hasEnd ? endsAt : nil,
                                               rates: rates)
            busy = false
            if let t {
                Haptics.success()
                ToastCenter.shared.show("Tournament started 🏆", style: .success)
                dismiss()
                onCreated(t)
            } else {
                ToastCenter.shared.show("Couldn't create the tournament", style: .error)
            }
        }
    }
}

// MARK: - Tournament screen

/// The tournament hub: live team standings with points, joining/creating a
/// team, the scoring explainer, and the admin end-and-declare-winner flow.
struct TournamentView: View {
    let crew: CommunityService.Crew

    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared
    @State private var tournament: CommunityService.Tournament
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var profiles: [String: CommunityService.Profile] = [:]
    @State private var crewMembers: [CommunityService.GroupMember] = []
    @State private var loading = true
    @State private var showingInfo = false
    @State private var showingEnd = false
    @State private var newTeamName = ""
    @State private var creatingTeam = false
    @State private var shareImage: UIImage?
    @State private var showingShare = false

    init(tournament: CommunityService.Tournament, crew: CommunityService.Crew) {
        self.crew = crew
        _tournament = State(initialValue: tournament)
    }

    private var myTeam: CommunityService.TeamStanding? {
        standings.first { $0.memberCodes.contains(svc.friendCode) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                if tournament.isEnded, let winner = tournament.winnerTeam {
                    winnerBanner(winner)
                }
                hero
                highlightsSection
                standingsSection
                if myTeam == nil && !tournament.isEnded { joinArea }
                if svc.myRole(in: crew).canRunTournaments && !tournament.isEnded {
                    Button(role: .destructive) {
                        showingEnd = true
                    } label: {
                        Label("End tournament", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    shareImage = TournamentShareCard.render(
                        tournament: tournament, crewName: crew.name, standings: standings)
                    if shareImage != nil { showingShare = true }
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share tournament card")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("How points work")
            }
        }
        .sheet(isPresented: $showingShare) {
            if let shareImage {
                ImageShareSheet(image: shareImage,
                                filename: "Currents-\(tournament.name)",
                                caption: TournamentShareCard.caption(tournament: tournament,
                                                                     standings: standings))
            }
        }
        .sheet(isPresented: $showingInfo) { infoSheet }
        .sheet(isPresented: $showingEnd) {
            EndTournamentSheet(tournament: tournament, crew: crew, standings: standings) { winner in
                tournament.endedAt = .now
                tournament.winnerTeam = winner
                // Team sessions are ended server-side with the tournament —
                // close my own local GPS session too if it was one of them.
                if let active = appState.tripTracker.activeTrip,
                   let linked = svc.groupCode(forTripId: active.id),
                   standings.contains(where: { $0.id == linked }) {
                    _ = appState.tripTracker.end()
                    ToastCenter.shared.show("Your team session ended with the tournament",
                                            style: .info, haptic: false)
                }
                Task { await refresh() }
            }
        }
        .task {
            await refresh()
            await pollLoop()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            if !tournament.isEnded { await refresh() }
        }
    }

    private func refresh() async {
        async let freshTournament = svc.activeTournament(crewCode: crew.code)
        async let members = svc.crewMembers(code: crew.code)
        if let fresh = await freshTournament, fresh.id == tournament.id {
            tournament = fresh
        }
        crewMembers = await members
        standings = await svc.teamStandings(tournament: tournament)
        // Lock Screen scoreboard: starts when you're on a team, updates with
        // every refresh, ends with the tournament.
        TournamentActivityManager.shared.sync(
            tournament: tournament, standings: standings, myCode: svc.friendCode)
        let codes = Array(Set(standings.flatMap(\.memberCodes)))
        if !codes.isEmpty {
            profiles = await svc.profiles(for: codes)
        }
        loading = false
    }

    /// Crewmates not yet on any team — the pool an admin can assign from.
    private var unassignedMembers: [CommunityService.GroupMember] {
        crewMembers.filter { m in !standings.contains { $0.memberCodes.contains(m.id) } }
    }

    private var canAssign: Bool {
        svc.myRole(in: crew).canRunTournaments && !tournament.isEnded
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.title3).foregroundStyle(.yellow)
                Text(tournament.name).font(.title3.bold())
                Spacer()
                if tournament.isEnded {
                    Text("Ended")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.gray.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                } else {
                    Text("LIVE")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            Text("Hosted by \(tournament.hostName)")
                .font(.caption).foregroundStyle(.secondary)
            if !tournament.isEnded, let ends = tournament.endsAt {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Label(countdownLabel(to: ends, now: ctx.date), systemImage: "clock")
                        .font(.caption.bold())
                        .foregroundStyle(ends > ctx.date ? Color.secondary : .orange)
                }
            }
            HStack(spacing: 12) {
                Label("\(standings.count) \(standings.count == 1 ? "team" : "teams")",
                      systemImage: "person.3.fill")
                Label("\(standings.reduce(0) { $0 + $1.fishCount }) fish", systemImage: "fish.fill")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Highlights

    /// The tournament's headline moments — most fish, biggest, first — each
    /// pinned to the angler (avatar + name) and their team.
    @ViewBuilder private var highlightsSection: some View {
        let highlights = CommunityService.tournamentHighlights(from: standings)
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Highlights", systemImage: "sparkles").font(.headline)
                ForEach(highlights) { h in
                    HStack(spacing: 10) {
                        Image(systemName: h.icon)
                            .font(.subheadline)
                            .foregroundStyle(CurrentsTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(CurrentsTheme.accent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.title).font(.caption).foregroundStyle(.secondary)
                            Text(h.detail).font(.subheadline.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(h.anglerCode == svc.friendCode ? "You" : h.anglerName)
                                    .font(.caption.bold())
                                AnglerAvatar(image: profiles[h.anglerCode]?.avatar, size: 24)
                            }
                            Text(h.teamName)
                                .font(.caption2.bold())
                                .foregroundStyle(teamColor(teamId(named: h.teamName) ?? h.teamName))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func teamId(named name: String) -> String? {
        standings.first { $0.teamName == name }?.id
    }

    private func winnerBanner(_ winner: String) -> some View {
        VStack(spacing: 6) {
            Text("🏆").font(.system(size: 44))
            Text(winner).font(.title2.bold())
            Text("Tournament winner").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .overlay(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius)
            .strokeBorder(Color.yellow.opacity(0.6), lineWidth: 1.5))
    }

    // MARK: Standings

    @ViewBuilder private var standingsSection: some View {
        if standings.isEmpty {
            if loading {
                FishLoader(message: "Tallying the scores…")
                    .frame(maxWidth: .infinity)
                    .glassCard()
            } else {
                ContentUnavailableView(
                    "No teams yet",
                    systemImage: "trophy",
                    description: Text("Create the first team below — every catch its members log scores points."))
                    .glassCard()
            }
        } else {
            VStack(spacing: 10) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { i, s in
                    teamCard(rank: i + 1, s)
                }
            }
        }
    }

    private func teamCard(rank: Int, _ s: CommunityService.TeamStanding) -> some View {
        let isMyTeam = s.memberCodes.contains(svc.friendCode)
        return VStack(alignment: .leading, spacing: 8) {
            // The card opens the team's tournament summary (points breakdown,
            // angler contributions, catches); the live session is one row in
            // there. The admin assign control sits below, outside the link.
            NavigationLink {
                TeamTournamentDetailView(tournament: tournament, crew: crew,
                                         standing: s, rank: rank, profiles: profiles)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        rankBadge(rank)
                        Text(s.teamName).font(.headline)
                            .foregroundStyle(teamColor(s.id))
                        if isMyTeam {
                            Text("YOUR TEAM")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(CurrentsTheme.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        if s.isEnded {
                            Text("Ended").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(s.points)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(CurrentsTheme.accent)
                        Text("pts").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        statChip("\(s.fishCount) fish")
                        statChip(Units.weight(kg: s.totalWeightKg))
                        statChip("\(s.speciesCount) species")
                        Spacer()
                        facepile(s.memberCodes)
                    }
                    if !s.hostName.isEmpty {
                        HStack(spacing: 5) {
                            AnglerAvatar(image: profiles[s.hostCode]?.avatar, size: 16)
                            Text("Started by \(s.hostCode == svc.friendCode ? "you" : s.hostName) · session & GPS inside")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canAssign && !s.isEnded {
                Menu {
                    if unassignedMembers.isEmpty {
                        Button("Everyone's on a team") {}.disabled(true)
                    } else {
                        ForEach(unassignedMembers, id: \.id) { m in
                            Button(m.id == svc.friendCode ? "You (\(m.name))" : m.name) {
                                assign(m, to: s)
                            }
                        }
                    }
                } label: {
                    Label("Add teammate", systemImage: "person.badge.plus")
                        .font(.caption.bold())
                        .foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay {
            if rank == 1 {
                RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius)
                    .strokeBorder(CurrentsTheme.accent.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    /// Admin: put a crewmate on this team. Their device picks the trip up on
    /// its next membership reconcile (and from the team page itself).
    private func assign(_ m: CommunityService.GroupMember, to team: CommunityService.TeamStanding) {
        Task {
            if await svc.assignMember(code: m.id, name: m.name, toTeam: team.id) {
                Haptics.success()
                ToastCenter.shared.show("\(m.name) added to \(team.teamName)", style: .success)
                await refresh()
            } else {
                ToastCenter.shared.show("Couldn't add \(m.name)", style: .error)
            }
        }
    }

    @ViewBuilder private func rankBadge(_ rank: Int) -> some View {
        switch rank {
        case 1: Text("🥇")
        case 2: Text("🥈")
        case 3: Text("🥉")
        default:
            Text("\(rank)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(CurrentsTheme.accent.opacity(0.10), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func facepile(_ codes: [String]) -> some View {
        HStack(spacing: -8) {
            ForEach(codes.prefix(5), id: \.self) { c in
                AnglerAvatar(image: profiles[c]?.avatar, size: 22)
            }
            if codes.count > 5 {
                Text("+\(codes.count - 5)")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.2), in: Circle())
            }
        }
    }

    // MARK: Join / create a team

    private var joinArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Get on the board", systemImage: "person.badge.plus").font(.headline)
            Text("Tap a team above to join it, or start your own — a team is a live session that scores every catch.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Team name", text: $newTeamName)
                .textFieldStyle(.roundedBorder)
            Button {
                createTeam()
            } label: {
                HStack {
                    if creatingTeam { ProgressView().tint(.white) }
                    Label("Create a team", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
            .disabled(creatingTeam || newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func createTeam() {
        creatingTeam = true
        let teamName = newTeamName.trimmingCharacters(in: .whitespaces)
        Task {
            // A team IS a live session: start (or adopt) a real GPS-tracked
            // trip locally, then share it as the team — so tracking, log-to-
            // trip and the session strip all work exactly like any live trip.
            let trip = appState.tripTracker.activeTrip
                ?? appState.tripTracker.start(name: teamName, spotId: nil)
            let code = await svc.createTeam(named: teamName, tournament: tournament,
                                            localTripId: trip.id)
            creatingTeam = false
            if code != nil {
                Haptics.success()
                ToastCenter.shared.show("Team created — session live, tight lines!", style: .success)
                newTeamName = ""
                await refresh()
            } else {
                ToastCenter.shared.show("Couldn't create the team", style: .error)
            }
        }
    }

    // MARK: Info sheet

    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How points work", systemImage: "trophy.fill")
                        .font(.headline)
                    Text(TournamentPoints.explanation(rates: tournament.rates))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                .padding()
            }
            .navigationTitle("Scoring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingInfo = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - End tournament (admin)

/// Admin end flow: pick a winner (top team preselected), confirm, done.
private struct EndTournamentSheet: View {
    let tournament: CommunityService.Tournament
    let crew: CommunityService.Crew
    let standings: [CommunityService.TeamStanding]
    let onEnded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var selected: String?
    @State private var confirming = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { i, s in
                        Button {
                            Haptics.tap()
                            selected = s.teamName
                        } label: {
                            HStack(spacing: 10) {
                                Text(i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "#\(i + 1)")
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.teamName).font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        Text("\(s.points) pts · \(s.fishCount) fish")
                                        if i == 0 {
                                            Text("Most points")
                                                .font(.system(size: 9, weight: .heavy))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(CurrentsTheme.accent.opacity(0.15), in: Capsule())
                                                .foregroundStyle(CurrentsTheme.accent)
                                        }
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected == s.teamName
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == s.teamName
                                                     ? CurrentsTheme.accent : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected == s.teamName
                                           ? CurrentsTheme.accent.opacity(0.10) : nil)
                    }
                } header: {
                    Text("Declare the winner")
                } footer: {
                    Text("The top team is preselected — the final call is yours.")
                }

                Section {
                    Button(role: .destructive) {
                        confirming = true
                    } label: {
                        HStack {
                            if busy { ProgressView() }
                            Text("Declare \(selected ?? "…") the winner & end")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selected == nil || busy)
                    .confirmationDialog("End the tournament?", isPresented: $confirming,
                                        titleVisibility: .visible) {
                        Button("End tournament", role: .destructive) { end() }
                    } message: {
                        Text("Points stop counting and any team sessions still running are ended for everyone.")
                    }
                }
            }
            .navigationTitle("End Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                if selected == nil { selected = standings.first?.teamName }
            }
        }
    }

    private func end() {
        guard let winner = selected else { return }
        busy = true
        Task {
            let ok = await svc.endTournament(tournament, winnerTeam: winner, crew: crew)
            busy = false
            if ok {
                Haptics.success()
                ToastCenter.shared.show("Tournament ended 🏆", style: .success)
                dismiss()
                onEnded(winner)
            } else {
                ToastCenter.shared.show("Couldn't end the tournament", style: .error)
            }
        }
    }
}

// MARK: - Tournament history

/// Every tournament the crew has run, newest first — its own page, so fifty
/// tournaments never pile up on the crew screen.
struct TournamentHistoryView: View {
    let crew: CommunityService.Crew

    @StateObject private var svc = CommunityService.shared
    @State private var list: [CommunityService.Tournament] = []
    @State private var loading = true

    var body: some View {
        List {
            if list.isEmpty {
                if loading {
                    FishLoader(message: "Loading tournaments…")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "No tournaments yet",
                        systemImage: "trophy",
                        description: Text("When the crew runs a tournament it lands here, results and all."))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(list) { t in
                NavigationLink {
                    TournamentView(tournament: t, crew: crew)
                } label: {
                    row(t)
                }
            }
        }
        .navigationTitle("Tournaments")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            list = await svc.tournaments(crewCode: crew.code)
            loading = false
        }
    }

    private func row(_ t: CommunityService.Tournament) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.isEnded ? "flag.checkered" : "trophy.fill")
                .foregroundStyle(t.isEnded ? Color.secondary : .yellow)
                .frame(width: 34, height: 34)
                .background((t.isEnded ? Color.secondary.opacity(0.12)
                                       : Color.yellow.opacity(0.15)), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(t.name).font(.subheadline.bold())
                    if !t.isEnded {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.red.opacity(0.14), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                if let winner = t.winnerTeam {
                    Text("🏆 \(winner)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(t.createdAt.formatted(date: .abbreviated, time: .omitted)) · hosted by \(t.hostName)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Team summary

/// One team's tournament story: points with their breakdown, each angler's
/// contribution, and every catch — tapping a team lands here, not on the raw
/// join-a-trip screen. The live session itself is one row at the bottom.
struct TeamTournamentDetailView: View {
    let tournament: CommunityService.Tournament
    let crew: CommunityService.Crew
    @State var standing: CommunityService.TeamStanding
    let rank: Int
    let profiles: [String: CommunityService.Profile]

    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    private var isMember: Bool { standing.memberCodes.contains(svc.friendCode) }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                hero
                pointsCard
                membersCard
                catchesCard
                sessionRow
            }
            .padding()
        }
        .navigationTitle(standing.teamName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
            while !Task.isCancelled, !tournament.isEnded, !standing.isEnded {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private func refresh() async {
        if let fresh = await svc.teamStandings(tournament: tournament)
            .first(where: { $0.id == standing.id }) {
            standing = fresh
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "#\(rank)")
                    .font(.title3)
                Text(standing.teamName)
                    .font(.title2.bold())
                    .foregroundStyle(teamColor(standing.id))
                Spacer()
                if standing.isEnded || tournament.isEnded {
                    Text("Ended")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                } else {
                    Text("LIVE")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(standing.points)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CurrentsTheme.accent)
                Text("pts").font(.headline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                heroChip("\(standing.fishCount) fish", icon: "fish.fill")
                heroChip(Units.weight(kg: standing.totalWeightKg), icon: "scalemass")
                heroChip("\(standing.speciesCount) species", icon: "leaf.fill")
            }
            if !standing.hostName.isEmpty {
                HStack(spacing: 5) {
                    AnglerAvatar(image: profiles[standing.hostCode]?.avatar, size: 16)
                    Text("Started by \(standing.hostCode == svc.friendCode ? "you" : standing.hostName)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func heroChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(CurrentsTheme.accent.opacity(0.10), in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: Points breakdown

    private var pointsCard: some View {
        let rates = tournament.rates
        let fishPts = standing.fishCount * rates.perFish
        let speciesPts = standing.speciesCount * rates.newSpeciesBonus
        let weightPts = standing.points - fishPts - speciesPts
        return VStack(alignment: .leading, spacing: 8) {
            Label("Where the points came from", systemImage: "sum").font(.headline)
            breakdownRow("\(standing.fishCount) fish × \(rates.perFish)", fishPts)
            breakdownRow("Weight (+\(rates.perKg)/kg)", weightPts)
            breakdownRow("\(standing.speciesCount) new species × \(rates.newSpeciesBonus)", speciesPts)
            Divider()
            breakdownRow("Total", standing.points, bold: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func breakdownRow(_ label: String, _ pts: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .subheadline.bold() : .subheadline)
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text("\(pts)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(bold ? CurrentsTheme.accent : .primary)
        }
    }

    // MARK: Members

    private var membersCard: some View {
        // Each angler's contribution, biggest haul first. Members who haven't
        // landed anything yet still show, so the roster is complete.
        let byAngler = Dictionary(grouping: standing.catches, by: \.friendCode)
        let rows: [(code: String, name: String, fish: Int, kg: Double)] =
            standing.memberCodes.map { code in
                let cs = byAngler[code] ?? []
                let name = profiles[code]?.name ?? cs.first?.anglerName ?? code
                return (code, name, cs.count, cs.compactMap(\.weightKg).reduce(0, +))
            }
            .sorted { $0.fish > $1.fish }
        return VStack(alignment: .leading, spacing: 10) {
            Label("Anglers", systemImage: "person.2.fill").font(.headline)
            ForEach(rows, id: \.code) { row in
                HStack(spacing: 10) {
                    AnglerAvatar(image: profiles[row.code]?.avatar, size: 32)
                    Text(row.code == svc.friendCode ? "You" : row.name)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(row.fish == 0 ? "No catches yet"
                         : "\(row.fish) fish · \(Units.weight(kg: row.kg))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Catches

    private var catchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Catches", systemImage: "fish.fill").font(.headline)
                Spacer()
                if !standing.catches.isEmpty {
                    Text("\(standing.catches.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if standing.catches.isEmpty {
                Text("Nothing landed yet — first fish scores \(tournament.rates.perFish + tournament.rates.newSpeciesBonus) points.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(standing.catches) { c in
                        HStack(spacing: 10) {
                            Group {
                                if let sp = SpeciesArtLookup.species(named: c.species, appState: appState) {
                                    SpeciesArtworkView(species: sp, caught: true, size: 30)
                                } else {
                                    Image(systemName: "fish.fill")
                                        .foregroundStyle(CurrentsTheme.accent)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(CurrentsTheme.accent.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.species).font(.subheadline.bold())
                                Text("\(c.friendCode == svc.friendCode ? "You" : c.anglerName) · \(c.date.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(c.weightKg.map { Units.weight(kg: $0) } ?? "")
                                .font(.caption.bold())
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                        .padding(.vertical, 6)
                        if c.id != standing.catches.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Session

    private var sessionRow: some View {
        NavigationLink {
            GroupTripView(tripId: svc.tripId(forGroupCode: standing.id),
                          tripName: standing.teamName, initialCode: standing.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(standing.isEnded ? Color.secondary : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMember ? "Open the team session" : "View the live session")
                        .font(.subheadline.bold())
                    Text(isMember ? "Log to the trip, GPS, member standings"
                         : "Watch the feed — or join the team from there")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
