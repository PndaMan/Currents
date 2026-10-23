import SwiftUI
import UIKit

/// "12 points", "1 point".
private func pointsText(_ n: Int) -> String { n == 1 ? "1 point" : "\(n) points" }

/// The service's highlight details use a middle dot between parts.
private func plainDetail(_ s: String) -> String {
    s.replacingOccurrences(of: " · ", with: ", ") // ui-lint: allow, strips the service's middle dots
}

// MARK: - Tournament setup

/// Start a crew tournament, laid out like Luma's create-event sheet: the
/// cover the page will open with, the name typed at title size, then grouped
/// rows for when it runs, how it scores and who plays. Teams are live
/// sessions crewmates create or join afterwards.
struct TournamentSetupView: View {
    let crew: CommunityService.Crew
    var onCreated: (CommunityService.Tournament) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    /// Hours it runs: 0 runs until an admin ends it, `customHours` is an end
    /// picked by hand.
    @State private var runHours = 0
    @State private var endsAt = Date().addingTimeInterval(6 * 3600)
    /// The end the last preset set, so a hand-picked time reads "Custom".
    @State private var presetEnd: Date?
    @State private var busy = false
    @State private var perFish = TournamentPoints.standard.perFish
    @State private var perKg = TournamentPoints.standard.perKg
    @State private var speciesBonus = TournamentPoints.standard.newSpeciesBonus
    @FocusState private var nameFocused: Bool

    /// "Runs for" presets, in hours.
    private static let durations: [Int] = [3, 6, 12, 24, 48, 72, 168]
    private static let customHours = -1

    private var canCreate: Bool { !busy && !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasEnd: Bool { runHours != 0 }

    private var rates: TournamentPoints.Rates {
        TournamentPoints.Rates(perFish: perFish, perKg: perKg, newSpeciesBonus: speciesBonus)
    }

    private var isStandard: Bool { rates == TournamentPoints.standard }

    var body: some View {
        NavigationStack {
            form
                .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
                .eventSheetTitle("New tournament", close: "Cancel")
                .onChange(of: runHours) { _, hours in applyDuration(hours) }
                .onChange(of: endsAt) { _, end in
                    if runHours > 0, end != presetEnd { runHours = Self.customHours }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleSection
                whenSection
                scoringSection
                teamsSection
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .detailTint(nil)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Cover and name

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            EventCover(species: nil, systemImage: "trophy.fill", tint: .dsScoreFair)
            TextField("Tournament name", text: $name, prompt: Text("Tournament name"))
                .font(.title.bold())
                .foregroundStyle(.dsText)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, DS.gutter)
        }
        .padding(.top, DS.Space.s2)
    }

    // MARK: When

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("When")
                .padding(.top, DS.Space.s6)
            GroupedCard {
                IconRow("Starts", systemImage: "play.fill", tint: .dsScoreGood) {
                    Text("Now").foregroundStyle(.dsText2)
                }
                CardDivider()
                IconRow("Runs for", systemImage: "timer", tint: .orange) { durationPicker }
                if hasEnd {
                    CardDivider()
                    IconRow("Ends", systemImage: "flag.checkered", tint: CrewTint.calendar) {
                        DatePicker("Ends", selection: $endsAt, in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
            }
            SectionFootnote(hasEnd ? "Points stop counting at the end time." : "It runs until an admin ends it.")
        }
    }

    private var durationPicker: some View {
        Picker("Runs for", selection: $runHours) {
            Text("No end").tag(0)
            ForEach(Self.durations, id: \.self) { hours in
                Text(Self.durationText(hours)).tag(hours)
            }
            if runHours == Self.customHours {
                Text("Custom").tag(Self.customHours)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Scoring

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Scoring")
                .padding(.top, DS.Space.s6)
            GroupedCard {
                stepperRow("Each fish", value: pointsText(perFish), systemImage: "fish.fill",
                           tint: CrewTint.fish, binding: $perFish, range: 0...100)
                CardDivider()
                stepperRow("Each kilogram", value: "+\(perKg)", systemImage: "scalemass.fill",
                           tint: CrewTint.weight, binding: $perKg, range: 0...50)
                CardDivider()
                stepperRow("New species", value: "+\(speciesBonus)", systemImage: "leaf.fill",
                           tint: CrewTint.species, binding: $speciesBonus, range: 0...100)
                if !isStandard {
                    CardDivider()
                    Button(action: resetScoring) {
                        IconRow("Use standard scoring", systemImage: "arrow.counterclockwise",
                                tint: CrewTint.people)
                    }
                    .buttonStyle(.dim)
                }
            }
            SectionFootnote("A 3 kg fish new to the team scores \(pointsText(perFish + 3 * perKg + speciesBonus)).")
        }
    }

    private func stepperRow(_ title: String, value: String, systemImage: String, tint: Color,
                            binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        IconRow(title, subtitle: value, systemImage: systemImage, tint: tint) {
            Stepper(title, value: binding, in: range)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Teams

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Teams")
                .padding(.top, DS.Space.s6)
            GroupedCard {
                IconRow("Crew", systemImage: "person.3.fill", tint: CrewTint.people) {
                    Text(crew.name).foregroundStyle(.dsText2).lineLimit(1)
                }
                CardDivider()
                IconRow("Teams", subtitle: "Live sessions with GPS on", systemImage: "location.fill",
                        tint: CrewTint.spot) {
                    Text("Started by crewmates").font(.footnote).foregroundStyle(.dsText2)
                        .multilineTextAlignment(.trailing)
                }
            }
            SectionFootnote("Every catch a team logs scores.")
        }
    }

    // MARK: Create

    private var createBar: some View {
        Button(action: create) {
            if busy {
                ProgressView().tint(Color.dsOnPrimary)
            } else {
                Text("Start tournament")
            }
        }
        .buttonStyle(.dsPrimary)
        .disabled(!canCreate)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .background(Color.dsBackground)
    }

    private static func durationText(_ hours: Int) -> String {
        if hours == 168 { return "1 week" }
        if hours >= 24 { return hours == 24 ? "1 day" : "\(hours / 24) days" }
        return "\(hours) hours"
    }

    private func applyDuration(_ hours: Int) {
        if hours == 0 { presetEnd = nil }
        guard hours > 0 else { return }
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
        nameFocused = false
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

/// The tournament event page, laid out like Luma's event page: cover, title
/// with a ticking status line, three actions, then the result, your team,
/// one ranked list of teams, highlights and rules, with End tournament at
/// the foot for admins.
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
            EventCover(species: coverSpecies, systemImage: "trophy.fill", tint: .dsScoreFair)
                .padding(.top, DS.Space.s2)
            header
                .padding(.top, DS.Space.s4)
            actions
                .padding(.top, DS.Space.s5)
            notices
            statStrip
            resultSection
            yourTeamSection
            standingsSection
            highlightsSection
            if canAssign && !standings.isEmpty { assignSection }
            rulesSection
            footButton
        }
        .padding(.bottom, DS.Space.s8)
        .pageWidth()
    }

    /// Offline, then time's up: at most one line each, under the actions.
    @ViewBuilder private var notices: some View {
        if offline {
            offlineNotice
                .padding(.top, DS.Space.s4)
        }
        if isOvertime {
            overtimeNotice
                .padding(.top, DS.Space.s4)
        }
    }

    /// End tournament while it runs (admins), Delete tournament once it has
    /// ended (managers). Both confirm first.
    @ViewBuilder private var footButton: some View {
        if canEnd {
            DangerButton(title: "End tournament", systemImage: "flag.checkered") {
                showingEnd = true
            }
            .padding(.top, DS.Space.s8)
        } else if tournament.isEnded && role.canManage {
            DangerButton(title: "Delete tournament", systemImage: "trash") {
                confirmingDelete = true
            }
            .padding(.top, DS.Space.s8)
        }
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

    /// Today's hero: the status over the name, who hosts it, and the clock
    /// ring (or the trophy once it has ended) on the right.
    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                statusLabel
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                Text(tournament.name)
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(hostLine)
                    .font(.callout)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            TournamentRing(start: tournament.createdAt, end: tournament.endsAt,
                           ended: tournament.isEnded,
                           fish: standings.reduce(0) { $0 + $1.fishCount })
        }
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder private var statusLabel: some View {
        if tournament.isEnded {
            Text(endedLine)
        } else {
            HStack(spacing: 6) {
                EventLiveTag()
                liveStatus
            }
        }
    }

    /// Teams, fish, the leader's points and your place, as Logbook tiles.
    @ViewBuilder private var statStrip: some View {
        if !standings.isEmpty {
            StatStrip {
                StatTile("Teams", systemImage: "person.3.fill", tint: CrewTint.people,
                         value: "\(standings.count)", width: 120)
                StatTile("Fish", systemImage: "fish.fill", tint: CrewTint.fish,
                         value: "\(standings.reduce(0) { $0 + $1.fishCount })", width: 120)
                StatTile("Top score", systemImage: "trophy.fill", tint: CrewTint.trophy,
                         value: "\(standings.first?.points ?? 0)", unit: "pts", width: 120)
                if let i = myIndex {
                    StatTile("Your place", systemImage: "flag.fill", tint: .orange,
                             value: eventOrdinal(i + 1), footnote: "of \(standings.count)", width: 120)
                }
            }
            .padding(.top, DS.Space.s5)
        }
    }

    /// "Ends in 3d 04:12:09", ticking, or when it started if it has no end.
    private var liveStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(liveLine(now: ctx.date))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
    }

    private var hostLine: String {
        let host = tournament.hostCode == svc.friendCode ? "you" : tournament.hostName
        return "Hosted by \(host) in \(crew.name)"
    }

    private var endedLine: String {
        "Ended \((tournament.endedAt ?? .now).formatted(date: .abbreviated, time: .omitted))"
    }

    private func liveLine(now: Date) -> String {
        guard let ends = tournament.endsAt else {
            return "Started \(eventTimeText(tournament.createdAt, now: now))"
        }
        return ends > now ? "Ends in \(CrewText.clock(to: ends, now: now))" : "In overtime"
    }

    private var offlineNotice: some View {
        EventNotice(eventOfflineText("Standings", since: lastUpdated), systemImage: "wifi.slash") {
            Button("Try again") { Task { await refresh() } }
        }
    }

    /// Past its end time and waiting for an admin. The page refreshes every
    /// 20 seconds, so this shows within one refresh of the end.
    private var isOvertime: Bool {
        guard !tournament.isEnded, let ends = tournament.endsAt else { return false }
        return ends <= .now
    }

    private var overtimeNotice: some View {
        EventNotice(canEnd ? "Time's up. End it to confirm the winner."
                           : "Time's up. An admin confirms the winner.",
                    systemImage: "flag.checkered") {
            if canEnd {
                Button("End now") { showingEnd = true }
            }
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

    // MARK: Your team

    @ViewBuilder private var yourTeamSection: some View {
        if !tournament.isEnded, let i = myIndex {
            CrewSection(title: "Your team", detail: pointsText(standings[i].points)) {
                yourTeamRow(i)
                SectionFootnote("Your score shows on the lock screen and in the Dynamic Island while you're on a team.")
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
                standingRows
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

    /// Every team in one ranked list, the leaderboard's rows: place, faces,
    /// name, points. Teams slide to their new places when the order changes.
    private var standingRows: some View {
        VStack(spacing: 0) {
            if showsPodium { podium }
            ForEach(Array(standings.enumerated()).dropFirst(showsPodium ? 3 : 0), id: \.element.id) { i, s in
                NavigationLink {
                    teamPage(s, rank: i + 1)
                } label: {
                    TeamRankRow(rank: i + 1,
                                name: s.teamName,
                                subtitle: teamSubtitle(s),
                                points: s.points,
                                images: teamImages(s),
                                isMe: s.memberCodes.contains(svc.friendCode))
                }
                .buttonStyle(.dsRow)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: standings.map(\.id))
    }

    /// Three or more teams: the top three stand on the podium, the rest
    /// follow as rows.
    private var showsPodium: Bool { standings.count >= 3 }

    private var podium: some View {
        EventPodium(entries: standings.prefix(3).map { s in
            EventPodiumEntry(id: s.id, name: s.teamName, value: "\(s.points)", unit: "pts",
                             images: teamImages(s), isMe: s.memberCodes.contains(svc.friendCode))
        }) { entry in
            if let i = standings.firstIndex(where: { $0.id == entry.id }) {
                teamPage(standings[i], rank: i + 1)
            }
        }
        .padding(.bottom, DS.Space.s3)
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

    // MARK: Highlights

    @ViewBuilder private var highlightsSection: some View {
        let highlights = CommunityService.tournamentHighlights(from: standings)
        if !highlights.isEmpty {
            CrewSection(title: "Highlights") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(highlights) { h in highlightCard(h) }
                    }
                    .padding(.horizontal, DS.gutter)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    /// One highlight as a Today day card: the moment's symbol on its colour,
    /// what it was, and who landed it.
    private func highlightCard(_ h: CommunityService.TournamentHighlight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ThumbView(systemImage: h.icon, tint: highlightTint(h.icon), size: 44)
                Spacer(minLength: 4)
                AnglerAvatar(image: avatar(h.anglerCode), size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.dsText2)
                Text(plainDetail(h.detail))
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                Text(h.anglerCode == svc.friendCode ? "You, \(h.teamName)" : "\(h.anglerName), \(h.teamName)")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        }
        .frame(width: 168, alignment: .leading)
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func highlightTint(_ icon: String) -> Color {
        switch icon {
        case "fish.fill": return CrewTint.fish
        case "scalemass.fill": return CrewTint.weight
        case "bolt.fill": return .dsScoreFair
        default: return DS.accent
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        CrewSection(title: "Rules") {
            GroupedCard {
                ForEach(Array(ruleRows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { CardDivider() }
                    IconRow(row.label, systemImage: row.symbol, tint: row.tint) {
                        Text(row.value)
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.dsText2)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if tournament.rates != TournamentPoints.standard {
                SectionFootnote("Custom scoring set by the host.")
            }
        }
    }

    private struct RuleRow {
        let label: String
        let symbol: String
        let tint: Color
        let value: String
    }

    private var ruleRows: [RuleRow] {
        let r = tournament.rates
        var rows: [RuleRow] = [
            .init(label: "Each fish", symbol: "fish.fill", tint: CrewTint.fish, value: pointsText(r.perFish)),
            .init(label: "Each kilogram", symbol: "scalemass.fill", tint: CrewTint.weight, value: "+\(r.perKg)"),
            .init(label: "New species", symbol: "leaf.fill", tint: CrewTint.species, value: "+\(r.newSpeciesBonus)"),
            .init(label: "Teams", symbol: "location.fill", tint: CrewTint.spot, value: "Live sessions"),
            .init(label: "Started", symbol: "play.fill", tint: CrewTint.people,
                  value: tournament.createdAt.formatted(date: .abbreviated, time: .shortened)),
        ]
        let endValue: String
        if let ended = tournament.endedAt {
            endValue = ended.formatted(date: .abbreviated, time: .shortened)
        } else if let ends = tournament.endsAt {
            endValue = ends.formatted(date: .abbreviated, time: .shortened)
        } else {
            endValue = "When an admin ends it"
        }
        rows.append(.init(label: tournament.isEnded ? "Ended" : "Ends", symbol: "flag.checkered",
                          tint: CrewTint.calendar, value: endValue))
        return rows
    }
}

/// Today's score ring, for a tournament: how much of its time has gone,
/// with what's left in the middle. Open-ended ones show the fish landed;
/// ended ones a trophy on gold.
private struct TournamentRing: View {
    let start: Date
    let end: Date?
    let ended: Bool
    let fish: Int
    var size: CGFloat = 100

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        Group {
            if ended {
                endedRing
            } else if let end {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ring(progress: progress(end: end, now: ctx.date),
                         value: remaining(end: end, now: ctx.date),
                         caption: end > ctx.date ? "left" : "overtime",
                         colour: end > ctx.date ? DS.accent : .dsScoreLow)
                }
            } else {
                ring(progress: 1, value: "\(fish)", caption: "fish", colour: CrewTint.fish)
            }
        }
        .frame(width: size, height: size)
    }

    private var endedRing: some View {
        ZStack {
            Circle().fill(Color.dsScoreFair.opacity(0.16))
            Circle().strokeBorder(Color.dsScoreFair, lineWidth: size * 0.1)
            Image(systemName: "trophy.fill")
                .font(.system(size: size * 0.36, weight: .semibold)) // ui-lint: allow, symbol scales with the ring like ScoreRing's number
                .foregroundStyle(Color.dsScoreFair)
                .symbolEffect(.bounce, value: bounce)
        }
        .onAppear { if !reduceMotion { bounce += 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ended")
    }

    private func ring(progress: Double, value: String, caption: String, colour: Color) -> some View {
        ZStack {
            Circle().stroke(colour.opacity(0.22), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(colour, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: size * 0.26, weight: .bold)) // ui-lint: allow, number scales with the ring like ScoreRing's
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
            .padding(size * 0.12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }

    private func progress(end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return now.timeIntervalSince(start) / total
    }

    /// The biggest unit left: "3d", "5h", "42m", then seconds.
    private func remaining(end: Date, now: Date) -> String {
        let s = Int(end.timeIntervalSince(now))
        guard s > 0 else { return "0m" }
        if s >= 86_400 { return "\(s / 86_400)d" }
        if s >= 3600 { return "\(s / 3600)h" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }
}

/// One team in the standings, in the leaderboard's row: the place (first,
/// second and third on a gold, silver and bronze disc), the team's faces,
/// name and haul, points on the right. Your team is tinted with the accent.
private struct TeamRankRow: View {
    let rank: Int
    let name: String
    let subtitle: String
    let points: Int
    let images: [UIImage?]
    let isMe: Bool

    @ScaledMetric(relativeTo: .headline) private var rankWidth: CGFloat = 30

    var body: some View {
        ArtRow(title: isMe ? "\(name) (you)" : name, subtitle: subtitle, chevron: true) {
            HStack(spacing: DS.Space.s3) {
                TeamRankMark(rank: rank)
                    .frame(width: rankWidth)
                EventAvatarStack(images: images, size: 48)
            }
        } trailing: {
            Text(points == 1 ? "1 pt" : "\(points) pts")
                .contentTransition(.numericText())
        }
        .background(isMe ? DS.accent.opacity(0.12) : Color.clear)
        .accessibilityLabel("\(eventOrdinal(rank)), \(name), \(pointsText(points)), \(subtitle)")
    }
}

private struct TeamRankMark: View {
    let rank: Int
    @ScaledMetric(relativeTo: .subheadline) private var disc: CGFloat = 28

    var body: some View {
        if let fill = medal {
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .frame(width: disc, height: disc)
                .background(fill, in: Circle())
        } else {
            Text("\(rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
    }

    private var medal: Color? {
        switch rank {
        case 1: return Color.dsScoreFair.opacity(0.32)
        case 2: return Color.dsFill2
        case 3: return Color.dsScoreLow.opacity(0.28)
        default: return nil
        }
    }
}

// MARK: - New team

/// Start a team: the name at title size, as on the start screen, then the
/// team's live session starts from the button at the foot.
private struct NewTeamSheet: View {
    let hasTeams: Bool
    let create: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            form
                .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
                .eventSheetTitle("New team", close: "Cancel")
                .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Team name", text: $name, prompt: Text("Team name"))
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .focused($nameFocused)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                GroupedCard {
                    IconRow("Session", subtitle: "Starts now, GPS on", systemImage: "location.fill",
                            tint: CrewTint.spot)
                    CardDivider()
                    IconRow("Scores", subtitle: "Every catch you log", systemImage: "fish.fill",
                            tint: CrewTint.fish)
                }
                .padding(.top, DS.Space.s5)
                SectionFootnote(hasTeams ? "To join a team already fishing, open it from the standings."
                                         : "Crewmates join your team from the tournament page.")
            }
            .pageWidth()
        }
        .detailTint(nil)
        .scrollDismissesKeyboard(.interactively)
    }

    private var startBar: some View {
        Button(action: start) {
            if busy {
                ProgressView().tint(Color.dsOnPrimary)
            } else {
                Text("Start team")
            }
        }
        .buttonStyle(.dsPrimary)
        .disabled(busy || trimmed.isEmpty)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .background(Color.dsBackground)
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

/// "How points work", from the tournament's own rates, with a worked
/// example. Grouped rows, like the start screen that set them.
private struct TournamentScoringSheet: View {
    let rates: TournamentPoints.Rates

    private var exampleTotal: Int { rates.perFish + 3 * rates.perKg + rates.newSpeciesBonus }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommunityHero(label: "A new species at 3 kg", title: pointsText(exampleTotal),
                                  line: rates != TournamentPoints.standard ? "Custom scoring set by the host"
                                                                           : "Standard scoring") {
                        ThumbView(systemImage: "trophy.fill", tint: CrewTint.trophy, size: 72)
                    }
                    .padding(.top, DS.Space.s2)
                    ratesSection
                    exampleSection
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .detailTint(nil)
            .eventSheetTitle("How points work")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Points")
                .padding(.top, DS.Space.s6)
            HStack(spacing: 10) {
                StatTile("Each fish", systemImage: "fish.fill", tint: CrewTint.fish,
                         value: "\(rates.perFish)", unit: "pts", width: nil)
                StatTile("Per kg", systemImage: "scalemass.fill", tint: CrewTint.weight,
                         value: "+\(rates.perKg)", width: nil)
                StatTile("Species", systemImage: "leaf.fill", tint: CrewTint.species,
                         value: "+\(rates.newSpeciesBonus)", width: nil)
            }
            .padding(.horizontal, DS.gutter)
            SectionFootnote("Weight rounds to the nearest kilogram. The species bonus is the team's first of its kind.")
        }
    }

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Worked example")
                .padding(.top, DS.Space.s6)
            KeyValueList(rows: [
                .init(label: "The fish", value: pointsText(rates.perFish)),
                .init(label: "3 kg", value: "+\(3 * rates.perKg)"),
                .init(label: "New species", value: "+\(rates.newSpeciesBonus)"),
                .init(label: "Total", value: pointsText(exampleTotal), emphasized: true),
            ])
            SectionFootnote("An admin confirms the winner at the end.")
        }
    }
}

// MARK: - End tournament (admin)

/// Admin end flow: pick a winner from a checkmark list (top team
/// preselected), then the red button at the foot, confirmed.
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

    private var canEnd: Bool { selected != nil && !busy }

    var body: some View {
        NavigationStack {
            list
                .safeAreaInset(edge: .bottom, spacing: 0) { endBar }
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

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CommunityHero(label: "Winner", title: selected ?? "No winner",
                              line: "Most points wins unless the crew agreed another") {
                    ThumbView(systemImage: "trophy.fill", tint: CrewTint.trophy, size: 72)
                }
                .padding(.top, DS.Space.s2)
                SectionTitle("Teams", detail: standings.isEmpty ? nil : "\(standings.count)")
                    .padding(.top, DS.Space.s6)
                if standings.isEmpty {
                    InlineEmpty(systemImage: "trophy", text: "No team fished this tournament.")
                } else {
                    GroupedCard {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { CardDivider(inset: DS.Space.s4 + 40 + DS.Space.s3) }
                            teamRow(s, rank: i + 1)
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .detailTint(nil)
    }

    private var endBar: some View {
        DangerButton(title: busy ? "Ending" : "End tournament", systemImage: "flag.checkered") {
            confirming = true
        }
        .disabled(!canEnd)
        .opacity(canEnd ? 1 : 0.4)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .background(Color.dsBackground)
    }

    private func teamRow(_ s: CommunityService.TeamStanding, rank: Int) -> some View {
        let isSelected = selected == s.teamName
        return Button {
            selected = s.teamName
        } label: {
            HStack(spacing: DS.Space.s3) {
                EventAvatarStack(images: images(s), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.teamName)
                        .foregroundStyle(.dsText)
                    Text("\(eventOrdinal(rank)), \(pointsText(s.points)) from \(s.fishCount) fish")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.dsText3))
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
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
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        list = await svc.tournaments(crewCode: crew.code)
        loading = false
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
                      tint: t.isEnded ? Color.gray : Color.dsScoreFair, size: 56)
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

    /// Today's hero: status over the team name, the haul, and the place on
    /// a medal-coloured ring.
    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                statusLabel
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                Text(standing.teamName)
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(summaryLine)
                    .font(.callout)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            PlaceRing(place: place)
        }
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder private var statusLabel: some View {
        if ended {
            Text(endedLine)
        } else {
            HStack(spacing: 6) {
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
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                pointTiles
                KeyValueList(rows: pointRows)
            }
        }
    }

    /// Where the points came from, as Today's stat tiles.
    private var pointTiles: some View {
        let rates = tournament.rates
        let fishPts = standing.fishCount * rates.perFish
        let speciesPts = standing.speciesCount * rates.newSpeciesBonus
        let weightPts = standing.points - fishPts - speciesPts
        let weighed = standing.totalWeightKg > 0 ? Units.weight(kg: standing.totalWeightKg) : "Not weighed"
        return StatStrip {
            StatTile("Fish", systemImage: "fish.fill", tint: CrewTint.fish,
                     value: "\(fishPts)", unit: "pts", footnote: "\(standing.fishCount) caught", width: 132)
            StatTile("Weight", systemImage: "scalemass.fill", tint: CrewTint.weight,
                     value: "\(weightPts)", unit: "pts", footnote: weighed, width: 132)
            StatTile("Species", systemImage: "leaf.fill", tint: CrewTint.species,
                     value: "\(speciesPts)", unit: "pts", footnote: "\(standing.speciesCount) kinds", width: 132)
        }
    }

    private var pointRows: [KeyValueList.Row] {
        let rates = tournament.rates
        let fishPts = standing.fishCount * rates.perFish
        let speciesPts = standing.speciesCount * rates.newSpeciesBonus
        let weightPts = standing.points - fishPts - speciesPts
        return [
            .init(label: "\(standing.fishCount) fish, \(rates.perFish) each", value: "\(fishPts)"),
            .init(label: "Weight, +\(rates.perKg) a kilogram", value: "\(weightPts)"),
            .init(label: "\(standing.speciesCount) species, +\(rates.newSpeciesBonus) each", value: "\(speciesPts)"),
            .init(label: "Total", value: "\(standing.points)", emphasized: true),
        ]
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

/// A team's place as a ring in its medal colour (gold, silver, bronze, then
/// the accent) with the ordinal inside, like Today's score ring.
private struct PlaceRing: View {
    let place: Int
    var size: CGFloat = 100

    private var colour: Color {
        place <= 3 ? EventPodiumColumn.medal(place) : DS.accent
    }

    var body: some View {
        ZStack {
            Circle().fill(colour.opacity(0.14))
            Circle().strokeBorder(colour, lineWidth: size * 0.09)
            VStack(spacing: 0) {
                Text(eventOrdinal(place))
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("place")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(eventOrdinal(place)) place")
    }
}
