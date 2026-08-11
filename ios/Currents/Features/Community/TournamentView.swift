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
                    Button {
                        create()
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Label("Create tournament", systemImage: "trophy.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
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

    private func create() {
        busy = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Task {
            let t = await svc.createTournament(name: trimmed, crew: crew,
                                               endsAt: hasEnd ? endsAt : nil)
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

    @StateObject private var svc = CommunityService.shared
    @State private var tournament: CommunityService.Tournament
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var profiles: [String: CommunityService.Profile] = [:]
    @State private var loading = true
    @State private var showingInfo = false
    @State private var showingEnd = false
    @State private var newTeamName = ""
    @State private var creatingTeam = false

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
                Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("How points work")
            }
        }
        .sheet(isPresented: $showingInfo) { infoSheet }
        .sheet(isPresented: $showingEnd) {
            EndTournamentSheet(tournament: tournament, crew: crew, standings: standings) { winner in
                tournament.endedAt = .now
                tournament.winnerTeam = winner
                Task { await refresh() }
            }
        }
        .refreshable { await refresh() }
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
        if let fresh = await svc.activeTournament(crewCode: crew.code), fresh.id == tournament.id {
            tournament = fresh
        }
        standings = await svc.teamStandings(tournament: tournament)
        let codes = Array(Set(standings.flatMap(\.memberCodes)))
        if !codes.isEmpty {
            profiles = await svc.profiles(for: codes)
        }
        loading = false
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
        return NavigationLink {
            GroupTripView(tripId: svc.tripId(forGroupCode: s.id),
                          tripName: s.teamName, initialCode: s.id)
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
        .buttonStyle(.plain)
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
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            .disabled(creatingTeam || newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func createTeam() {
        creatingTeam = true
        let teamName = newTeamName.trimmingCharacters(in: .whitespaces)
        Task {
            let code = await svc.createTeam(named: teamName, tournament: tournament,
                                            localTripId: UUID().uuidString)
            creatingTeam = false
            if code != nil {
                Haptics.success()
                ToastCenter.shared.show("Team created — tight lines!", style: .success)
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
                    Text(TournamentPoints.explanation)
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
