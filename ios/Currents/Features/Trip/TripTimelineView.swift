import SwiftUI

struct TripTimelineView: View {
    @Environment(AppState.self) private var appState
    let trip: Trip
    @State private var catches: [CatchDetail] = []
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingCard = false

    private var durationText: String {
        guard let end = trip.endDate else { return "In Progress" }
        let dur = end.timeIntervalSince(trip.startDate)
        let hours = Int(dur) / 3600
        let minutes = (Int(dur) % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    private var speciesCount: Int {
        Set(catches.compactMap { $0.species?.id }).count
    }

    private var releasedCount: Int {
        catches.filter { $0.catchRecord.released }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
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
                }
                .glassCard()

                // Stats
                if !catches.isEmpty {
                    HStack(spacing: 12) {
                        StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                        StatCard(value: "\(speciesCount)", label: "Species", icon: "leaf.fill")
                        StatCard(value: "\(releasedCount)", label: "Released", icon: "arrow.uturn.backward")
                    }
                }

                // Timeline of catches
                if catches.isEmpty {
                    ContentUnavailableView(
                        "No Activity",
                        systemImage: "clock",
                        description: Text("Catches logged during this trip will appear here")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline")
                            .font(.headline)

                        ForEach(Array(catches.enumerated()), id: \.element.catchRecord.id) { index, detail in
                            timelineEntry(detail: detail, isLast: index == catches.count - 1)
                        }
                    }
                }
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
        }
    }

    private func timelineEntry(detail: CatchDetail, isLast: Bool) -> some View {
        let interval = detail.catchRecord.caughtAt.timeIntervalSince(trip.startDate)
        let totalMinutes = max(0, Int(interval) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let timeText = "\(hours)h \(String(format: "%02d", minutes))m"

        return HStack(alignment: .top, spacing: 12) {
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

            VStack(alignment: .leading, spacing: 4) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.headline)
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
                if let photoPath = detail.catchRecord.allPhotoPaths.first,
                   let image = PhotoManager.load(photoPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func generateShareCard() {
        isGeneratingCard = true
        Task { @MainActor in
            shareImage = Self.renderShareCard(trip: trip, catches: catches)
            showingShareSheet = true
            isGeneratingCard = false
        }
    }

    static func renderShareCard(trip: Trip, catches: [CatchDetail]) -> UIImage {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cardWidth, height: cardHeight))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Dark gradient background
            let bg = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1.0).cgColor,
                    UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            cgCtx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: cardHeight), options: [])

            let margin: CGFloat = 60
            var y: CGFloat = margin + 20

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            (trip.name as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 80

            // Date
            let f = DateFormatter()
            f.dateStyle = .long
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            (f.string(from: trip.startDate) as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttrs)
            y += 80

            // Stats boxes
            let statsBoxWidth = (cardWidth - margin * 2 - 24) / 3
            let statsBoxHeight: CGFloat = 140
            let stats: [(String, String)] = [
                ("\(catches.count)", "Catches"),
                ("\(Set(catches.compactMap { $0.species?.id }).count)", "Species"),
                ("\(catches.filter { $0.catchRecord.released }.count)", "Released")
            ]
            for (i, s) in stats.enumerated() {
                let boxX = margin + CGFloat(i) * (statsBoxWidth + 12)
                let boxRect = CGRect(x: boxX, y: y, width: statsBoxWidth, height: statsBoxHeight)
                let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 16)
                UIColor.white.withAlphaComponent(0.08).setFill()
                boxPath.fill()

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let valSize = (s.0 as NSString).size(withAttributes: valAttrs)
                (s.0 as NSString).draw(at: CGPoint(x: boxX + (statsBoxWidth - valSize.width) / 2, y: y + 30), withAttributes: valAttrs)

                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.5)
                ]
                let labelSize = (s.1 as NSString).size(withAttributes: labelAttrs)
                (s.1 as NSString).draw(at: CGPoint(x: boxX + (statsBoxWidth - labelSize.width) / 2, y: y + 90), withAttributes: labelAttrs)
            }
            y += statsBoxHeight + 40

            // Photos grid (up to 4)
            let photoPaths = catches.compactMap { $0.catchRecord.allPhotoPaths.first }.prefix(4)
            let photos: [UIImage] = photoPaths.compactMap { PhotoManager.load($0) }
            if !photos.isEmpty {
                let cellSize = (cardWidth - margin * 2 - 12) / 2
                for (i, photo) in photos.enumerated() {
                    let row = i / 2
                    let col = i % 2
                    let cellX = margin + CGFloat(col) * (cellSize + 12)
                    let cellY = y + CGFloat(row) * (cellSize + 12)
                    let cellRect = CGRect(x: cellX, y: cellY, width: cellSize, height: cellSize)
                    let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 16)
                    cgCtx.saveGState()
                    cellPath.addClip()
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
                }
            }

            // Watermark
            let bottomAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.3)
            ]
            ("Currents" as NSString).draw(at: CGPoint(x: margin, y: cardHeight - margin - 30), withAttributes: bottomAttrs)
        }
    }
}
