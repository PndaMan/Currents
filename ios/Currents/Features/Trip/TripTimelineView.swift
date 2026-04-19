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

    private var biggestKg: Double {
        catches.compactMap(\.catchRecord.weightKg).max() ?? 0
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CurrentsTheme.accent.opacity(0.25),
                    Color.black.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    statsRow
                    timelineSection
                }
                .padding()
            }
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

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trip.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(trip.startDate.formatted(.dateTime.weekday(.wide).month().day().year()))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 12) {
                Label(durationText, systemImage: "clock.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CurrentsTheme.accent.opacity(0.25))
                    .foregroundStyle(CurrentsTheme.accent)
                    .clipShape(Capsule())

                if let cond = trip.weatherConditions, !cond.isEmpty {
                    Label(cond, systemImage: "cloud.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        if !catches.isEmpty {
            HStack(spacing: 10) {
                miniStat(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                miniStat(value: "\(speciesCount)", label: "Species", icon: "leaf.fill")
                miniStat(value: "\(releasedCount)", label: "Released", icon: "arrow.uturn.backward")
                if biggestKg > 0 {
                    miniStat(value: String(format: "%.1fkg", biggestKg), label: "Biggest", icon: "trophy.fill")
                }
            }
        }
    }

    private func miniStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(CurrentsTheme.accent)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        if catches.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "fish")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No catches on this trip")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(CurrentsTheme.accent)
                    Text("Story Timeline")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 4)

                ForEach(Array(catches.enumerated()), id: \.element.catchRecord.id) { index, detail in
                    timelineEntry(detail: detail, isLast: index == catches.count - 1)
                }
            }
        }
    }

    private func timelineEntry(detail: CatchDetail, isLast: Bool) -> some View {
        let interval = detail.catchRecord.caughtAt.timeIntervalSince(trip.startDate)
        let totalMinutes = max(0, Int(interval) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let timeText = "\(hours)h \(String(format: "%02d", minutes))m"

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(CurrentsTheme.accent)
                        .frame(width: 14, height: 14)
                        .shadow(color: CurrentsTheme.accent, radius: 6)
                    Circle().fill(.white)
                        .frame(width: 5, height: 5)
                }
                if !isLast {
                    Rectangle()
                        .fill(CurrentsTheme.accent.opacity(0.4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CurrentsTheme.accent)
                Text(detail.species?.commonName ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    if let w = detail.catchRecord.weightKg {
                        Text(String(format: "%.1f kg", w))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if let l = detail.catchRecord.lengthCm {
                        Text(String(format: "%.0f cm", l))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if detail.catchRecord.released {
                        Text("Released")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CurrentsTheme.accent.opacity(0.2))
                            .foregroundStyle(CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                }

                if let path = detail.catchRecord.allPhotoPaths.first,
                   let img = PhotoManager.load(path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 14)
        }
    }

    // MARK: - Share Card

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

            // Dark gradient
            let bg = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1.0).cgColor,
                    UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            cgCtx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: cardHeight), options: [])

            let margin: CGFloat = 60
            var y: CGFloat = margin + 20

            // Header label
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor(CurrentsTheme.accent)
            ]
            ("FISHING TRIP" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttrs)
            y += 40

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .heavy),
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
            let boxWidth = (cardWidth - margin * 2 - 24) / 3
            let boxHeight: CGFloat = 140
            let stats: [(String, String)] = [
                ("\(catches.count)", "Catches"),
                ("\(Set(catches.compactMap { $0.species?.id }).count)", "Species"),
                ("\(catches.filter { $0.catchRecord.released }.count)", "Released")
            ]
            for (i, s) in stats.enumerated() {
                let bx = margin + CGFloat(i) * (boxWidth + 12)
                let bRect = CGRect(x: bx, y: y, width: boxWidth, height: boxHeight)
                let bPath = UIBezierPath(roundedRect: bRect, cornerRadius: 16)
                UIColor.white.withAlphaComponent(0.08).setFill()
                bPath.fill()

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 44, weight: .heavy),
                    .foregroundColor: UIColor.white
                ]
                let vSize = (s.0 as NSString).size(withAttributes: valAttrs)
                (s.0 as NSString).draw(at: CGPoint(x: bx + (boxWidth - vSize.width) / 2, y: y + 22), withAttributes: valAttrs)

                let labAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.55)
                ]
                let lSize = (s.1 as NSString).size(withAttributes: labAttrs)
                (s.1 as NSString).draw(at: CGPoint(x: bx + (boxWidth - lSize.width) / 2, y: y + 90), withAttributes: labAttrs)
            }
            y += boxHeight + 36

            // Photo grid
            let photoPaths = catches.compactMap { $0.catchRecord.allPhotoPaths.first }.prefix(4)
            let photos: [UIImage] = photoPaths.compactMap { PhotoManager.load($0) }
            if !photos.isEmpty {
                let cell = (cardWidth - margin * 2 - 12) / 2
                for (i, p) in photos.enumerated() {
                    let row = i / 2
                    let col = i % 2
                    let cx = margin + CGFloat(col) * (cell + 12)
                    let cy = y + CGFloat(row) * (cell + 12)
                    let cr = CGRect(x: cx, y: cy, width: cell, height: cell)
                    let cp = UIBezierPath(roundedRect: cr, cornerRadius: 16)
                    cgCtx.saveGState()
                    cp.addClip()
                    let scale = max(cell / p.size.width, cell / p.size.height)
                    let dw = p.size.width * scale
                    let dh = p.size.height * scale
                    p.draw(in: CGRect(x: cx + (cell - dw) / 2, y: cy + (cell - dh) / 2, width: dw, height: dh))
                    cgCtx.restoreGState()
                }
            }

            // Watermark
            let bottomAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor(CurrentsTheme.accent).withAlphaComponent(0.7)
            ]
            ("Currents" as NSString).draw(at: CGPoint(x: margin, y: cardHeight - margin - 30), withAttributes: bottomAttrs)
        }
    }
}
