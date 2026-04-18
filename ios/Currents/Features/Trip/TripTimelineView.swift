import SwiftUI

// MARK: - Trip Timeline View

struct TripTimelineView: View {
    @Environment(AppState.self) private var appState
    let trip: Trip
    @State private var catches: [CatchDetail] = []
    @State private var tripPhotos: [String] = []
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingCard = false

    // MARK: - Computed Properties

    private var duration: TimeInterval? {
        guard let end = trip.endDate else { return nil }
        return end.timeIntervalSince(trip.startDate)
    }

    private var durationText: String {
        guard let duration else { return "In Progress" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    private var speciesCount: Int {
        Set(catches.compactMap { $0.species?.id }).count
    }

    private var releasedCount: Int {
        catches.filter { $0.catchRecord.released }.count
    }

    /// All timeline entries (catches + trip photos) sorted chronologically.
    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = []

        for detail in catches {
            entries.append(.catch(detail))
        }

        for photo in tripPhotos {
            // Trip photos don't have a timestamp in our model, so place them
            // at trip start (they appear at the beginning of the timeline).
            entries.append(.tripPhoto(photo, date: trip.startDate))
        }

        return entries.sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                tripHeaderCard
                statsRow
                timelineSection
            }
            .padding()
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    generateShareCard()
                } label: {
                    if isGeneratingCard {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isGeneratingCard)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ImageShareSheet(image: shareImage)
            }
        }
        .task {
            catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
            // Collect all unique photo paths from catches as "trip photos"
            tripPhotos = catches.flatMap { $0.catchRecord.allPhotoPaths }
        }
    }

    // MARK: - Trip Header Card

    private var tripHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.title2.bold())
                    Text(trip.startDate.formatted(.dateTime.weekday(.wide).month().day().year()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(durationText)
                        .font(.title3.bold())
                        .foregroundStyle(CurrentsTheme.accent)
                    Text("duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let conditions = trip.weatherConditions, !conditions.isEmpty {
                HStack(spacing: 6) {
                    WeatherIcon(condition: conditions)
                    Text(conditions.capitalized)
                        .font(.caption)
                }
                .glassPill()
            }
        }
        .glassCard()
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        if !catches.isEmpty {
            HStack(spacing: 12) {
                StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                StatCard(value: "\(speciesCount)", label: "Species", icon: "leaf.fill")
                StatCard(value: "\(releasedCount)", label: "Released", icon: "arrow.uturn.backward")
            }
        }
    }

    // MARK: - Timeline Section

    @ViewBuilder
    private var timelineSection: some View {
        if timelineEntries.isEmpty {
            ContentUnavailableView(
                "No Activity",
                systemImage: "clock",
                description: Text("Catches logged during this trip will appear on the timeline")
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Timeline")
                    .font(.headline)
                    .padding(.bottom, 12)

                ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                    TimelineNodeView(
                        entry: entry,
                        tripStart: trip.startDate,
                        isLast: index == timelineEntries.count - 1
                    )
                }
            }
        }
    }

    // MARK: - Share Card Generation

    private func generateShareCard() {
        isGeneratingCard = true
        Task {
            let card = Self.generateShareCard(trip: trip, catches: catches)
            shareImage = card
            showingShareSheet = true
            isGeneratingCard = false
        }
    }

    /// Renders a 1080x1350 shareable summary card for a trip.
    static func generateShareCard(trip: Trip, catches: [CatchDetail]) -> UIImage {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cardWidth, height: cardHeight))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight)

            // Background — dark gradient
            let bgGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1.0).cgColor,
                    UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0).cgColor,
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            cgCtx.drawLinearGradient(
                bgGradient,
                start: .zero,
                end: CGPoint(x: 0, y: cardHeight),
                options: []
            )

            let margin: CGFloat = 60
            var y: CGFloat = margin

            // -- Watermark (top-left) --
            if let logoImage = UIImage(named: "Logo") {
                let logoSize: CGFloat = 50
                let logoRect = CGRect(x: margin, y: y, width: logoSize, height: logoSize)
                logoImage.draw(in: logoRect)

                let wordmark = "Currents"
                let wordmarkAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]
                (wordmark as NSString).draw(
                    at: CGPoint(x: margin + logoSize + 12, y: y + 8),
                    withAttributes: wordmarkAttrs
                )
            }
            y += 80

            // -- Divider line --
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: margin, y: y))
            dividerPath.addLine(to: CGPoint(x: cardWidth - margin, y: y))
            UIColor.white.withAlphaComponent(0.15).setStroke()
            dividerPath.lineWidth = 2
            dividerPath.stroke()
            y += 30

            // -- Trip Name --
            let tripNameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let tripNameRect = CGRect(x: margin, y: y, width: cardWidth - margin * 2, height: 140)
            (trip.name as NSString).draw(in: tripNameRect, withAttributes: tripNameAttrs)
            y += 80

            // -- Date --
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            let dateStr = formatter.string(from: trip.startDate)
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            ]
            (dateStr as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttrs)
            y += 40

            // -- Duration badge --
            if let endDate = trip.endDate {
                let dur = endDate.timeIntervalSince(trip.startDate)
                let hours = Int(dur) / 3600
                let minutes = (Int(dur) % 3600) / 60
                let durText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

                let badgeRect = CGRect(x: margin, y: y, width: 200, height: 48)
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 24)
                UIColor(CurrentsTheme.accent).withAlphaComponent(0.85).setFill()
                badgePath.fill()

                let durAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let durSize = (durText as NSString).size(withAttributes: durAttrs)
                let durPoint = CGPoint(
                    x: badgeRect.midX - durSize.width / 2,
                    y: badgeRect.midY - durSize.height / 2
                )
                (durText as NSString).draw(at: durPoint, withAttributes: durAttrs)
                y += 70
            }

            y += 20

            // -- Photo grid (up to 4 photos) --
            let photoCatches = catches.filter { !$0.catchRecord.allPhotoPaths.isEmpty }
            let photoImages: [UIImage] = Array(
                photoCatches
                    .prefix(4)
                    .compactMap { detail -> UIImage? in
                        guard let path = detail.catchRecord.allPhotoPaths.first else { return nil }
                        return PhotoManager.load(path)
                    }
            )

            if !photoImages.isEmpty {
                let gridSize = cardWidth - margin * 2
                let cellSpacing: CGFloat = 8
                let cellSize = (gridSize - cellSpacing) / 2

                for (index, photo) in photoImages.enumerated() {
                    let row = index / 2
                    let col = index % 2
                    let cellX = margin + CGFloat(col) * (cellSize + cellSpacing)
                    let cellY = y + CGFloat(row) * (cellSize + cellSpacing)
                    let cellRect = CGRect(x: cellX, y: cellY, width: cellSize, height: cellSize)

                    let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 16)
                    cgCtx.saveGState()
                    cellPath.addClip()

                    // Scale photo to fill cell
                    let scale = max(cellSize / photo.size.width, cellSize / photo.size.height)
                    let drawW = photo.size.width * scale
                    let drawH = photo.size.height * scale
                    let drawRect = CGRect(
                        x: cellX + (cellSize - drawW) / 2,
                        y: cellY + (cellSize - drawH) / 2,
                        width: drawW,
                        height: drawH
                    )
                    photo.draw(in: drawRect)
                    cgCtx.restoreGState()

                    // Border
                    UIColor.white.withAlphaComponent(0.2).setStroke()
                    cellPath.lineWidth = 2
                    cellPath.stroke()
                }

                let rows = photoImages.count > 2 ? 2 : 1
                y += CGFloat(rows) * (cellSize + cellSpacing) + 30
            }

            // -- Stats section --
            y += 10
            let statsBoxWidth = (cardWidth - margin * 2 - 24) / 3

            let statsData: [(String, String)] = [
                ("\(catches.count)", "Catches"),
                ("\(Set(catches.compactMap { $0.species?.id }).count)", "Species"),
                ("\(catches.filter { $0.catchRecord.released }.count)", "Released"),
            ]

            for (index, stat) in statsData.enumerated() {
                let boxX = margin + CGFloat(index) * (statsBoxWidth + 12)
                let boxRect = CGRect(x: boxX, y: y, width: statsBoxWidth, height: 100)
                let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 16)
                UIColor.white.withAlphaComponent(0.08).setFill()
                boxPath.fill()

                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let valueSize = (stat.0 as NSString).size(withAttributes: valueAttrs)
                (stat.0 as NSString).draw(
                    at: CGPoint(x: boxRect.midX - valueSize.width / 2, y: boxRect.minY + 14),
                    withAttributes: valueAttrs
                )

                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.5),
                ]
                let labelSize = (stat.1 as NSString).size(withAttributes: labelAttrs)
                (stat.1 as NSString).draw(
                    at: CGPoint(x: boxRect.midX - labelSize.width / 2, y: boxRect.minY + 62),
                    withAttributes: labelAttrs
                )
            }

            // -- Bottom watermark --
            let bottomText = "Shared from Currents"
            let bottomAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.3),
            ]
            let bottomSize = (bottomText as NSString).size(withAttributes: bottomAttrs)
            (bottomText as NSString).draw(
                at: CGPoint(
                    x: (cardWidth - bottomSize.width) / 2,
                    y: cardHeight - margin - bottomSize.height
                ),
                withAttributes: bottomAttrs
            )
        }
    }
}

// MARK: - Timeline Entry Model

enum TimelineEntry: Identifiable {
    case `catch`(CatchDetail)
    case tripPhoto(String, date: Date)

    var id: String {
        switch self {
        case .catch(let detail):
            return "catch-\(detail.catchRecord.id)"
        case .tripPhoto(let filename, _):
            return "photo-\(filename)"
        }
    }

    var date: Date {
        switch self {
        case .catch(let detail):
            return detail.catchRecord.caughtAt
        case .tripPhoto(_, let date):
            return date
        }
    }
}

// MARK: - Timeline Node View

struct TimelineNodeView: View {
    let entry: TimelineEntry
    let tripStart: Date
    let isLast: Bool

    private var relativeTimeText: String {
        let interval = entry.date.timeIntervalSince(tripStart)
        let totalMinutes = max(0, Int(interval) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline line + dot
            VStack(spacing: 0) {
                Circle()
                    .fill(CurrentsTheme.accent)
                    .frame(width: 12, height: 12)

                if !isLast {
                    Rectangle()
                        .fill(CurrentsTheme.accent.opacity(0.4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            // Connector line from dot to content
            Rectangle()
                .fill(CurrentsTheme.accent.opacity(0.4))
                .frame(width: 16, height: 2)
                .padding(.top, 5)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                switch entry {
                case .catch(let detail):
                    catchNodeContent(detail: detail)
                case .tripPhoto(let filename, _):
                    tripPhotoNodeContent(filename: filename)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Catch Node

    @ViewBuilder
    private func catchNodeContent(detail: CatchDetail) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Time label
                Text(relativeTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Species name
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.headline)

                // Measurements
                HStack(spacing: 8) {
                    if let weight = detail.catchRecord.weightKg {
                        Text(String(format: "%.1fkg", weight))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let length = detail.catchRecord.lengthCm {
                        Text(String(format: "%.0fcm", length))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if detail.catchRecord.released {
                        Text("Released")
                            .font(.caption2.bold())
                            .foregroundStyle(CurrentsTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CurrentsTheme.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                // Forecast score badge
                if let score = detail.catchRecord.forecastScoreAtCapture {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.medium")
                            .font(.caption2)
                        Text("Score: \(score)")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(CurrentsTheme.scoreColor(score))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CurrentsTheme.scoreColor(score).opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            // Photo thumbnail
            if let photoPath = detail.catchRecord.allPhotoPaths.first,
               let image = PhotoManager.load(photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .glassCard()
    }

    // MARK: - Trip Photo Node

    @ViewBuilder
    private func tripPhotoNodeContent(filename: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(relativeTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Trip Memory")
                .font(.headline)
                .foregroundStyle(CurrentsTheme.accent)

            if let image = PhotoManager.load(filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .glassCard()
    }
}
