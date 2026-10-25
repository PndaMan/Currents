import CoreHaptics
import SwiftUI
import UIKit

/// The app's one haptic vocabulary. Every tap, confirmation and celebration
/// goes through here, so each kind of interaction always feels the same and
/// the Haptics setting (Settings > Appearance) silences all of it.
///
/// Meanings follow Apple's Playing haptics guidance:
/// - `press`: the main button of a screen (`.dsPrimary`, a primary action tile).
/// - `softPress`: rows, tiles, thumbnails, tonal and secondary buttons.
/// - `selection`: a value changing: chips, segments, menu pickers, steppers,
///   tab change, a sheet snapping to a detent.
/// - `toggle`: an on/off the app draws itself (favourite, released, follow).
///   System switches, wheels and sliders already play their own.
/// - `success`: saved, logged, sent, joined, copied.
/// - `warning`: a destructive action confirmed (delete, leave, end, discard).
/// - `error`: an action failed.
/// - `celebrate(_:)`: Core Haptics patterns timed to the celebration card.
enum Haptics {
    enum Feedback: Hashable {
        case press, softPress, selection, toggle, success, warning, error
        /// Turns a DS button style's press haptic off (see `buttonHaptic(_:)`).
        case silent
    }

    /// The celebration card's moments, each with its own pattern.
    enum Moment: Hashable {
        case firstCatch, newSpecies, personalBest, achievement, tournamentResult
        /// The weekly streak moment: the flame lights, then the count rolls on.
        case streak
    }

    /// `@AppStorage(Haptics.enabledKey)` in settings; on unless turned off.
    static let enabledKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func play(_ feedback: Feedback) {
        guard feedback != .silent, isEnabled else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { HapticPlayer.shared.play(feedback) }
        } else {
            Task { @MainActor in HapticPlayer.shared.play(feedback) }
        }
    }

    static func celebrate(_ moment: Moment) {
        guard isEnabled else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { HapticPlayer.shared.celebrate(moment) }
        } else {
            Task { @MainActor in HapticPlayer.shared.celebrate(moment) }
        }
    }

    static func press()     { play(.press) }
    static func softPress() { play(.softPress) }
    static func selection() { play(.selection) }
    static func toggle()    { play(.toggle) }
    static func success()   { play(.success) }
    static func warning()   { play(.warning) }
    static func error()     { play(.error) }
    /// Older name for `softPress()`.
    static func tap()       { play(.softPress) }
}

// MARK: - Player

/// Prepared, reused generators plus one Core Haptics engine for celebrations.
@MainActor
private final class HapticPlayer {
    static let shared = HapticPlayer()

    private let pressGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let softGenerator = UIImpactFeedbackGenerator(style: .light)
    private let toggleGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private let supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var engineRunning = false
    private var celebrationPlayer: CHHapticPatternPlayer?

    private var lastFeedback: Haptics.Feedback?
    private var lastTime: CFTimeInterval = 0
    /// Ordinary feedback stays quiet while a celebration pattern plays.
    private var quietUntil: CFTimeInterval = 0
    private var backgroundObserver: NSObjectProtocol?

    private init() {
        pressGenerator.prepare()
        softGenerator.prepare()
        selectionGenerator.prepare()
        // The system stops the engine in the background; stop it first so
        // the next celebration starts a fresh one.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopEngine() }
        }
    }

    func play(_ feedback: Haptics.Feedback) {
        let now = CACurrentMediaTime()
        if now < quietUntil, feedback != .warning, feedback != .error { return }
        // One action, one haptic: the same feedback asked for twice in a
        // moment (a success haptic and a success toast) plays once, and a
        // light tap right after any other haptic (an info toast after its
        // button's press) is already covered.
        if feedback == lastFeedback, now - lastTime < 0.12 { return }
        if feedback == .softPress, now - lastTime < 0.3 { return }
        lastFeedback = feedback
        lastTime = now

        switch feedback {
        case .press:
            pressGenerator.impactOccurred(intensity: 0.75)
            pressGenerator.prepare()
        case .softPress:
            softGenerator.impactOccurred(intensity: 0.6)
            softGenerator.prepare()
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .toggle:
            toggleGenerator.impactOccurred(intensity: 0.8)
            toggleGenerator.prepare()
        case .success:
            notificationGenerator.notificationOccurred(.success)
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
        case .error:
            notificationGenerator.notificationOccurred(.error)
        case .silent:
            break
        }
    }

    func celebrate(_ moment: Haptics.Moment) {
        let spec = CelebrationPattern(moment)
        quietUntil = CACurrentMediaTime() + spec.duration
        guard let engine = startedEngine(),
              let pattern = try? spec.pattern(),
              let player = try? engine.makePlayer(with: pattern) else {
            notificationGenerator.notificationOccurred(.success)
            return
        }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
            celebrationPlayer = player
        } catch {
            notificationGenerator.notificationOccurred(.success)
        }
    }

    // MARK: Engine

    private func startedEngine() -> CHHapticEngine? {
        guard supportsCoreHaptics else { return nil }
        if engine == nil {
            guard let made = try? CHHapticEngine() else { return nil }
            made.playsHapticsOnly = true
            made.isAutoShutdownEnabled = true
            made.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engineRunning = false }
            }
            // The haptic server restarted (media services reset): players
            // are gone, so start again on the next celebration.
            made.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.engineRunning = false
                    self?.celebrationPlayer = nil
                }
            }
            engine = made
        }
        guard let engine else { return nil }
        if !engineRunning {
            do {
                try engine.start()
                engineRunning = true
            } catch {
                return nil
            }
        }
        return engine
    }

    private func stopEngine() {
        celebrationPlayer = nil
        guard engineRunning else { return }
        engine?.stop(completionHandler: nil)
        engineRunning = false
    }
}

// MARK: - Celebration patterns

/// Timed to the celebration card: it springs in over 0.56 s (DS.Motion.spring,
/// overshooting at about 0.22 s) while the confetti launches at 0 and peaks
/// between 0.2 and 0.75 s. Each card moment is under a second and feels
/// distinct. The streak moment is longer, timed to its own motion.
private struct CelebrationPattern {
    /// (time, intensity, sharpness) taps.
    var taps: [(Double, Float, Float)] = []
    /// (time, duration, intensity, sharpness) rumbles that fade out.
    var swells: [(Double, Double, Float, Float)] = []
    var duration: Double

    init(_ moment: Haptics.Moment) {
        switch moment {
        case .firstCatch:
            // A strike, a second hit, then a long swell as the card settles,
            // ending on a crisp tick.
            taps = [(0, 0.75, 0.35), (0.13, 1, 0.45), (0.74, 0.6, 0.9)]
            swells = [(0.18, 0.5, 0.55, 0.2)]
            duration = 0.8
        case .newSpecies:
            // A sharp pop with the card, then sparkles as the confetti peaks.
            taps = [(0, 1, 0.6), (0.26, 0.55, 0.95), (0.36, 0.45, 1),
                    (0.44, 0.38, 0.95), (0.54, 0.3, 1), (0.66, 0.22, 1)]
            swells = [(0, 0.18, 0.4, 0.3)]
            duration = 0.7
        case .personalBest:
            // Rising taps, then one heavy hit on the card's overshoot.
            taps = [(0, 0.35, 0.5), (0.07, 0.5, 0.55), (0.14, 0.65, 0.6), (0.24, 1, 0.25)]
            swells = [(0.24, 0.32, 0.7, 0.1)]
            duration = 0.6
        case .achievement:
            // A medal clink: bright, sharp taps that ring down.
            taps = [(0, 0.9, 1), (0.09, 0.55, 1), (0.17, 0.35, 1), (0.24, 0.2, 1)]
            swells = [(0, 0.3, 0.25, 0.85)]
            duration = 0.35
        case .tournamentResult:
            // Three even beats, then the podium lands.
            taps = [(0, 0.7, 0.5), (0.16, 0.7, 0.5), (0.32, 0.7, 0.5), (0.5, 1, 0.35)]
            swells = [(0.5, 0.4, 0.8, 0.2)]
            duration = 0.9
        case .streak:
            // Timed to StreakMomentView: a soft whoomp as the flame lights
            // (0.3 s), light ticks as the week markers land, then a heavy
            // hit as the number rolls on and this week pops in (1.35 s).
            taps = [(0.3, 0.9, 0.4), (0.8, 0.3, 0.8), (0.92, 0.3, 0.8),
                    (1.04, 0.3, 0.8), (1.35, 1, 0.55)]
            swells = [(0.3, 0.45, 0.6, 0.2), (1.35, 0.35, 0.7, 0.15)]
            duration = 1.7
        }
    }

    func pattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = taps.map { time, intensity, sharpness in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                          ],
                          relativeTime: time)
        }
        var curves: [CHHapticParameterCurve] = []
        for (time, length, intensity, sharpness) in swells {
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [
                                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                                        ],
                                        relativeTime: time,
                                        duration: length))
            // Swell in quickly, then fade to nothing by the end.
            curves.append(CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.4),
                    CHHapticParameterCurve.ControlPoint(relativeTime: length * 0.3, value: 1),
                    CHHapticParameterCurve.ControlPoint(relativeTime: length, value: 0),
                ],
                relativeTime: time))
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }
}

// MARK: - SwiftUI

private struct ButtonHapticKey: EnvironmentKey {
    static let defaultValue: Haptics.Feedback? = nil
}

extension EnvironmentValues {
    /// Overrides the press haptic of the DS button styles below; nil keeps each style's own.
    var buttonHaptic: Haptics.Feedback? {
        get { self[ButtonHapticKey.self] }
        set { self[ButtonHapticKey.self] = newValue }
    }
}

extension View {
    /// `.sensoryFeedback(_:trigger:)` through `Haptics`, so the setting applies.
    /// Only for values the user changes; changes the code makes stay quiet
    /// when they go through a plain assignment instead.
    func haptic<T: Equatable>(_ feedback: Haptics.Feedback, trigger: T) -> some View {
        onChange(of: trigger) { _, _ in Haptics.play(feedback) }
    }

    /// Plays only when `condition(old, new)` is true.
    func haptic<T: Equatable>(_ feedback: Haptics.Feedback, trigger: T,
                              condition: @escaping (T, T) -> Bool) -> some View {
        onChange(of: trigger) { old, new in
            if condition(old, new) { Haptics.play(feedback) }
        }
    }

    /// Sets the press haptic of the DS button styles inside this view, for
    /// example `.selection` on chips or `.silent` where the action plays its own.
    func buttonHaptic(_ feedback: Haptics.Feedback) -> some View {
        environment(\.buttonHaptic, feedback)
    }

    /// Plays a button style's press haptic as the press begins.
    func pressHaptic(_ isPressed: Bool, _ feedback: Haptics.Feedback) -> some View {
        modifier(PressHaptic(isPressed: isPressed, feedback: feedback))
    }
}

extension Binding where Value: Equatable {
    /// Plays `feedback` when a control sets a new value through this binding
    /// (`Picker(selection: $sort.haptic())`). Assignments the code makes to
    /// the state itself stay quiet.
    func haptic(_ feedback: Haptics.Feedback = .selection) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { newValue, transaction in
            if newValue != wrappedValue { Haptics.play(feedback) }
            self.transaction(transaction).wrappedValue = newValue
        })
    }
}

private struct PressHaptic: ViewModifier {
    let isPressed: Bool
    let feedback: Haptics.Feedback
    @Environment(\.buttonHaptic) private var styleOverride

    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, pressed in
            if pressed { Haptics.play(styleOverride ?? feedback) }
        }
    }
}
