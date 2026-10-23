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

/// Start a crew tournament: a name, how long it runs, how it scores. Teams
/// are live sessions crewmates create or join afterwards.
struct TournamentSetupView: View {
    let crew: CommunityService.Crew
    var onCreated: (CommunityService.Tournament) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    /// Index into `durations`. 0 runs until an admin ends it.
    @State private var durationIndex = 0
    @State private var endsAt = Date().addingTimeInterval(6 * 3600)
    /// The end the stepper last set, so a hand-picked time reads "Custom".
    @State private var presetEnd: Date?
    @State private var busy = false
    @State private var perFish = TournamentPoints.standard.perFish
    @State private var perKg = TournamentPoints.standard.perKg
    @State private var speciesBonus = TournamentPoints.standard.newSpeciesBonus

    /// "Runs for" steps, in hours.
    private static let durations: [Int] = [0, 3, 6, 12, 24, 48, 72, 168]

    private var canCreate: Bool { !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasEnd: Bool { durationIndex > 0 }

    private var rates: TournamentPoints.Rates {
        TournamentPoints.Rates(perFish: perFish, perKg: perKg, newSpeciesBonus: speciesBonus)
    }

    private var isStandard: Bool { rates == TournamentPoints.standard }

    private var durationLabel: String {
        let hours = Self.durations[durationIndex]
        if hours == 0 { return "No end" }
        if endsAt != presetEnd { return "Custom" }
        if hours == 168 { return "1 week" }
        if hours >= 24 { return hours == 24 ? "1 day" : "\(hours / 24) days" }
        return "\(hours) hours"
    }

    var body: some View {
        NavigationStack {
            ScrollView { form }
                .scrollDismissesKeyboard(.interactively)
                .dsScreenBackground()
                .eventSheetTitle("New tournament", close: "Cancel")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            Text("For \(crew.name). Teams are live sessions, and every catch logged during the tournament scores.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            CrewTextField(label: "Tournament name", placeholder: "Winter classic", text: $name)
                .submitLabel(.done)
            lengthField
            scoringField
            startButton
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s6)
        .animation(DS.Motion.softSpring, value: hasEnd)
        .animation(DS.Motion.softSpring, value: isStandard)
        .pageWidth()
    }

    private var lengthField: some View {
        EventFormField("Length") {
            EventFormRow("Runs for", showsDivider: hasEnd) {
                EventStepper(label: "Runs for", value: durationLabel,
                             canDecrement: durationIndex > 0,
                             canIncrement: durationIndex < Self.durations.count - 1,
                             decrement: { setDuration(durationIndex - 1) },
                             increment: { setDuration(durationIndex + 1) })
            }
            if hasEnd {
                EventFormRow("Ends", showsDivider: false) {
                    DatePicker("Ends", selection: $endsAt, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                .transition(.opacity)
            }
        }
    }

    private var scoringField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            EventFormField("Scoring") {
                EventFormRow("Each fish") {
                    EventStepper(label: "Points for each fish", value: pointsText(perFish),
                                 canDecrement: perFish > 0, canIncrement: perFish < 100,
                                 decrement: { perFish -= 1 }, increment: { perFish += 1 })
                }
                EventFormRow("Each kilogram") {
                    EventStepper(label: "Points for each kilogram", value: "+\(perKg)",
                                 canDecrement: perKg > 0, canIncrement: perKg < 50,
                                 decrement: { perKg -= 1 }, increment: { perKg += 1 })
                }
                EventFormRow("New species", showsDivider: false) {
                    EventStepper(label: "Bonus for each new species", value: "+\(speciesBonus)",
                                 canDecrement: speciesBonus > 0, canIncrement: speciesBonus < 100,
                                 decrement: { speciesBonus -= 1 }, increment: { speciesBonus += 1 })
                }
            }
            if !isStandard {
                Button("Use standard scoring", action: resetScoring)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .buttonStyle(.dim)
                    .transition(.opacity)
            }
        }
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Button(action: create) {
                if busy { ProgressView() } else { Text("Start tournament") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(!canCreate)
            Text("Crewmates start or join teams from the tournament page once it's live.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setDuration(_ index: Int) {
        durationIndex = min(max(0, index), Self.durations.count - 1)
        let hours = Self.durations[durationIndex]
        guard hours > 0 else { presetEnd = nil; return }
        let end = Date().addingTimeInterval(TimeInterval(hours) * 3600)
        presetEnd = end
        endsAt = end
    }

    private func resetScoring() {
        perFish = TournamentPoints.standard.perFish
        perKg = TournamentPoints.standard.perKg
        speciesBonus = TournamentPoints.standard.newSpeciesBonus
    }

    private func create() {
        busy = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let rates = self.rates
        Task {
            let t = await svc.createTournament(name: trimmed, crew: crew,
                                               endsAt: hasEnd ? endsAt : nil,
                                               rates: rates)
            busy = false
            if let t {
                ToastCenter.shared.show("Tournament started", style: .success, icon: "trophy.fill")
                dismiss()
                onCreated(t)
            } else {
                ToastCenter.shared.show("Couldn't create the tournament", style: .error)
            }
        }
    }
}

// MARK: - Tournament screen

/// The tournament event page: cover, title, three actions, then the result
/// or time left, your team, the podium and standings, your Live Activity,
/// highlights and rules.
struct TournamentView: View {
    let crew: CommunityService.Crew

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @State private var tournament: CommunityService.Tournament
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var profiles: [String: CommunityService.Profile] = [:]
    @State private var crewMembers: [CommunityService.GroupMember] = []
    /// The best fish landed so far, for the cover and the page tint.
    @State private var coverSpecies: Species?
    @State private var loading = true
    /// The last refresh couldn't reach iCloud, so the page shows what it had.
    @State private var offline = false
    @State private var lastUpdated: Date?
    @State private var showingInfo = false
    @State private var showingEnd = false
    @State private var showingHistory = false
    @State private var showingLog = false
    @State private var showingNewTeam = false
    @State private var shareImage: UIImage?
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var trophyBounce = 0
    /// The result pattern plays once per visit, not on every return to the page.
    @State private var celebratedResult = false

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
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        scrollPage
            .navigationDestination(isPresented: $showingHistory) {
                TournamentHistoryView(crew: crew)
            }
            .sheet(isPresented: $showingShare) { shareSheet }
            .fullScreenCover(isPresented: $showingLog, onDismiss: { Task { await refresh() } }) {
                LogCatchView(groupCodeOverride: myTeam?.id)
            }
            .confirmationDialog("Delete this tournament?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete tournament", role: .destructive, action: deleteTournament)
            } message: {
                Text("The tournament disappears for the whole crew and its history. Team sessions end, but everyone keeps their logged catches.")
            }
            .sheet(isPresented: $showingInfo) {
                TournamentScoringSheet(rates: tournament.rates)
            }
            .sheet(isPresented: $showingNewTeam) {
                NewTeamSheet(hasTeams: !standings.isEmpty, create: createTeam(named:))
            }
            .sheet(isPresented: $showingEnd) { endSheet }
            .task {
                await refresh()
                await pollLoop()
            }
    }

    private var scrollPage: some View {
        ScrollView { content }
            .detailTint(coverSpecies?.artTint)
            .eventPageTitle(tournament.name)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventCover(species: coverSpecies, systemImage: "trophy.fill", tint: DS.accent)
                .padding(.top, DS.Space.s2)
            header
                .padding(.top, DS.Space.s4)
            actions
                .padding(.top, DS.Space.s5)
            if offline {
                offlineNotice
                    .padding(.top, DS.Space.s4)
            }
            resultSection
            countdownSection
            yourTeamSection
            standingsSection
            if canAssign && !standings.isEmpty { assignSection }
            if myTeam != nil && !tournament.isEnded { lockScreenSection }
            highlightsSection
            rulesSection
            if role.canRunTournaments && !tournament.isEnded {
                DangerButton(title: "End tournament", systemImage: "flag.checkered") {
                    showingEnd = true
                }
                .padding(.top, DS.Space.s8)
            }
        }
        .padding(.bottom, DS.Space.s8)
        .pageWidth()
    }

    @ViewBuilder private var shareSheet: some View {
        if let shareImage {
            ImageShareSheet(image: shareImage,
                            filename: "Currents-\(tournament.name)",
                            caption: TournamentShareCard.caption(tournament: tournament,
                                                                 standings: standings))
        }
    }

    private var endSheet: some View {
        EndTournamentSheet(tournament: tournament, crew: crew, standings: standings,
                           images: teamImages) { winner in
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

    private func deleteTournament() {
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

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            if !tournament.isEnded { await refresh() }
        }
    }

    private func refresh() async {
        async let latestTournament = svc.activeTournament(crewCode: crew.code)
        async let members = svc.crewMembers(code: crew.code)
        let latest = await latestTournament
        if let latest, latest.id == tournament.id { tournament = latest }
        let fresh = await svc.teamStandings(tournament: tournament)
        // No teams and no connection both come back empty, and a tournament
        // missing from the crew's list may have been deleted, so ask the
        // server which it is before saying anything.
        var probe = CommunityService.RecordProbe.exists
        if fresh.isEmpty || latest?.id != tournament.id {
            probe = await svc.tournamentExists(code: tournament.id)
        }
        if probe == .missing {
            // Deleted under us (a Mate removed it), so stop polling a ghost.
            TournamentActivityManager.shared.end()
            ToastCenter.shared.show("This tournament was deleted", style: .info)
            dismiss()
            return
        }
        crewMembers = await members
        let unreachable = probe == .unreachable && fresh.isEmpty
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            offline = unreachable
            // Teams slide to their new places on the podium and in the list.
            if !unreachable { standings = fresh }
        }
        if !unreachable {
            lastUpdated = .now
            // Lock Screen scoreboard: starts when you're on a team, updates
            // with every refresh, ends with the tournament.
            TournamentActivityManager.shared.sync(
                tournament: tournament, standings: standings, myCode: svc.friendCode)
        }
        coverSpecies = eventCoverSpecies(standings.flatMap(\.catches), appState: appState)
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

    private func teamPage(_ s: CommunityService.TeamStanding, rank: Int) -> some View {
        TeamTournamentDetailView(tournament: tournament, crew: crew,
                                 standing: s, rank: rank, profiles: profiles)
    }

    /// Wraps a row in a link to the team's page when the team is in the
    /// standings, so every team row opens the same way.
    @ViewBuilder
    private func teamLink<L: View>(_ team: CommunityService.TeamStanding?,
                                   @ViewBuilder label: () -> L) -> some View {
        if let team, let i = standings.firstIndex(where: { $0.id == team.id }) {
            NavigationLink { teamPage(team, rank: i + 1) } label: { label() }
                .buttonStyle(.dim)
        } else {
            label()
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if tournament.isEnded {
            DetailHeader(over: endedLine, title: tournament.name, subtitle: hostLine)
        } else {
            EventHeader(title: tournament.name, subtitle: hostLine) {
                EventLiveTag()
                Text(liveLine)
            }
        }
    }

    private var hostLine: String {
        let host = tournament.hostCode == svc.friendCode ? "you" : tournament.hostName
        return "Hosted by \(host) in \(crew.name)"
    }

    private var endedLine: String {
        "Ended \((tournament.endedAt ?? .now).formatted(date: .abbreviated, time: .omitted))"
    }

    private var liveLine: String {
        guard let ends = tournament.endsAt else {
            return "Started \(eventTimeText(tournament.createdAt))"
        }
        return ends > .now ? "Ends \(eventTimeText(ends))" : "In overtime"
    }

    private var offlineNotice: some View {
        EventNotice(eventOfflineText("Standings", since: lastUpdated), systemImage: "wifi.slash") {
            Button("Try again") { Task { await refresh() } }
        }
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
                Button { showingLog = true } label: { Label("Log catch", systemImage: "plus") }
                    .buttonStyle(ActionTileStyle(.primary))
                shareTile
                moreMenu
            }
        } else {
            ActionTriple {
                // Wait for the first standings load before offering a new
                // team, so members never start a second one over their own.
                Button { showingNewTeam = true } label: { Label("Start a team", systemImage: "plus") }
                    .buttonStyle(ActionTileStyle(.primary))
                    .disabled(loading)
                shareTile
                moreMenu
            }
        }
    }

    private var shareTile: some View {
        Button(action: share) { Label("Share", systemImage: "square.and.arrow.up") }
            .buttonStyle(ActionTileStyle(.tonal))
    }

    private var canEnd: Bool { role.canRunTournaments && !tournament.isEnded }

    private var moreMenu: some View {
        Menu {
            Button { showingInfo = true } label: { Label("How points work", systemImage: "questionmark.circle") }
            if !tournament.isEnded {
                Button { showingHistory = true } label: {
                    Label("All tournaments", systemImage: "clock.arrow.circlepath")
                }
            }
            if canEnd || role.canManage { Divider() }
            if canEnd {
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
        .buttonStyle(.dim)
        .accessibilityLabel("More")
    }

    private func share() {
        shareImage = TournamentShareCard.render(
            tournament: tournament, crewName: crew.name, standings: standings, images: teamImages)
        if shareImage != nil { showingShare = true }
    }

    // MARK: Result

    @ViewBuilder private var resultSection: some View {
        if tournament.isEnded {
            CrewSection(title: "Result") {
                if let winner = tournament.winnerTeam {
                    winnerRow(winner)
                }
                if let i = myIndex, standings[i].teamName != tournament.winnerTeam {
                    finishRow(i)
                }
                if tournament.winnerTeam == nil && myIndex == nil {
                    InlineEmpty(systemImage: "flag.checkered", text: "Ended without a winner.")
                }
            }
        }
    }

    private func winnerRow(_ winner: String) -> some View {
        let team = standings.first { $0.teamName == winner }
        let won = myTeam?.teamName == winner
        return teamLink(team) {
            ArtRow(over: won ? "Your team won" : "Winner",
                   title: winner,
                   subtitle: team.map { "\(pointsText($0.points)) from \($0.fishCount) fish" },
                   chevron: team != nil) {
                ThumbView(tint: .dsScoreFair, size: 56) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(Color.dsScoreFair)
                        .symbolEffect(.bounce, value: trophyBounce)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { trophyBounce += 1 }
        }
        .onChange(of: trophyBounce) {
            guard won, !celebratedResult else { return }
            celebratedResult = true
            Haptics.celebrate(.tournamentResult)
        }
    }

    private func finishRow(_ i: Int) -> some View {
        let me = standings[i]
        return teamLink(me) {
            ArtRow(over: me.teamName,
                   title: "You finished \(eventOrdinal(i + 1)) of \(standings.count)",
                   subtitle: "\(pointsText(me.points)) from \(me.fishCount) fish",
                   chevron: true) {
                placeThumb(i + 1)
            }
        }
    }

    /// "2nd" on the accent, the leading art of your team's row.
    private func placeThumb(_ place: Int) -> some View {
        ThumbView(tint: DS.accent, size: 56) {
            Text(eventOrdinal(place))
                .font(.headline.monospacedDigit())
                .foregroundStyle(DS.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }

    // MARK: Time left and your team

    @ViewBuilder private var countdownSection: some View {
        if !tournament.isEnded, let ends = tournament.endsAt {
            CrewSection(title: "Time left") {
                EventCountdown(label: "Time left", target: ends)
            }
        }
    }

    @ViewBuilder private var yourTeamSection: some View {
        if !tournament.isEnded, let i = myIndex {
            CrewSection(title: "Your team", detail: pointsText(standings[i].points)) {
                yourTeamRow(i)
            }
        }
    }

    private func yourTeamRow(_ i: Int) -> some View {
        let me = standings[i]
        let lines = rankLines(i: i, me: me)
        return teamLink(me) {
            ArtRow(over: me.teamName, title: lines.title, subtitle: lines.detail, chevron: true) {
                placeThumb(i + 1)
            }
        }
    }

    private func rankLines(i: Int, me: CommunityService.TeamStanding) -> (title: String, detail: String) {
        if i == 0 {
            guard standings.count > 1 else { return ("You're leading", "The only team so far") }
            let gap = me.points - standings[1].points
            return ("You're leading", "\(pointsText(gap)) clear of \(standings[1].teamName)")
        }
        let ahead = standings[i - 1]
        let gap = ahead.points - me.points
        let title = gap == 0 ? "Level with \(ahead.teamName)" : "\(pointsText(gap)) behind \(ahead.teamName)"
        let perFish = tournament.rates.perFish
        guard perFish > 0 else { return (title, "Keep fishing") }
        let fishNeeded = max(1, Int((Double(gap + 1) / Double(perFish)).rounded(.up)))
        return (title, fishNeeded == 1 ? "One more fish gets you past" : "\(fishNeeded) more fish get you past")
    }

    // MARK: Standings

    private var standingsSection: some View {
        CrewSection(title: tournament.isEnded ? "Final standings" : "Standings",
                    detail: standings.isEmpty ? nil : "\(standings.count)") {
            if standings.isEmpty {
                standingsEmpty
            } else {
                podium
                rankRows
                if !tournament.isEnded && myTeam == nil {
                    SectionFootnote("Open a team to join it, or start your own.")
                }
            }
        }
    }

    @ViewBuilder private var standingsEmpty: some View {
        if loading {
            EventSkeletonRows(count: 3, thumbSize: 36, label: "Loading the standings")
        } else if offline {
            InlineEmpty(systemImage: "wifi.slash", text: "No standings saved on this phone yet.")
        } else if tournament.isEnded {
            InlineEmpty(systemImage: "trophy", text: "Nobody fished this one.")
        } else {
            InlineEmpty(systemImage: "trophy",
                        text: "No teams yet. Start one and every catch you log scores.",
                        actionTitle: "Start a team") { showingNewTeam = true }
        }
    }

    private var podium: some View {
        EventPodium(entries: standings.prefix(3).map(podiumEntry)) { e in
            if let i = standings.firstIndex(where: { $0.id == e.id }) {
                teamPage(standings[i], rank: i + 1)
            }
        }
    }

    private var rankRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(standings.enumerated()).dropFirst(3), id: \.element.id) { i, s in
                NavigationLink {
                    teamPage(s, rank: i + 1)
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

    // MARK: Start a team

    /// A team IS a live session: start (or adopt) a real GPS-tracked trip
    /// locally, then share it as the team, so tracking, log-to-trip and the
    /// session strip all work like any live trip.
    private func createTeam(named teamName: String) async -> Bool {
        let trip = appState.tripTracker.activeTrip
            ?? appState.tripTracker.start(name: teamName, spotId: nil)
        let code = await svc.createTeam(named: teamName, tournament: tournament,
                                        localTripId: trip.id)
        guard code != nil else {
            ToastCenter.shared.show("Couldn't create the team", style: .error)
            return false
        }
        Haptics.success()
        ToastCenter.shared.show("Team created. Your session is live.", style: .success, haptic: false)
        Task { await refresh() }
        return true
    }

    // MARK: Assign crewmates (admins)

    private var assignSection: some View {
        CrewSection(title: "Assign crewmates") {
            if unassignedMembers.isEmpty {
                InlineEmpty(text: "Everyone's on a team.", systemImage: "person.3")
            } else {
                VStack(spacing: 0) {
                    ForEach(unassignedMembers, id: \.id) { m in assignRow(m) }
                }
                SectionFootnote("Pick a team for each crewmate. Their phone joins it on its own.")
            }
        }
    }

    private func assignRow(_ m: CommunityService.GroupMember) -> some View {
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
                Label("Add to a team", systemImage: "person.badge.plus")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.dim)
        .accessibilityLabel("Add \(m.name) to a team")
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
            CrewSection(title: "On your lock screen") {
                lockScreenPreview(i)
                SectionFootnote("Shows on your lock screen and in the Dynamic Island while you're on a team.")
            }
        }
    }

    private func lockScreenPreview(_ i: Int) -> some View {
        let me = standings[i]
        let rival: CommunityService.TeamStanding? = i == 0
            ? (standings.count > 1 ? standings[1] : nil)
            : standings.first
        return TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: DS.Space.s1) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsText2)
                liveActivityCard(me: me, rank: i + 1, rival: rival, now: ctx.date)
                    .padding(.top, DS.Space.s4)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live Activity preview: your team \(pointsText(me.points)), \(eventOrdinal(i + 1)) of \(standings.count)")
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
            liveActivityScores(me: me, rival: rival)
            HStack {
                Text(rank == 1 ? "Leading" : "\(eventOrdinal(rank)) of \(standings.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
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
        .background(Color.dsElevated, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func liveActivityScores(me: CommunityService.TeamStanding,
                                    rival: CommunityService.TeamStanding?) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your team").font(.footnote).foregroundStyle(Color.dsText2)
                Text("\(me.points)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
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
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        }
    }

    // MARK: Highlights

    @ViewBuilder private var highlightsSection: some View {
        let highlights = CommunityService.tournamentHighlights(from: standings)
        if !highlights.isEmpty {
            CrewSection(title: "Highlights") {
                VStack(spacing: 0) {
                    ForEach(highlights) { h in
                        ArtRow(over: h.title,
                               title: plainDetail(h.detail),
                               subtitle: "\(h.anglerCode == svc.friendCode ? "You" : h.anglerName), \(h.teamName)") {
                            ThumbView(systemImage: h.icon, tint: DS.accent, size: 56)
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
        CrewSection(title: "Rules") {
            KeyValueList(rows: ruleRows)
            if tournament.rates != TournamentPoints.standard {
                SectionFootnote("This tournament uses custom scoring set by its host.")
            }
        }
    }

    private var ruleRows: [KeyValueList.Row] {
        let r = tournament.rates
        var rows: [KeyValueList.Row] = [
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
        rows.append(.init(label: "Teams so far", value: "\(standings.count)"))
        rows.append(.init(label: "Fish landed", value: "\(standings.reduce(0) { $0 + $1.fishCount })"))
        return rows
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

// MARK: - New team

/// Start a team: one name, then the team's live session starts. The same
/// form as the crew sheets.
private struct NewTeamSheet: View {
    let hasTeams: Bool
    let create: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView { form }
                .scrollDismissesKeyboard(.interactively)
                .dsScreenBackground()
                .eventSheetTitle("New team", close: "Cancel")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            Text("Your team is a live session with GPS on. Every catch you log scores for it.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            CrewTextField(label: "Team name", placeholder: "Early risers", text: $name)
                .submitLabel(.go)
                .onSubmit(start)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Button(action: start) {
                    if busy { ProgressView() } else { Text("Start team") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(busy || trimmed.isEmpty)
                Text(hasTeams
                     ? "To join a team that's already fishing, open it from the standings."
                     : "Crewmates join your team from the tournament page.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s6)
        .pageWidth()
    }

    private func start() {
        guard !busy, !trimmed.isEmpty else { return }
        busy = true
        let teamName = trimmed
        Task {
            let ok = await create(teamName)
            busy = false
            if ok { dismiss() }
        }
    }
}

// MARK: - Scoring sheet

/// "How points work", from the tournament's own rates, with a worked example.
private struct TournamentScoringSheet: View {
    let rates: TournamentPoints.Rates

    private var exampleTotal: Int { rates.perFish + 3 * rates.perKg + rates.newSpeciesBonus }

    var body: some View {
        NavigationStack {
            ScrollView { content }
                .dsScreenBackground()
                .eventSheetTitle("How points work")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            rateRow("fish.fill", title: "Every fish landed",
                    subtitle: nil, value: pointsText(rates.perFish))
            rateRow("scalemass.fill", title: "Each kilogram",
                    subtitle: "Rounded, for every fish", value: "+\(rates.perKg)")
            rateRow("star.fill", title: "New species",
                    subtitle: "The team's first of its kind", value: "+\(rates.newSpeciesBonus)")
            CrewSection(title: "A new species at 3 kg") {
                KeyValueList(rows: exampleRows)
                SectionFootnote(rates != TournamentPoints.standard
                                ? "Custom scoring set by the host. An admin confirms the winner at the end."
                                : "Points update as catches come in. An admin confirms the winner at the end.")
            }
        }
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s6)
        .pageWidth()
    }

    private var exampleRows: [KeyValueList.Row] {
        [
            .init(label: "The fish", value: pointsText(rates.perFish)),
            .init(label: "3 kg", value: "+\(3 * rates.perKg)"),
            .init(label: "New species", value: "+\(rates.newSpeciesBonus)"),
            .init(label: "Total", value: pointsText(exampleTotal), emphasized: true),
        ]
    }

    private func rateRow(_ icon: String, title: String, subtitle: String?, value: String) -> some View {
        ArtRow(title: title, subtitle: subtitle) {
            ThumbView(systemImage: icon, tint: DS.accent, size: 44)
        } trailing: {
            Text(value)
        }
    }
}

// MARK: - End tournament (admin)

/// Admin end flow: pick a winner (top team preselected), confirm, done.
private struct EndTournamentSheet: View {
    let tournament: CommunityService.Tournament
    let crew: CommunityService.Crew
    let standings: [CommunityService.TeamStanding]
    let images: (CommunityService.TeamStanding) -> [UIImage?]
    let onEnded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var selected: String?
    @State private var confirming = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView { content }
                .dsScreenBackground()
                .eventSheetTitle("End tournament", close: "Cancel")
                .confirmationDialog("End the tournament?", isPresented: $confirming,
                                    titleVisibility: .visible) {
                    Button("End tournament", role: .destructive) { end() }
                } message: {
                    Text("Points stop counting and any team sessions still running are ended for everyone.")
                }
                .onAppear {
                    if selected == nil { selected = standings.first?.teamName }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Most points wins by default. Pick another team if the crew agreed one.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
            CrewSection(title: "Winner") {
                if standings.isEmpty {
                    InlineEmpty(text: "No team fished this tournament.", systemImage: "trophy")
                }
                ForEach(Array(standings.enumerated()), id: \.element.id) { i, s in
                    teamRow(s, rank: i + 1)
                }
            }
            endButton
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s6)
        }
        .padding(.bottom, DS.Space.s6)
        .pageWidth()
    }

    private var endButton: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Button(role: .destructive) {
                confirming = true
            } label: {
                if busy { ProgressView() } else { Text("Declare winner and end") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(selected == nil || busy)
            Text("Points stop counting and team sessions still running end for everyone.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func teamRow(_ s: CommunityService.TeamStanding, rank: Int) -> some View {
        let isSelected = selected == s.teamName
        return Button {
            selected = s.teamName
        } label: {
            ArtRow(over: "\(eventOrdinal(rank)) place",
                   title: s.teamName,
                   subtitle: rank == 1 ? "\(pointsText(s.points)), most points"
                                       : "\(pointsText(s.points)), \(s.fishCount) fish") {
                EventAvatarStack(images: images(s), size: 44)
            } trailing: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.dsText3))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func end() {
        guard let winner = selected else { return }
        busy = true
        Task {
            let ok = await svc.endTournament(tournament, winnerTeam: winner, crew: crew)
            busy = false
            if ok {
                Haptics.warning()
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
                        EventSkeletonRows(count: 4, thumbSize: 56, label: "Loading tournaments")
                    } else {
                        InlineEmpty(systemImage: "trophy", text: "No tournaments yet. Results land here when the crew runs one.")
                    }
                }
                .dsListRow()
            }
            let live = list.filter { !$0.isEnded }
            let past = list.filter { $0.isEnded }
            if !live.isEmpty {
                SectionTitle("Live", detail: "\(live.count)")
                    .dsListRow()
                rows(live)
            }
            if !past.isEmpty {
                SectionTitle("Past", detail: "\(past.count)")
                    .padding(.top, live.isEmpty ? 0 : DS.Space.s4)
                    .dsListRow()
                rows(past)
            }
        }
        .dsPlainList()
        .detailTint(nil)
        .eventPageTitle("Tournaments")
        .confirmationDialog("Delete this tournament?",
                            isPresented: Binding(get: { tournamentToDelete != nil },
                                                 set: { if !$0 { tournamentToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete tournament", role: .destructive, action: deleteChosen)
        } message: {
            Text("It disappears for the whole crew and its history. Everyone keeps their logged catches.")
        }
        .task {
            list = await svc.tournaments(crewCode: crew.code)
            loading = false
        }
    }

    private func deleteChosen() {
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

    @ViewBuilder
    private func rows(_ items: [CommunityService.Tournament]) -> some View {
        ForEach(items) { t in
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

    private func row(_ t: CommunityService.Tournament) -> some View {
        ArtRow(over: t.createdAt.formatted(date: .abbreviated, time: .omitted),
               title: t.name,
               subtitle: t.winnerTeam.map { "\($0) won" } ?? (t.isEnded ? "Ended" : "Hosted by \(t.hostName)"),
               subtitleIcon: t.winnerTeam != nil ? "trophy.fill" : nil,
               chevron: true) {
            ThumbView(systemImage: t.isEnded ? "flag.checkered" : "trophy.fill",
                      tint: t.isEnded ? Color.gray : DS.accent, size: 56)
        } trailing: {
            if !t.isEnded { EventLiveTag().font(.subheadline) }
        }
    }
}

// MARK: - Team page

/// One team's tournament story, laid out like the tournament: cover, title,
/// three actions, then the points with their breakdown, each angler's
/// contribution and every catch.
struct TeamTournamentDetailView: View {
    let tournament: CommunityService.Tournament
    let crew: CommunityService.Crew
    let profiles: [String: CommunityService.Profile]

    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared
    @State private var standing: CommunityService.TeamStanding
    /// The team's place, kept current by the refresh.
    @State private var place: Int
    /// The team's best fish, for the cover and the page tint.
    @State private var coverSpecies: Species?
    @State private var offline = false
    @State private var showingLog = false
    @State private var showingScoring = false

    init(tournament: CommunityService.Tournament, crew: CommunityService.Crew,
         standing: CommunityService.TeamStanding, rank: Int,
         profiles: [String: CommunityService.Profile]) {
        self.tournament = tournament
        self.crew = crew
        self.profiles = profiles
        _standing = State(initialValue: standing)
        _place = State(initialValue: rank)
    }

    private var isMember: Bool { standing.memberCodes.contains(svc.friendCode) }
    private var ended: Bool { standing.isEnded || tournament.isEnded }

    var body: some View {
        ScrollView { content }
            .detailTint(coverSpecies?.artTint)
            .eventPageTitle(standing.teamName)
            .sheet(isPresented: $showingScoring) {
                TournamentScoringSheet(rates: tournament.rates)
            }
            .fullScreenCover(isPresented: $showingLog, onDismiss: { Task { await refresh() } }) {
                LogCatchView(groupCodeOverride: standing.id)
            }
            .task {
                coverSpecies = eventCoverSpecies(standing.catches, appState: appState)
                await refresh()
                while !Task.isCancelled, !tournament.isEnded, !standing.isEnded {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    guard !Task.isCancelled else { return }
                    await refresh()
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            EventCover(species: coverSpecies, systemImage: "person.2.fill", tint: DS.accent)
                .padding(.top, DS.Space.s2)
            header
                .padding(.top, DS.Space.s4)
            actions
                .padding(.top, DS.Space.s5)
            if offline {
                EventNotice("Offline. Points update when you're back online.", systemImage: "wifi.slash") {
                    Button("Try again") { Task { await refresh() } }
                }
                .padding(.top, DS.Space.s4)
            }
            pointsSection
            anglersSection
            catchesSection
        }
        .padding(.bottom, DS.Space.s8)
        .pageWidth()
    }

    private func refresh() async {
        let all = await svc.teamStandings(tournament: tournament)
        if let i = all.firstIndex(where: { $0.id == standing.id }) {
            withAnimation(DS.Motion.softSpring) {
                standing = all[i]
                place = i + 1
                offline = false
            }
            coverSpecies = eventCoverSpecies(standing.catches, appState: appState)
        } else if all.isEmpty {
            // Empty means no connection (this team exists), unless the
            // session itself is gone.
            let probe = await svc.groupTripExists(code: standing.id)
            withAnimation(DS.Motion.softSpring) { offline = probe == .unreachable }
        }
    }

    private func avatar(_ code: String) -> UIImage? {
        code == svc.friendCode ? (svc.myAvatar ?? profiles[code]?.avatar) : profiles[code]?.avatar
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if ended {
            DetailHeader(over: endedLine, title: standing.teamName, subtitle: summaryLine)
        } else {
            EventHeader(title: standing.teamName, subtitle: summaryLine) {
                EventLiveTag()
                Text("\(eventOrdinal(place)) place")
            }
        }
    }

    private var endedLine: String {
        tournament.isEnded
            ? "Finished \(eventOrdinal(place))"
            : "Session ended, \(eventOrdinal(place)) place"
    }

    private var summaryLine: String {
        "\(pointsText(standing.points)) from \(standing.fishCount) fish in \(tournament.name)"
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if !ended && isMember {
            ActionTriple {
                Button { showingLog = true } label: { Label("Log catch", systemImage: "plus") }
                    .buttonStyle(ActionTileStyle(.primary))
                sessionTile("Session", systemImage: "dot.radiowaves.left.and.right", kind: .tonal)
                scoringTile
            }
        } else if !ended {
            ActionTriple {
                sessionTile("Join team", systemImage: "person.badge.plus", kind: .primary)
                scoringTile
            }
        } else if let trip = myLinkedTrip {
            ActionTriple {
                // Once the team's session is over, the trip page is a dead
                // end for "where did I fish", so the first tile opens YOUR
                // recorded session.
                NavigationLink {
                    SessionDetailView(trip: trip)
                } label: {
                    ActionTileLabel("Your track", systemImage: "map", kind: .primary)
                }
                .buttonStyle(.dim)
                sessionTile("Session", systemImage: "dot.radiowaves.left.and.right", kind: .tonal)
                scoringTile
            }
        } else {
            ActionTriple {
                sessionTile("Session", systemImage: "dot.radiowaves.left.and.right", kind: .primary)
                scoringTile
            }
        }
    }

    /// The team's live session page: the feed, GPS and log-to-trip for
    /// members, the join confirmation for everyone else.
    private func sessionTile(_ title: String, systemImage: String, kind: ActionTileKind) -> some View {
        NavigationLink {
            GroupTripView(tripId: svc.tripId(forGroupCode: standing.id),
                          tripName: standing.teamName, initialCode: standing.id)
        } label: {
            ActionTileLabel(title, systemImage: systemImage, kind: kind)
        }
        .buttonStyle(.dim)
    }

    private var scoringTile: some View {
        Button { showingScoring = true } label: {
            Label("Scoring", systemImage: "questionmark.circle")
        }
        .buttonStyle(ActionTileStyle(.tonal))
    }

    /// My local trip linked to this team's session, for the track link once
    /// the session is over.
    private var myLinkedTrip: Trip? {
        guard isMember, let id = svc.tripId(forGroupCode: standing.id) else { return nil }
        return (try? appState.tripRepository.fetch(id)) ?? nil
    }

    // MARK: Points breakdown

    private var pointsSection: some View {
        CrewSection(title: "Points", detail: pointsText(standing.points)) {
            KeyValueList(rows: pointRows)
        }
    }

    private var pointRows: [KeyValueList.Row] {
        let rates = tournament.rates
        let fishPts = standing.fishCount * rates.perFish
        let speciesPts = standing.speciesCount * rates.newSpeciesBonus
        let weightPts = standing.points - fishPts - speciesPts
        var rows: [KeyValueList.Row] = [
            .init(label: "\(standing.fishCount) fish, \(rates.perFish) each", value: "\(fishPts)"),
            .init(label: "Weight, +\(rates.perKg) a kilogram", value: "\(weightPts)"),
            .init(label: "\(standing.speciesCount) species, +\(rates.newSpeciesBonus) each", value: "\(speciesPts)"),
            .init(label: "Total", value: "\(standing.points)", emphasized: true),
        ]
        if standing.totalWeightKg > 0 {
            rows.insert(.init(label: "Total weight", value: Units.weight(kg: standing.totalWeightKg)), at: 3)
        }
        return rows
    }

    // MARK: Anglers

    private struct AnglerLine {
        let code: String
        let name: String
        let fish: Int
        let kg: Double
    }

    /// Each angler's contribution, biggest haul first. Members who haven't
    /// landed anything yet still show, so the roster is complete.
    private var anglerLines: [AnglerLine] {
        let byAngler = Dictionary(grouping: standing.catches, by: \.friendCode)
        return standing.memberCodes.map { code in
            let cs = byAngler[code] ?? []
            let name = profiles[code]?.name ?? cs.first?.anglerName ?? code
            return AnglerLine(code: code, name: name, fish: cs.count,
                              kg: cs.compactMap(\.weightKg).reduce(0, +))
        }
        .sorted { $0.fish > $1.fish }
    }

    private var anglersSection: some View {
        let lines = anglerLines
        return CrewSection(title: "Anglers", detail: "\(lines.count)") {
            VStack(spacing: 0) {
                ForEach(lines, id: \.code) { line in anglerRow(line) }
            }
        }
    }

    @ViewBuilder private func anglerRow(_ line: AnglerLine) -> some View {
        let isMe = line.code == svc.friendCode
        let row = ArtRow(over: line.code == standing.hostCode ? "Started the session" : nil,
                         title: isMe ? "You" : line.name,
                         subtitle: line.fish == 0 ? "No catches yet"
                             : "\(line.fish) fish, \(Units.weight(kg: line.kg))",
                         chevron: !isMe) {
            AnglerAvatar(image: avatar(line.code), size: 48)
        }
        if isMe {
            row
        } else {
            NavigationLink { FriendProfileView(code: line.code) } label: { row }
                .buttonStyle(.dim)
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
        return CrewSection(title: "Catches", detail: standing.catches.isEmpty ? nil : "\(standing.catches.count)") {
            if standing.catches.isEmpty {
                InlineEmpty(text: firstFishText)
            } else {
                VStack(spacing: 0) {
                    ForEach(standing.catches) { c in catchRow(c, points: points[c.id] ?? 0) }
                }
            }
        }
    }

    private var firstFishText: String {
        let first = tournament.rates.perFish + tournament.rates.newSpeciesBonus
        return "Nothing landed yet. The first fish scores \(pointsText(first))."
    }

    private func catchRow(_ c: CommunityService.GroupCatch, points: Int) -> some View {
        let row = leaderRow(from: c)
        let who = c.friendCode == svc.friendCode ? "You" : c.anglerName
        return NavigationLink {
            CommunityCatchDetailView(row: row)
        } label: {
            ArtRow(over: "\(who), \(c.date.formatted(date: .abbreviated, time: .shortened))",
                   title: sizeTitle(c)) {
                CommunityCatchThumb(row: row, size: 56)
            } trailing: {
                Text("+\(points)")
                    .foregroundStyle(Color.dsScoreGood)
            }
        }
        .buttonStyle(.dim)
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
}
