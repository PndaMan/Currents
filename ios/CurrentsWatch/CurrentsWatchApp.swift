import SwiftUI
import WatchConnectivity
import ClockKit

@main
struct CurrentsWatchApp: App {
    @StateObject private var connector = WatchConnector()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connector)
                .onAppear { connector.activate() }
        }
    }
}

// MARK: - Connectivity

/// Watch side of the link: mirrors the phone's session/bite state and sends
/// quick actions (start / end / log). Falls back gracefully when the phone is
/// unreachable.
@MainActor
final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isTracking = false
    @Published var sessionName = ""
    @Published var sessionStart: Date?
    @Published var catchCount = 0
    @Published var biteScore = 0
    @Published var reachable = false
    @Published var busy = false
    @Published var lastConfirmation: String?
    @Published var recentSpecies: [String] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() { send(WatchMessage.requestState) }
    func startSession() { send(WatchMessage.startSession, confirm: "Session started") }
    func endSession() { send(WatchMessage.endSession, confirm: "Session ended") }

    /// Log a catch (optionally naming the species). Works with or without an
    /// active session — the phone attaches it to the session if one's running.
    func logCatch(species: String? = nil) {
        var extra: [String: Any] = [:]
        if let species, !species.trimmingCharacters(in: .whitespaces).isEmpty {
            extra[WatchMessage.speciesName] = species
        }
        let confirm = species.map { "Logged \($0)!" } ?? "Catch logged!"
        send(WatchMessage.logCatch, extra: extra, confirm: confirm)
    }

    private func send(_ action: String, extra: [String: Any] = [:], confirm: String? = nil) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            reachable = false
            return
        }
        busy = true
        var msg: [String: Any] = [WatchMessage.action: action]
        msg.merge(extra) { _, new in new }
        WCSession.default.sendMessage(msg, replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.apply(reply)
                self?.busy = false
                if let confirm { self?.lastConfirmation = confirm }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.busy = false; self?.reachable = false }
        })
    }

    private func apply(_ dict: [String: Any]) {
        isTracking = dict[WatchMessage.isTracking] as? Bool ?? isTracking
        sessionName = dict[WatchMessage.sessionName] as? String ?? ""
        if let s = dict[WatchMessage.sessionStart] as? Double { sessionStart = Date(timeIntervalSince1970: s) }
        else { sessionStart = nil }
        catchCount = dict[WatchMessage.catchCount] as? Int ?? catchCount
        biteScore = dict[WatchMessage.biteScore] as? Int ?? biteScore
        if let w = dict[WatchMessage.nextPrimeWindow] as? String { ComplicationStore.nextWindow = w }
        if let recent = dict[WatchMessage.recentSpecies] as? [String] { recentSpecies = recent }
        if let raw = dict[WatchMessage.hourly] as? [[Double]] {
            ComplicationStore.hourly = raw.compactMap { p in
                p.count == 2 ? SnapHour(date: Date(timeIntervalSince1970: p[0]), score: Int(p[1])) : nil
            }
        }
        reachable = true
        // Persist the latest state where the watch-face complications read it,
        // then ask the clock to refresh them.
        ComplicationStore.update(biteScore: biteScore, isTracking: isTracking,
                                 sessionStart: sessionStart, catchCount: catchCount)
        ComplicationStore.reloadComplications()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.reachable = session.isReachable
            self.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.apply(ctx) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if session.isReachable { self.refresh() }
        }
    }
}

// MARK: - UI

struct WatchRootView: View {
    @EnvironmentObject var connector: WatchConnector
    @State private var showingLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                biteCard
                // Log a catch is always available — no need to start a session.
                Button { showingLog = true } label: {
                    Label("Log a Catch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .tint(.blue)
                .disabled(connector.busy)

                if connector.isTracking { activeCard } else { idleCard }
                if let msg = connector.lastConfirmation {
                    Text(msg).font(.footnote).foregroundStyle(.green)
                }
                if !connector.reachable {
                    Label("Open Currents on iPhone", systemImage: "iphone.slash")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Currents")
        .onAppear { connector.refresh() }
        .sheet(isPresented: $showingLog) { WatchLogView() }
    }

    private var biteCard: some View {
        VStack(spacing: 2) {
            Text("\(connector.biteScore)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(connector.biteScore))
            Text("Bite Score").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activeCard: some View {
        VStack(spacing: 8) {
            if let start = connector.sessionStart {
                Text(start, style: .timer)
                    .font(.system(.title3, design: .rounded).bold()).monospacedDigit()
            }
            Text("\(connector.catchCount) caught").font(.caption)
            Button(role: .destructive) { connector.endSession() } label: {
                Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
        }
        .disabled(connector.busy)
    }

    private var idleCard: some View {
        Button { connector.startSession() } label: {
            Label("Start Session", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .tint(.green)
        .disabled(connector.busy)
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 80...: return .green
        case 60..<80: return .teal
        case 40..<60: return .orange
        default: return .gray
        }
    }
}

// MARK: - Log a catch (species by dictation or recents)

/// Logs a catch to the phone with the species you name — tap the mic in the
/// text field to say "largemouth bass", or pick a recent species. No active
/// session required.
struct WatchLogView: View {
    @EnvironmentObject var connector: WatchConnector
    @Environment(\.dismiss) private var dismiss
    @State private var species = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // watchOS shows Dictation / Scribble automatically for this field.
                TextField("Species (tap 🎙 to speak)", text: $species)
                    .textInputAutocapitalization(.words)

                Button {
                    connector.logCatch(species: species)
                    dismiss()
                } label: {
                    Label(species.isEmpty ? "Log Catch" : "Log \(species)", systemImage: "fish.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.blue)
                .disabled(connector.busy)

                if !connector.recentSpecies.isEmpty {
                    Text("Recent").font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(connector.recentSpecies, id: \.self) { name in
                        Button {
                            connector.logCatch(species: name)
                            dismiss()
                        } label: {
                            Text(name).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(connector.busy)
                    }
                }

                Button("Log without species") {
                    connector.logCatch()
                    dismiss()
                }
                .font(.caption)
                .disabled(connector.busy)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Log Catch")
    }
}
