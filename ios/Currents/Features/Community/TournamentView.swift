import SwiftUI
import UIKit

/// "12 points", "1 point".
private func pointsText(_ n: Int) -> String { n == 1 ? "1 point" : "\(n) points" }

/// "Ends in 3h 12m", "Ends in 4d 08:09", or "Overtime" once past due.
private func countdownLabel(to end: Date, now: Date) -> String {
    let s = Int(end.timeIntervalSince(now))
    guard s > 0 else { return "Overtime" }
    let d = s / 86400, h = s / 3600 % 24, m = s / 60 % 60
    if d > 0 { return "Ends in \(d)d \(String(format: "%02d:%02d", h, m))" }
    return h > 0 ? "Ends in \(h)h \(m)m" : "Ends in \(m)m"
}

/// The service's highlight details use a middle dot between parts.
private func plainDetail(_ s: String) -> String {
    s.replacingOccurrences(of: " · ", with: ", ") // ui-lint: allow, strips the service's middle dots
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
    @State private var created = 0

    private var canCreate: Bool { !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Winter classic", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Runs inside \(crew.name). Everyone in the crew can see it and start a team.")
                }
                Section {
                    Toggle("Set an end time", isOn: $hasEnd.animation(DS.Motion.softSpring))
                    if hasEnd {
                        DatePicker("Ends", selection: $endsAt, in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    Text("Teams are live sessions. Crewmates start or join one and every catch scores. Without an end time, an admin ends the tournament.")
                }
                Section {
                    Toggle("Custom scoring", isOn: $customScoring.animation(DS.Motion.softSpring))
                    if customScoring {
                        Stepper(value: $perFish, in: 0...100) {
                            scoringRow("Each fish", value: perFish)
                        }
                        Stepper(value: $perKg, in: 0...50) {
                            scoringRow("Each kilogram, rounded", value: perKg)
                        }
                        Stepper(value: $speciesBonus, in: 0...100) {
                            scoringRow("New species bonus", value: speciesBonus)
                        }
                    }
                } header: {
                    Text("Scoring")
                } footer: {
                    Text(customScoring
                         ? "Weight the tournament toward what matters. Set a rate to 0 to ignore it."
                         : "Standard scoring: \(pointsText(TournamentPoints.standard.perFish)) a fish, +\(TournamentPoints.standard.perKg) a kilogram and +\(TournamentPoints.standard.newSpeciesBonus) for each new species.")
                }
            }
            .tint(DS.accent)
            .safeAreaInset(edge: .bottom) {
                Button(action: create) {
                    HStack(spacing: DS.Space.s2) {
                        if busy { ProgressView() }
                        Text("Create tournament")
                    }
                }
                .buttonStyle(.dsPrimary)
                .disabled(!canCreate)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, DS.Space.s3)
                .background(.bar)
            }
            .navigationTitle("New tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sensoryFeedback(.success, trigger: created)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func scoringRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value == 1 ? "1 pt" : "\(value) pts")
                .foregroundStyle(Color.dsText2)
                .monospacedDigit()
                .contentTransition(.numericText())
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
                created += 1
                ToastCenter.shared.show("Tournament started", style: .success, haptic: false, icon: "trophy.fill")
                dismiss()
                onCreated(t)
            } else {
                ToastCenter.shared.show("Couldn't create the tournament", style: .error)
            }
        }
    }
}

// MARK: - Tournament screen

/// The tournament event page: result or countdown, where you stand, actions,
/// the podium and standings, your Live Activity, highlights and rules.
struct TournamentView: View {
    let crew: CommunityService.Crew

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var svc = CommunityService.shared
    @State private var tournament: CommunityService.Tournament
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var profiles: [String: CommunityService.Profile] = [:]
    @State private var crewMembers: [CommunityService.GroupMember] = []
    @State private var loading = true
    @State private var showingInfo = false
    @State private var showingEnd = false
    @State private var showingHistory = false
    @State private var showingLog = false
    @State private var newTeamName = ""
    @State private var creatingTeam = false
    @State private var shareImage: UIImage?
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var trophyBounce = 0
    @Environment(\.dismiss) private var dismiss

    init(tournament: CommunityService.Tournament, crew: CommunityService.Crew) {
        self.crew = crew
        _tournament = State(initialValue: tournament)
    }

    private var myIndex: Int? {
        standings.firstIndex { $0.memberCodes.contains(svc.friendCode) }
    }

    private var myTeam: CommunityService.TeamStanding? {
        myIndex.map { standings[$0] }
    }

    private var role: CrewRole { svc.myRole(in: crew) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                resultBanner
                header
                if !tournament.isEnded, let ends = tournament.endsAt {
                    EventCountdown(label: "Ends in", target: ends)
                        .padding(.top, DS.Space.s6)
                }
                rankCard
                actions
                    .padding(.top, DS.Space.s5)
                standingsSection
                // Wait for the first standings load before offering to create a
                // team, so members never see the join form over their own team.
                if !loading && myTeam == nil && !tournament.isEnded { joinSection }
                if canAssign && !standings.isEmpty { assignSection }
                if myTeam != nil && !tournament.isEnded { lockScreenSection }
                highlightsSection
                rulesSection
                if role.canRunTournaments && !tournament.isEnded {
                    EventDangerButton(title: "End tournament", systemImage: "flag.checkered") {
                        showingEnd = true
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(.dsScoreFair)
        .eventPageTitle(tournament.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingInfo = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("How points work")
            }
        }
        .navigationDestination(isPresented: $showingHistory) {
            TournamentHistoryView(crew: crew)
        }
        .sheet(isPresented: $showingShare) {
            if let shareImage {
                ImageShareSheet(image: shareImage,
                                filename: "Currents-\(tournament.name)",
                                caption: TournamentShareCard.caption(tournament: tournament,
                                                                     standings: standings))
            }
        }
        .fullScreenCover(isPresented: $showingLog, onDismiss: { Task { await refresh() } }) {
            LogCatchView(groupCodeOverride: myTeam?.id)
        }
        .confirmationDialog("Delete this tournament?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete tournament", role: .destructive) {
                Task {
                    if await svc.deleteTournament(tournament, crew: crew) {
                        Haptics.warning()
                        TournamentActivityManager.shared.end()
                        ToastCenter.shared.show("Tournament deleted", style: .info, haptic: false)
                        dismiss()
                    } else {
                        ToastCenter.shared.show("Couldn't delete the tournament", style: .error)
                    }
                }
            }
        } message: {
            Text("The tournament disappears for the whole crew and its history. Team sessions end, but everyone keeps their logged catches.")
        }
        .sheet(isPresented: $showingInfo) {
            TournamentScoringSheet(rates: tournament.rates)
        }
        .sheet(isPresented: $showingEnd) {
            EndTournamentSheet(tournament: tournament, crew: crew, standings: standings) { winner in
                tournament.endedAt = .now
                tournament.winnerTeam = winner
                // Team sessions are ended server-side with the tournament,
                // so close my own local GPS session too if it was one of them.
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
        .sensoryFeedback(.impact(weight: .light), trigger: myIndex)
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
        } else if await svc.tournamentExists(code: tournament.id) == .missing {
            // Deleted under us (a Mate removed it), so stop polling a ghost.
            TournamentActivityManager.shared.end()
            ToastCenter.shared.show("This tournament was deleted", style: .info)
            dismiss()
            return
        }
        crewMembers = await members
        let fresh = await svc.teamStandings(tournament: tournament)
        // Teams slide to their new places on the podium and in the list.
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            standings = fresh
        }
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

    /// Crewmates not yet on any team: the pool an admin can assign from.
    private var unassignedMembers: [CommunityService.GroupMember] {
        crewMembers.filter { m in !standings.contains { $0.memberCodes.contains(m.id) } }
    }

    private var canAssign: Bool {
        role.canRunTournaments && !tournament.isEnded
    }

    private func avatar(_ code: String) -> UIImage? {
        code == svc.friendCode ? (svc.myAvatar ?? profiles[code]?.avatar) : profiles[code]?.avatar
    }

    private func teamImages(_ s: CommunityService.TeamStanding) -> [UIImage?] {
        // Put me first on my own team, so the big face is mine.
        let codes = s.memberCodes.sorted { a, _ in a == svc.friendCode }
        return codes.prefix(2).map { avatar($0) }
    }

    // MARK: Result and header

    @ViewBuilder private var resultBanner: some View {
        if tournament.isEnded, let winner = tournament.winnerTeam {
            let won = myTeam?.teamName == winner
            let winnerPoints = standings.first { $0.teamName == winner }?.points
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dsScoreFair)
                    .frame(width: 52, height: 52)
                    .background(Color.dsScoreFair.opacity(0.22), in: Circle())
                    .symbolEffect(.bounce, value: trophyBounce)
                VStack(alignment: .leading, spacing: 2) {
                    Text(won ? "You won" : "\(winner) won")
                        .font(.headline)
                        .foregroundStyle(Color.dsText)
                    Text(resultDetail(points: winnerPoints))
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                if won {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(Color.dsScoreFair.opacity(0.7), lineWidth: 1.5)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, DS.Space.s5)
            .accessibilityElement(children: .combine)
            .sensoryFeedback(.success, trigger: trophyBounce) { _, _ in won }
            .onAppear {
                guard !reduceMotion else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { trophyBounce += 1 }
            }
        }
    }

    private func resultDetail(points: Int?) -> String {
        let when = (tournament.endedAt ?? .now).formatted(date: .abbreviated, time: .omitted)
        if let points { return "Ended \(when), \(pointsText(points))" }
        return "Ended \(when)"
    }

    private var header: some View {
        EventHeader(title: tournament.name,
                    subtitle: "Hosted by \(tournament.hostCode == svc.friendCode ? "you" : tournament.hostName)") {
            if tournament.isEnded {
                Text("Ended")
            } else {
                EventLiveTag()
            }
            Text(crew.name)
        }
    }

    // MARK: Where you stand

    @ViewBuilder private var rankCard: some View {
        if let i = myIndex {
            let me = standings[i]
            let count = standings.count
            let lines = rankLines(i: i, me: me, count: count)
            let wonBanner = tournament.isEnded && tournament.winnerTeam == me.teamName
            if !wonBanner {
                HStack(spacing: DS.Space.s4) {
                    Text(eventOrdinal(i + 1))
                        .font(.title.bold())
                        .monospacedDigit()
                        .foregroundStyle(i == 0 ? Color.dsScoreFair : Color.dsText)
                        .contentTransition(.numericText())
                        .frame(minWidth: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lines.title)
                            .font(.headline)
                            .foregroundStyle(Color.dsText)
                        Text(lines.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.dsText2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s4)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func rankLines(i: Int, me: CommunityService.TeamStanding, count: Int) -> (title: String, detail: String) {
        if tournament.isEnded {
            return ("You finished \(eventOrdinal(i + 1)) of \(count)",
                    "\(pointsText(me.points)) from \(me.fishCount) fish")
        }
        if i == 0 {
            guard count > 1 else { return ("You're leading", "The only team so far. Keep fishing.") }
            let gap = me.points - standings[1].points
            return ("You're leading", "\(pointsText(gap)) clear of \(standings[1].teamName). Keep fishing.")
        }
        let ahead = standings[i - 1]
        let gap = ahead.points - me.points
        let title = gap == 0 ? "Level with \(ahead.teamName)" : "\(pointsText(gap)) behind \(ahead.teamName)"
        let perFish = tournament.rates.perFish
        guard perFish > 0 else { return (title, "Keep fishing.") }
        let fishNeeded = max(1, Int((Double(gap + 1) / Double(perFish)).rounded(.up)))
        return (title, fishNeeded == 1 ? "One more fish gets you past." : "\(fishNeeded) more fish get you past.")
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if tournament.isEnded {
            ActionTriple {
                Button(action: share) { Label("Share result", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ActionTileStyle(.primary))
                Button { showingHistory = true } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(ActionTileStyle(.tonal))
                moreMenu
            }
        } else if myTeam != nil {
            ActionTriple {
                Button {
                    showingLog = true
                } label: { Label("Log catch", systemImage: "plus") }
                    .buttonStyle(ActionTileStyle(.primary))
                Button(action: share) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ActionTileStyle(.tonal))
                moreMenu
            }
        } else {
            ActionTriple {
                Button(action: share) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ActionTileStyle(.tonal))
                Button { showingInfo = true } label: {
                    Label("Scoring", systemImage: "questionmark.circle")
                }
                .buttonStyle(ActionTileStyle(.tonal))
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { showingInfo = true } label: { Label("How points work", systemImage: "questionmark.circle") }
            Button { showingHistory = true } label: {
                Label("All tournaments", systemImage: "clock.arrow.circlepath")
            }
            if role.canRunTournaments && !tournament.isEnded {
                Divider()
                Button(role: .destructive) { showingEnd = true } label: {
                    Label("End tournament", systemImage: "flag.checkered")
                }
            }
            if role.canManage {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete tournament", systemImage: "trash")
                }
            }
        } label: {
            ActionTileLabel("More", systemImage: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func share() {
        Haptics.tap()
        shareImage = TournamentShareCard.render(
            tournament: tournament, crewName: crew.name, standings: standings)
        if shareImage != nil { showingShare = true }
    }

    // MARK: Standings

    @ViewBuilder private var standingsSection: some View {
        EventSection(tournament.isEnded ? "Final standings" : "Standings",
                     detail: standings.isEmpty ? nil : "\(standings.count)") {
            if standings.isEmpty {
                if loading {
                    ProgressView("Tallying the scores")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s8)
                } else {
                    ContentUnavailableView(
                        "No teams yet",
                        systemImage: "trophy",
                        description: Text("Start the first team below. Every catch its anglers log scores points."))
                }
            } else {
                EventPodium(entries: standings.prefix(3).map(podiumEntry)) { e in
                    if let i = standings.firstIndex(where: { $0.id == e.id }) {
                        TeamTournamentDetailView(tournament: tournament, crew: crew,
                                                 standing: standings[i], rank: i + 1, profiles: profiles)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()).dropFirst(3), id: \.element.id) { i, s in
                        NavigationLink {
                            TeamTournamentDetailView(tournament: tournament, crew: crew,
                                                     standing: s, rank: i + 1, profiles: profiles)
                        } label: {
                            EventRankRow(rank: i + 1,
                                         name: teamLabel(s),
                                         subtitle: teamSubtitle(s),
                                         value: s.points == 1 ? "1 pt" : "\(s.points) pts",
                                         images: teamImages(s),
                                         isMe: s.memberCodes.contains(svc.friendCode))
                        }
                        .buttonStyle(.dim)
                    }
                }
                .padding(.top, DS.Space.s3)
                EventFootnote("Teams are live sessions. Every catch logged during the tournament scores.")
            }
        }
    }

    private func podiumEntry(_ s: CommunityService.TeamStanding) -> EventPodiumEntry {
        EventPodiumEntry(id: s.id, name: s.teamName, value: "\(s.points)", unit: "pts",
                         images: teamImages(s), isMe: s.memberCodes.contains(svc.friendCode))
    }

    private func teamLabel(_ s: CommunityService.TeamStanding) -> String {
        s.memberCodes.contains(svc.friendCode) ? "\(s.teamName) (you)" : s.teamName
    }

    private func teamSubtitle(_ s: CommunityService.TeamStanding) -> String {
        var parts = ["\(s.fishCount) fish"]
        if s.totalWeightKg > 0 { parts.append(Units.weight(kg: s.totalWeightKg)) }
        if s.isEnded { parts.append("session ended") }
        return parts.joined(separator: ", ")
    }

    // MARK: Join or create a team

    private var joinSection: some View {
        EventSection("Get on the board") {
            VStack(spacing: DS.Space.s3) {
                TextField("Team name", text: $newTeamName)
                    .font(.body)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(minHeight: 50)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    .submitLabel(.go)
                    .onSubmit { if canCreateTeam { createTeam() } }
                Button(action: createTeam) {
                    HStack(spacing: DS.Space.s2) {
                        if creatingTeam { ProgressView() }
                        Text("Create a team")
                    }
                }
                .buttonStyle(.dsPrimary)
                .disabled(!canCreateTeam)
            }
            .padding(.horizontal, DS.gutter)
            EventFootnote("Open a team above to join it, or start your own. A team is a live session that scores every catch.")
        }
    }

    private var canCreateTeam: Bool {
        !creatingTeam && !newTeamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createTeam() {
        creatingTeam = true
        let teamName = newTeamName.trimmingCharacters(in: .whitespaces)
        Task {
            // A team IS a live session: start (or adopt) a real GPS-tracked
            // trip locally, then share it as the team, so tracking, log-to-
            // trip and the session strip all work like any live trip.
            let trip = appState.tripTracker.activeTrip
                ?? appState.tripTracker.start(name: teamName, spotId: nil)
            let code = await svc.createTeam(named: teamName, tournament: tournament,
                                            localTripId: trip.id)
            creatingTeam = false
            if code != nil {
                Haptics.success()
                ToastCenter.shared.show("Team created. Your session is live.", style: .success, haptic: false)
                newTeamName = ""
                await refresh()
            } else {
                ToastCenter.shared.show("Couldn't create the team", style: .error)
            }
        }
    }

    // MARK: Assign crewmates (admins)

    private var assignSection: some View {
        EventSection("Assign crewmates") {
            if unassignedMembers.isEmpty {
                EventInlineEmpty(text: "Everyone's on a team.", systemImage: "person.3")
            } else {
                VStack(spacing: 0) {
                    ForEach(unassignedMembers, id: \.id) { m in
                        Menu {
                            Section("Add to team") {
                                ForEach(standings.filter { !$0.isEnded }) { team in
                                    Button(team.teamName) { assign(m, to: team) }
                                }
                            }
                        } label: {
                            ArtRow(title: m.id == svc.friendCode ? "You (\(m.name))" : m.name,
                                   subtitle: "Not on a team") {
                                AnglerAvatar(image: avatar(m.id), size: 44)
                            } trailing: {
                                Label("Add teammate", systemImage: "person.badge.plus")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.dsRow)
                        .accessibilityLabel("Add \(m.name) to a team")
                    }
                }
            }
        }
    }

    /// Admin: put a crewmate on this team. Their device picks the trip up on
    /// its next membership reconcile (and from the team page itself).
    private func assign(_ m: CommunityService.GroupMember, to team: CommunityService.TeamStanding) {
        Task {
            if await svc.assignMember(code: m.id, name: m.name, toTeam: team.id) {
                Haptics.success()
                ToastCenter.shared.show("\(m.name) added to \(team.teamName)", style: .success, haptic: false)
                await refresh()
            } else {
                ToastCenter.shared.show("Couldn't add \(m.name)", style: .error)
            }
        }
    }

    // MARK: Lock screen preview

    @ViewBuilder private var lockScreenSection: some View {
        if let i = myIndex {
            let me = standings[i]
            let rival: CommunityService.TeamStanding? = i == 0
                ? (standings.count > 1 ? standings[1] : nil)
                : standings.first
            EventSection("On your lock screen") {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(spacing: DS.Space.s1) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 56, weight: .bold, design: .rounded)) // ui-lint: allow, lock-screen clock numeral in a fixed-size device preview
                            .foregroundStyle(Color.dsText)
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.dsText2)
                        liveActivityCard(me: me, rank: i + 1, rival: rival, now: ctx.date)
                            .padding(.top, DS.Space.s4)
                    }
                    .padding(DS.Space.s4)
                    .frame(maxWidth: .infinity)
                    .background(Color.dsScoreFair.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card + 8, style: .continuous))
                }
                .padding(.horizontal, DS.gutter)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live Activity preview: your team \(pointsText(me.points)), \(eventOrdinal(i + 1)) of \(standings.count)")
                EventFootnote("While you're on a team, your score, the team to beat and the clock show on the lock screen and in the Dynamic Island.")
            }
        }
    }

    private func liveActivityCard(me: CommunityService.TeamStanding, rank: Int,
                                  rival: CommunityService.TeamStanding?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                Label(tournament.name, systemImage: "trophy.fill")
                    .labelStyle(TrophyLabelStyle())
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let ends = tournament.endsAt {
                    Text(countdownLabel(to: ends, now: now))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Color.dsText2)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your team").font(.footnote).foregroundStyle(Color.dsText2)
                    Text("\(me.points)")
                        .font(.system(.largeTitle, design: .rounded).bold()) // ui-lint: allow, big score numeral
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                if let rival {
                    Text("vs").font(.subheadline).foregroundStyle(Color.dsText2)
                        .padding(.bottom, DS.Space.s3)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(rival.teamName).font(.footnote).foregroundStyle(Color.dsText2).lineLimit(1)
                        Text("\(rival.points)")
                            .font(.system(.largeTitle, design: .rounded).bold()) // ui-lint: allow, big score numeral
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
            HStack {
                Text(rank == 1 ? "Leading" : "\(eventOrdinal(rank)) of \(standings.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsScoreFair)
                Spacer()
                if let bite = SharedStore.load()?.score() {
                    Text("Bite \(bite)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.dsText2)
                }
            }
        }
        .foregroundStyle(Color.dsText)
        .padding(DS.Space.s4)
        .background(Color.dsElevated.opacity(0.92), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: Highlights

    @ViewBuilder private var highlightsSection: some View {
        let highlights = CommunityService.tournamentHighlights(from: standings)
        if !highlights.isEmpty {
            EventSection("Highlights") {
                VStack(spacing: 0) {
                    ForEach(highlights) { h in
                        ArtRow(over: h.title,
                               title: plainDetail(h.detail),
                               subtitle: "\(h.anglerCode == svc.friendCode ? "You" : h.anglerName), \(h.teamName)") {
                            ThumbView(systemImage: h.icon, tint: .dsScoreFair, size: 56)
                        } trailing: {
                            AnglerAvatar(image: avatar(h.anglerCode), size: 32)
                        }
                    }
                }
            }
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        let r = tournament.rates
        var rows: [EventKeyValueList.Row] = [
            .init(label: "Each fish", value: pointsText(r.perFish)),
            .init(label: "Each kilogram", value: "+\(r.perKg)"),
            .init(label: "New species", value: "+\(r.newSpeciesBonus)"),
            .init(label: "Teams", value: "Live sessions, GPS on"),
            .init(label: "Started", value: tournament.createdAt.formatted(date: .abbreviated, time: .shortened)),
        ]
        if let ended = tournament.endedAt {
            rows.append(.init(label: "Ended", value: ended.formatted(date: .abbreviated, time: .shortened)))
        } else if let ends = tournament.endsAt {
            rows.append(.init(label: "Ends", value: ends.formatted(date: .abbreviated, time: .shortened)))
        } else {
            rows.append(.init(label: "Ends", value: "When an admin ends it"))
        }
        rows.append(.init(label: "Hosted by", value: tournament.hostCode == svc.friendCode ? "You" : tournament.hostName))
        rows.append(.init(label: "Teams so far", value: "\(standings.count)"))
        rows.append(.init(label: "Fish landed", value: "\(standings.reduce(0) { $0 + $1.fishCount })"))
        return EventSection("Rules") {
            EventKeyValueList(rows: rows)
            if r != TournamentPoints.standard {
                EventFootnote("This tournament uses custom scoring set by its host.")
            }
        }
    }
}

/// Trophy icon in the score yellow, title in the text colour.
private struct TrophyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.dsScoreFair)
            configuration.title
        }
    }
}

// MARK: - Scoring sheet

/// "How points work", from the tournament's own rates.
private struct TournamentScoringSheet: View {
    let rates: TournamentPoints.Rates
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EventKeyValueList(rows: [
                        .init(label: "Every fish landed", value: pointsText(rates.perFish)),
                        .init(label: "Each kilogram, rounded", value: "+\(rates.perKg)"),
                        .init(label: "A new species for the team", value: "+\(rates.newSpeciesBonus)"),
                    ])
                    EventFootnote("Points update as catches are logged. When the tournament ends, an admin confirms the winner. The top team is highlighted, but the call is theirs.")
                    if rates != TournamentPoints.standard {
                        EventFootnote("This tournament uses custom scoring set by its host.")
                    }
                }
                .padding(.top, DS.Space.s4)
            }
            .dsScreenBackground()
            .navigationTitle("Scoring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                            selected = s.teamName
                        } label: {
                            HStack(spacing: DS.Space.s3) {
                                Text("\(i + 1)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Color.dsText2)
                                    .frame(minWidth: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.teamName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Color.dsText)
                                    Text(i == 0 ? "\(pointsText(s.points)), \(s.fishCount) fish. Most points."
                                                : "\(pointsText(s.points)), \(s.fishCount) fish")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.dsText2)
                                }
                                Spacer()
                                Image(systemName: selected == s.teamName ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected == s.teamName ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.dsText3))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == s.teamName ? .isSelected : [])
                    }
                } header: {
                    Text("Declare the winner")
                } footer: {
                    Text("The top team is preselected. The final call is yours.")
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        if busy { ProgressView() }
                        Text("Declare \(selected ?? "a team") the winner and end")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.dsPrimary)
                .disabled(selected == nil || busy)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, DS.Space.s3)
                .background(.bar)
                .confirmationDialog("End the tournament?", isPresented: $confirming,
                                    titleVisibility: .visible) {
                    Button("End tournament", role: .destructive) { end() }
                } message: {
                    Text("Points stop counting and any team sessions still running are ended for everyone.")
                }
            }
            .navigationTitle("End tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                if selected == nil { selected = standings.first?.teamName }
            }
        }
        .tint(DS.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func end() {
        guard let winner = selected else { return }
        busy = true
        Task {
            let ok = await svc.endTournament(tournament, winnerTeam: winner, crew: crew)
            busy = false
            if ok {
                Haptics.success()
                ToastCenter.shared.show("Tournament ended", style: .success, haptic: false, icon: "flag.checkered")
                dismiss()
                onEnded(winner)
            } else {
                ToastCenter.shared.show("Couldn't end the tournament", style: .error)
            }
        }
    }
}

// MARK: - Tournament history

/// Every tournament the crew has run, newest first, on its own page so fifty
/// tournaments never pile up on the crew screen.
struct TournamentHistoryView: View {
    let crew: CommunityService.Crew

    @StateObject private var svc = CommunityService.shared
    @State private var list: [CommunityService.Tournament] = []
    @State private var loading = true
    @State private var tournamentToDelete: CommunityService.Tournament?

    private var canManage: Bool { svc.myRole(in: crew).canManage }

    var body: some View {
        List {
            DetailHeader(over: crew.name, title: "Tournaments")
                .padding(.bottom, DS.Space.s4)
                .dsListRow()
            if list.isEmpty {
                Group {
                    if loading {
                        ProgressView("Loading tournaments")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s8)
                    } else {
                        ContentUnavailableView(
                            "No tournaments yet",
                            systemImage: "trophy",
                            description: Text("When the crew runs a tournament it lands here, results and all."))
                    }
                }
                .dsListRow()
            }
            ForEach(list) { t in
                ZStack {
                    // Hidden link so the row keeps Luma's own chevron and padding.
                    NavigationLink {
                        TournamentView(tournament: t, crew: crew)
                    } label: { EmptyView() }
                        .opacity(0)
                    row(t)
                }
                .dsListRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canManage {
                        Button(role: .destructive) {
                            tournamentToDelete = t
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .contextMenu {
                    if canManage {
                        Button(role: .destructive) { tournamentToDelete = t } label: {
                            Label("Delete tournament", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .dsPlainList()
        .eventPageTitle("Tournaments")
        .confirmationDialog("Delete this tournament?",
                            isPresented: Binding(get: { tournamentToDelete != nil },
                                                 set: { if !$0 { tournamentToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete tournament", role: .destructive) {
                guard let t = tournamentToDelete else { return }
                tournamentToDelete = nil
                Task {
                    if await svc.deleteTournament(t, crew: crew) {
                        Haptics.warning()
                        withAnimation(DS.Motion.softSpring) { list.removeAll { $0.id == t.id } }
                        ToastCenter.shared.show("Tournament deleted", style: .info, haptic: false)
                    } else {
                        ToastCenter.shared.show("Couldn't delete the tournament", style: .error)
                    }
                }
            }
        } message: {
            Text("It disappears for the whole crew and its history. Everyone keeps their logged catches.")
        }
        .task {
            list = await svc.tournaments(crewCode: crew.code)
            loading = false
        }
    }

    private func row(_ t: CommunityService.Tournament) -> some View {
        ArtRow(over: t.createdAt.formatted(date: .abbreviated, time: .omitted),
               title: t.name,
               subtitle: t.winnerTeam.map { "\($0) won" } ?? (t.isEnded ? "Ended" : "Hosted by \(t.hostName)"),
               subtitleIcon: t.winnerTeam != nil ? "trophy.fill" : nil,
               chevron: true) {
            ThumbView(systemImage: t.isEnded ? "flag.checkered" : "trophy.fill",
                      tint: t.isEnded ? Color.gray : Color.dsScoreFair, size: 56)
        } trailing: {
            if !t.isEnded { EventLiveTag().font(.subheadline) }
        }
    }
}

// MARK: - Team summary

/// One team's tournament story: points with their breakdown, each angler's
/// contribution, and every catch. The live session is one row at the bottom.
struct TeamTournamentDetailView: View {
    let tournament: CommunityService.Tournament
    let crew: CommunityService.Crew
    @State var standing: CommunityService.TeamStanding
    let rank: Int
    let profiles: [String: CommunityService.Profile]

    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    private var isMember: Bool { standing.memberCodes.contains(svc.friendCode) }
    private var ended: Bool { standing.isEnded || tournament.isEnded }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EventAvatarStack(images: standing.memberCodes.prefix(2).map { avatar($0) }, size: 72)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s4)
                EventHeader(title: standing.teamName,
                            subtitle: "\(pointsText(standing.points)) from \(standing.fishCount) fish") {
                    if ended { Text("Ended") } else { EventLiveTag() }
                    Text("\(tournament.name), \(eventOrdinal(rank)) place")
                }
                pointsSection
                anglersSection
                catchesSection
                sessionSection
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(.dsScoreFair)
        .eventPageTitle(standing.teamName)
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
            withAnimation(DS.Motion.softSpring) { standing = fresh }
        }
    }

    private func avatar(_ code: String) -> UIImage? {
        code == svc.friendCode ? (svc.myAvatar ?? profiles[code]?.avatar) : profiles[code]?.avatar
    }

    // MARK: Points breakdown

    private var pointsSection: some View {
        let rates = tournament.rates
        let fishPts = standing.fishCount * rates.perFish
        let speciesPts = standing.speciesCount * rates.newSpeciesBonus
        let weightPts = standing.points - fishPts - speciesPts
        var rows: [EventKeyValueList.Row] = [
            .init(label: "\(standing.fishCount) fish, \(rates.perFish) each", value: "\(fishPts)"),
            .init(label: "Weight, +\(rates.perKg) a kilogram", value: "\(weightPts)"),
            .init(label: "\(standing.speciesCount) species, +\(rates.newSpeciesBonus) each", value: "\(speciesPts)"),
            .init(label: "Total", value: "\(standing.points)", emphasized: true),
        ]
        if standing.totalWeightKg > 0 {
            rows.insert(.init(label: "Total weight", value: Units.weight(kg: standing.totalWeightKg)), at: 3)
        }
        return EventSection("Where the points came from") {
            EventKeyValueList(rows: rows)
        }
    }

    // MARK: Anglers

    private var anglersSection: some View {
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
        return EventSection("Anglers", detail: "\(rows.count)") {
            VStack(spacing: 0) {
                ForEach(rows, id: \.code) { row in
                    let label = ArtRow(over: row.code == standing.hostCode ? "Started the session" : nil,
                                       title: row.code == svc.friendCode ? "You" : row.name,
                                       subtitle: row.fish == 0 ? "No catches yet"
                                           : "\(row.fish) fish, \(Units.weight(kg: row.kg))",
                                       chevron: row.code != svc.friendCode) {
                        AnglerAvatar(image: avatar(row.code), size: 48)
                    }
                    if row.code == svc.friendCode {
                        label
                    } else {
                        NavigationLink { FriendProfileView(code: row.code) } label: { label }
                            .buttonStyle(.dsRow)
                    }
                }
            }
        }
    }

    // MARK: Catches

    /// Points each catch earned, scored oldest first like the service does,
    /// so the first of each species carries its bonus.
    private var catchPoints: [String: Int] {
        let r = tournament.rates
        var seen = Set<String>(), out: [String: Int] = [:]
        for c in standing.catches.sorted(by: { $0.date < $1.date }) {
            var p = r.perFish
            if let w = c.weightKg { p += Int(w.rounded()) * r.perKg }
            if seen.insert(c.species.lowercased()).inserted { p += r.newSpeciesBonus }
            out[c.id] = p
        }
        return out
    }

    private var catchesSection: some View {
        let points = catchPoints
        return EventSection("Catches", detail: standing.catches.isEmpty ? nil : "\(standing.catches.count)") {
            if standing.catches.isEmpty {
                EventInlineEmpty(text: "Nothing landed yet. The first fish scores \(pointsText(tournament.rates.perFish + tournament.rates.newSpeciesBonus)).")
            } else {
                VStack(spacing: 0) {
                    ForEach(standing.catches) { c in
                        let row = leaderRow(from: c)
                        NavigationLink {
                            CommunityCatchDetailView(row: row)
                        } label: {
                            ArtRow(over: "\(c.friendCode == svc.friendCode ? "You" : c.anglerName), \(c.date.formatted(date: .abbreviated, time: .shortened))",
                                   title: sizeTitle(c)) {
                                CommunityCatchThumb(row: row, size: 56)
                            } trailing: {
                                Text("+\(points[c.id] ?? 0)")
                                    .foregroundStyle(Color.dsScoreGood)
                            }
                        }
                        .buttonStyle(.dsRow)
                    }
                }
            }
        }
    }

    private func sizeTitle(_ c: CommunityService.GroupCatch) -> String {
        if let w = c.weightKg { return "\(c.species), \(Units.weight(kg: w))" }
        if let l = c.lengthCm { return "\(c.species), \(Units.length(cm: l))" }
        return c.species
    }

    /// Full catch detail wants a LeaderRow, same conversion the group trip
    /// feed uses.
    private func leaderRow(from c: CommunityService.GroupCatch) -> CommunityService.LeaderRow {
        CommunityService.LeaderRow(
            id: c.id, anglerName: c.anglerName, friendCode: c.friendCode,
            species: c.species, weightKg: c.weightKg, lengthCm: c.lengthCm,
            catchCount: nil, region: "", date: c.date, hasRemotePhoto: true)
    }

    // MARK: Session

    /// My local trip linked to this team's session, for the GPS-session link
    /// once the tournament is over.
    private var myLinkedTrip: Trip? {
        guard isMember, let id = svc.tripId(forGroupCode: standing.id) else { return nil }
        return (try? appState.tripRepository.fetch(id)) ?? nil
    }

    @ViewBuilder private var sessionSection: some View {
        // Once the team's session is over, the trip screen is a dead end for
        // "where did I fish", so link straight to YOUR recorded session.
        if ended, let lt = myLinkedTrip {
            EventSection("Your GPS session") {
                NavigationLink {
                    SessionDetailView(trip: lt)
                } label: {
                    ArtRow(title: "Open your session",
                           subtitle: "Your track, stats and catches from this team",
                           chevron: true) {
                        ThumbView(systemImage: "map", tint: DS.accent, size: 48)
                    }
                }
                .buttonStyle(.dsRow)
            }
        } else {
            EventSection(isMember ? "Your team session" : "Team session") {
                NavigationLink {
                    GroupTripView(tripId: svc.tripId(forGroupCode: standing.id),
                                  tripName: standing.teamName, initialCode: standing.id)
                } label: {
                    ArtRow(over: standing.hostName.isEmpty ? nil
                               : "Started by \(standing.hostCode == svc.friendCode ? "you" : standing.hostName)",
                           title: isMember ? "Open the team session" : "Watch the live session",
                           subtitle: isMember ? "Log to the trip, GPS and standings"
                               : "See the feed, or join the team from there",
                           chevron: true) {
                        ThumbView(systemImage: "dot.radiowaves.left.and.right",
                                  tint: standing.isEnded ? Color.gray : Color.dsScoreGood, size: 48)
                    }
                }
                .buttonStyle(.dsRow)
            }
        }
    }
}
