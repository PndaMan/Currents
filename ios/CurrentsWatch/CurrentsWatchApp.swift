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
    /// Selected app theme raw value (synced from phone) — tints the in-app logo.
    @Published var theme = UserDefaults.standard.string(forKey: "cx_theme") ?? "ocean"

    /// App Store screenshot mode (SCREENSHOT_MODE=1): pose with a lively demo
    /// state and never touch WatchConnectivity, so an unpaired simulator
    /// photographs a working watch app instead of zeros and "open iPhone".
    private static let isScreenshotMode =
        ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"

    override init() {
        super.init()
        if Self.isScreenshotMode {
            biteScore = 84
            isTracking = true
            sessionName = "Dawn Session"
            sessionStart = Date().addingTimeInterval(-47 * 60)
            catchCount = 3
            reachable = true
            recentSpecies = ["Largemouth Bass", "Dusky Kob", "Rainbow Trout"]
        }
    }

    func activate() {
        guard !Self.isScreenshotMode, WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() { send(WatchMessage.requestState) }
    func startSession() { send(WatchMessage.startSession, confirm: "Session started") }
    func endSession() { send(WatchMessage.endSession, confirm: "Session ended") }

    /// Log a catch from whatever was said/typed — the phone parses species,
    /// weight, length and released/kept out of the phrase. Works with or
    /// without an active session.
    func logCatch(species: String? = nil) {
        var extra: [String: Any] = [:]
        var confirm = "Catch logged"
        if let species, !species.trimmingCharacters(in: .whitespaces).isEmpty {
            extra[WatchMessage.speciesName] = species
            let parsed = CatchPhraseParser.parse(species)
            let name = parsed.speciesText.isEmpty ? species : parsed.speciesText.capitalized
            let details = WatchCatchDetails.parts(parsed)
            confirm = details.isEmpty ? "Logged \(name)" : "Logged \(name), \(details.joined(separator: ", "))"
        }
        send(WatchMessage.logCatch, extra: extra, confirm: confirm)
    }

    private func send(_ action: String, extra: [String: Any] = [:], confirm: String? = nil) {
        // Screenshot mode: the posed demo state IS the state — a real send
        // would flip `reachable` off and stamp "open iPhone" on the capture.
        guard !Self.isScreenshotMode else { return }
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
        if let t = dict[WatchMessage.theme] as? String, !t.isEmpty {
            theme = t
            UserDefaults.standard.set(t, forKey: "cx_theme")
        }
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
    @State private var confirmingEnd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchLogoHeader(theme: connector.theme)
                    .padding(.top, 2)
                biteHero
                if connector.isTracking { liveSession }

                // Log a catch is always available — no need to start a session.
                Button { showingLog = true } label: {
                    Label("Log a catch", systemImage: "plus")
                }
                .buttonStyle(WatchPrimaryButtonStyle())
                .disabled(connector.busy)

                if connector.isTracking {
                    Button { confirmingEnd = true } label: {
                        Label("End session", systemImage: "stop.fill")
                    }
                    .buttonStyle(WatchTonalButtonStyle(tint: WatchTheme.scoreSlow))
                    .disabled(connector.busy)
                } else {
                    Button { connector.startSession() } label: {
                        Label("Start session", systemImage: "play.fill")
                    }
                    .buttonStyle(WatchTonalButtonStyle())
                    .disabled(connector.busy)
                }

                if let msg = connector.lastConfirmation {
                    Label {
                        Text(msg)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTheme.scoreGood)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !connector.reachable {
                    Label("Open Currents on iPhone", systemImage: "iphone.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Currents")
        .onAppear { connector.refresh() }
        .sheet(isPresented: $showingLog) { WatchLogView() }
        .confirmationDialog("End this session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { connector.endSession() }
            Button("Keep fishing", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: connector.lastConfirmation)
    }

    // The Today hero: the score ring with its label underneath.
    private var biteHero: some View {
        VStack(spacing: 6) {
            WatchScoreRing(score: connector.biteScore, theme: connector.theme, size: 84)
            Text("Bite score")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var liveSession: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(WatchTheme.scoreSlow).frame(width: 7, height: 7)
                Text(connector.sessionName.isEmpty ? "Live session" : connector.sessionName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            if let start = connector.sessionStart {
                Text(start, style: .timer)
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            Text(connector.catchCount == 1 ? "1 catch" : "\(connector.catchCount) catches")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(connector.catchCount)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The parsed measurements as separate values ("3½ lb", "45 cm", "released"),
/// so the watch never shows a dotted metadata string.
enum WatchCatchDetails {
    static func parts(_ parsed: ParsedCatchPhrase) -> [String] {
        var parts: [String] = []
        if !parsed.weightLabel.isEmpty { parts.append(parsed.weightLabel) }
        if !parsed.lengthLabel.isEmpty { parts.append(parsed.lengthLabel) }
        if let released = parsed.released { parts.append(released ? "Released" : "Kept") }
        return parts
    }
}

// MARK: - Log a catch (species by dictation or recents)

/// Logs a catch to the phone from one dictated phrase — say "three pound
/// largemouth bass released" and the species, weight and release all land on
/// the catch. Or pick a recent species. No active session required.
struct WatchLogView: View {
    @EnvironmentObject var connector: WatchConnector
    @Environment(\.dismiss) private var dismiss
    @State private var species = ""

    private var parsed: ParsedCatchPhrase { CatchPhraseParser.parse(species) }
    private var speciesName: String { parsed.speciesText.isEmpty ? species : parsed.speciesText.capitalized }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // watchOS shows Dictation / Scribble automatically for this field.
                TextField("Species, or speak it", text: $species)
                    .textInputAutocapitalization(.words)

                if species.isEmpty {
                    Text("Try “3 lb bass released”. Weight, length and kept or released are understood.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if parsed.hasDetails {
                    // Live read-back of what the phone will log.
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(parsed.speciesText.isEmpty ? "Catch" : parsed.speciesText.capitalized)
                                .font(.footnote.weight(.semibold))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTheme.scoreGood)
                        }
                        HStack(spacing: 4) {
                            ForEach(WatchCatchDetails.parts(parsed), id: \.self) { part in
                                Text(part)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(WatchTheme.tonal, in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    connector.logCatch(species: species)
                    dismiss()
                } label: {
                    Label(species.isEmpty ? "Log catch" : "Log \(speciesName)", systemImage: "fish.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(WatchPrimaryButtonStyle())
                .disabled(connector.busy)

                if !connector.recentSpecies.isEmpty {
                    Text("Recent")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    ForEach(connector.recentSpecies, id: \.self) { name in
                        Button {
                            connector.logCatch(species: name)
                            dismiss()
                        } label: {
                            Text(name).lineLimit(1)
                        }
                        .buttonStyle(WatchTonalButtonStyle())
                        .disabled(connector.busy)
                    }
                }

                Button("Log without species") {
                    connector.logCatch()
                    dismiss()
                }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .disabled(connector.busy)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Log catch")
    }
}
