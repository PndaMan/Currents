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

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() { send(WatchMessage.requestState) }
    func startSession() { send(WatchMessage.startSession, confirm: "Session started") }
    func endSession() { send(WatchMessage.endSession, confirm: "Session ended") }
    func logCatch() { send(WatchMessage.logCatch, confirm: "Catch logged!") }

    private func send(_ action: String, confirm: String? = nil) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            reachable = false
            return
        }
        busy = true
        WCSession.default.sendMessage([WatchMessage.action: action], replyHandler: { [weak self] reply in
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

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                biteCard
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
            Button { connector.logCatch() } label: {
                Label("Log Catch", systemImage: "fish.fill").frame(maxWidth: .infinity)
            }.tint(.blue)
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
