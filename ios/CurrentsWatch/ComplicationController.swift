import ClockKit
import SwiftUI

// MARK: - Shared complication state

/// The latest phone-synced values, persisted in the watch app's own storage so
/// the watch-face complications can render them (they run in the same process
/// as `WatchConnector`, so no App Group is needed).
enum ComplicationStore {
    private static let d = UserDefaults.standard

    static var biteScore: Int { d.integer(forKey: "cx_bite") }
    static var isTracking: Bool { d.bool(forKey: "cx_tracking") }
    static var catchCount: Int { d.integer(forKey: "cx_catches") }
    static var sessionStart: Date? {
        let t = d.double(forKey: "cx_start"); return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static var nextWindow: String {
        get { d.string(forKey: "cx_window") ?? "" }
        set { d.set(newValue, forKey: "cx_window") }
    }

    /// Upcoming hourly bite scores so the face ticks through the day on its own.
    static var hourly: [SnapHour] {
        get {
            guard let data = d.data(forKey: "cx_hourly") else { return [] }
            return (try? JSONDecoder().decode([SnapHour].self, from: data)) ?? []
        }
        set {
            d.set(try? JSONEncoder().encode(newValue), forKey: "cx_hourly")
            reloadComplications()
        }
    }

    /// Bite score for a given time from the hourly list, falling back to the
    /// last pushed value.
    static func score(at date: Date) -> Int {
        hourly.last(where: { $0.date <= date })?.score ?? hourly.first?.score ?? biteScore
    }

    static func update(biteScore: Int, isTracking: Bool, sessionStart: Date?, catchCount: Int) {
        d.set(biteScore, forKey: "cx_bite")
        d.set(isTracking, forKey: "cx_tracking")
        d.set(catchCount, forKey: "cx_catches")
        d.set(sessionStart?.timeIntervalSince1970 ?? 0, forKey: "cx_start")
    }

    /// Ask watchOS to redraw every complication the user has placed.
    static func reloadComplications() {
        let server = CLKComplicationServer.sharedInstance()
        (server.activeComplications ?? []).forEach { server.reloadTimeline(for: $0) }
    }

    static func color(forScore s: Int) -> UIColor {
        // The app's score ramp (WatchTheme / DS.scoreColor), with the top band
        // in the theme colour synced from the phone.
        let theme = d.string(forKey: "cx_theme") ?? "ocean"
        return UIColor(WatchTheme.scoreColor(s, theme: theme))
    }
}

// MARK: - Data source

/// Watch-face complications for Currents' notable features: the live bite
/// score (as a gauge), the running session (timer + catch count), and a
/// one-tap "log a catch" launcher. Registered via the `CLKComplicationPrincipalClass`
/// key in Info.plist.
final class ComplicationController: NSObject, CLKComplicationDataSource {

    private let families: [CLKComplicationFamily] = [
        .modularSmall, .modularLarge, .utilitarianSmall, .utilitarianSmallFlat,
        .utilitarianLarge, .circularSmall, .extraLarge, .graphicCorner,
        .graphicBezel, .graphicCircular, .graphicRectangular, .graphicExtraLarge,
    ]

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        handler([
            CLKComplicationDescriptor(identifier: "bite", displayName: "Bite score", supportedFamilies: families),
            CLKComplicationDescriptor(identifier: "session", displayName: "Fishing session", supportedFamilies: families),
            CLKComplicationDescriptor(identifier: "window", displayName: "Next trip", supportedFamilies: families),
            CLKComplicationDescriptor(identifier: "log", displayName: "Log a catch", supportedFamilies: families),
        ])
    }

    func getCurrentTimelineEntry(for complication: CLKComplication,
                                 withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        if let t = template(for: complication.identifier, family: complication.family, date: Date(), sample: false) {
            handler(CLKComplicationTimelineEntry(date: Date(), complicationTemplate: t))
        } else {
            handler(nil)
        }
    }

    // Forward timeline for the bite score: one entry per upcoming hour, so the
    // face updates the score every hour without the app running.
    func getTimelineEndDate(for complication: CLKComplication,
                            withHandler handler: @escaping (Date?) -> Void) {
        handler(complication.identifier == "bite" ? ComplicationStore.hourly.last?.date : nil)
    }

    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int,
                            withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        guard complication.identifier == "bite" else { handler(nil); return }
        let entries = ComplicationStore.hourly.filter { $0.date > date }.prefix(limit).compactMap { hour in
            biteTemplate(complication.family, date: hour.date, sample: false).map { t in
                CLKComplicationTimelineEntry(date: hour.date, complicationTemplate: t)
            }
        }
        handler(entries.isEmpty ? nil : entries)
    }

    func getLocalizableSampleTemplate(for complication: CLKComplication,
                                      withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(template(for: complication.identifier, family: complication.family, date: Date(), sample: true))
    }

    // MARK: - Template building

    private func template(for id: String, family: CLKComplicationFamily, date: Date, sample: Bool) -> CLKComplicationTemplate? {
        switch id {
        case "bite":    return biteTemplate(family, date: date, sample: sample)
        case "session": return sessionTemplate(family, sample: sample)
        case "window":  return windowTemplate(family, sample: sample)
        case "log":     return logTemplate(family)
        default:        return nil
        }
    }

    // Bite score — a 0…100 gauge with the number and a "Bite" label so it
    // clearly reads as a fishing bite score.
    private func biteTemplate(_ family: CLKComplicationFamily, date: Date, sample: Bool) -> CLKComplicationTemplate? {
        let score = sample ? 72 : ComplicationStore.score(at: date)
        let color = ComplicationStore.color(forScore: score)
        let fill = Float(max(0, min(100, score))) / 100
        let num = CLKSimpleTextProvider(text: "\(score)")
        let fishText = CLKSimpleTextProvider(text: "Bite")
        let gauge = CLKSimpleGaugeProvider(style: .fill, gaugeColor: color, fillFraction: fill)

        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
                gaugeProvider: gauge, bottomTextProvider: fishText, centerTextProvider: num)
        case .graphicExtraLarge:
            return CLKComplicationTemplateGraphicExtraLargeCircularClosedGaugeText(
                gaugeProvider: gauge, centerTextProvider: num)
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerGaugeText(
                gaugeProvider: gauge, outerTextProvider: CLKSimpleTextProvider(text: "Bite \(score)"))
        case .graphicBezel:
            let circ = CLKComplicationTemplateGraphicCircularClosedGaugeText(gaugeProvider: gauge, centerTextProvider: num)
            return CLKComplicationTemplateGraphicBezelCircularText(
                circularTemplate: circ, textProvider: CLKSimpleTextProvider(text: "Bite score"))
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularTextGauge(
                headerTextProvider: CLKSimpleTextProvider(text: "Bite score"),
                body1TextProvider: num, gaugeProvider: gauge)
        case .modularSmall:
            return CLKComplicationTemplateModularSmallStackText(line1TextProvider: fishText, line2TextProvider: num)
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "Bite score"),
                body1TextProvider: CLKSimpleTextProvider(text: "\(score) of 100"))
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallStackText(line1TextProvider: fishText, line2TextProvider: num)
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeStackText(line1TextProvider: fishText, line2TextProvider: num)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: CLKSimpleTextProvider(text: "Bite \(score)"))
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: "Bite score \(score)"))
        default:
            return nil
        }
    }

    // Active session — running timer + catch count (or a prompt to start).
    private func sessionTemplate(_ family: CLKComplicationFamily, sample: Bool) -> CLKComplicationTemplate? {
        let tracking = sample ? true : ComplicationStore.isTracking
        let catches = sample ? 3 : ComplicationStore.catchCount
        let start = sample ? Date().addingTimeInterval(-3600) : ComplicationStore.sessionStart

        let caughtText = CLKSimpleTextProvider(text: catches == 1 ? "1 catch" : "\(catches) catches")
        let timeProvider: CLKTextProvider = (tracking && start != nil)
            ? CLKRelativeDateTextProvider(date: start!, style: .timer, units: [.hour, .minute])
            : CLKSimpleTextProvider(text: "Tap to start")
        let header = CLKSimpleTextProvider(text: tracking ? "Fishing" : "Session")

        switch family {
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: header, body1TextProvider: timeProvider, body2TextProvider: caughtText)
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: header, body1TextProvider: timeProvider, body2TextProvider: caughtText)
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerStackText(
                innerTextProvider: caughtText, outerTextProvider: header)
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: tracking ? caughtText : CLKSimpleTextProvider(text: "Start session"))
        case .modularSmall, .circularSmall:
            return CLKComplicationTemplateModularSmallSimpleText(textProvider: CLKSimpleTextProvider(text: "\(catches)"))
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: CLKSimpleTextProvider(text: "\(catches) caught"))
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "\(catches)"),
                line2TextProvider: CLKSimpleTextProvider(text: "caught"))
        default:
            return nil
        }
    }

    // Next planned trip, as the phone formats it.
    private func windowTemplate(_ family: CLKComplicationFamily, sample: Bool) -> CLKComplicationTemplate? {
        let raw = sample ? "Kariba, Sat 6 AM" : ComplicationStore.nextWindow
        let text = raw.isEmpty ? "None planned" : raw
        let value = CLKSimpleTextProvider(text: text)
        let header = CLKSimpleTextProvider(text: "Next trip")

        switch family {
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: header, body1TextProvider: value)
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: header, body1TextProvider: value)
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerStackText(innerTextProvider: value, outerTextProvider: header)
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: value)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: value)
        case .graphicBezel:
            let circ = CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "Next"),
                line2TextProvider: CLKSimpleTextProvider(text: text))
            return CLKComplicationTemplateGraphicBezelCircularText(circularTemplate: circ, textProvider: header)
        default:
            return nil
        }
    }

    // One-tap launcher — opens the watch app (ready to log).
    private func logTemplate(_ family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        let icon = CLKSimpleTextProvider(text: "Catch")
        let label = CLKSimpleTextProvider(text: "Log")
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(line1TextProvider: icon, line2TextProvider: label)
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerStackText(innerTextProvider: label, outerTextProvider: icon)
        case .circularSmall, .modularSmall:
            return CLKComplicationTemplateModularSmallSimpleText(textProvider: label)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: CLKSimpleTextProvider(text: "Log catch"))
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: "Log a catch"))
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "Currents"),
                body1TextProvider: CLKSimpleTextProvider(text: "Tap to log a catch"))
        default:
            return nil
        }
    }
}
