import SwiftUI

struct TripTimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip

    @State private var catches: [CatchDetail] = []
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingCard = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

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

    /// Mixed chronological timeline of catches + memory photos.
    enum TimelineEntry: Identifiable {
        case fishCatch(CatchDetail)
        case memory(String, Date) // photo filename + placed at trip start

        var id: String {
            switch self {
            case .fishCatch(let d): return "c-" + d.catchRecord.id
            case .memory(let f, _): return "m-" + f
            }
        }

        var date: Date {
            switch self {
            case .fishCatch(let d): return d.catchRecord.caughtAt
            case .memory(_, let d): return d
            }
        }
    }

    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = catches.map { .fishCatch($0) }
        // Spread memory photos evenly across trip duration (so they appear throughout)
        let photos = trip.allPhotoPaths
        if !photos.isEmpty {
            let tripStart = trip.startDate
            let tripEnd = trip.endDate ?? .now
            let totalSeconds = max(tripEnd.timeIntervalSince(tripStart), 60)
            for (i, path) in photos.enumerated() {
                let fraction = Double(i + 1) / Double(photos.count + 1)
                let date = tripStart.addingTimeInterval(totalSeconds * fraction)
                entries.append(.memory(path, date))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CurrentsTheme.accent.opacity(0.25), Color.black.opacity(0.9)],
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
                Menu {
                    Button {
                        generateShareCard()
                    } label: {
                        Label("Share Trip", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isGeneratingCard)
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit Trip", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Trip", systemImage: "trash")
                    }
                } label: {
                    if isGeneratingCard {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ImageShareSheet(image: shareImage)
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: {
            if let fresh = try? appState.tripRepository.fetch(trip.id) {
                trip = fresh
            }
        }) {
            TripEditSheet(trip: trip)
        }
        .alert("Delete Trip?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.tripRepository.delete(trip)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the trip. Catches will remain but become unlinked from the trip.")
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
                        .foregroundStyle(.white.opacity(0.85))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }

            if let notes = trip.notes, !notes.isEmpty {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 4)
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
        let memoryCount = trip.allPhotoPaths.count
        if !catches.isEmpty || memoryCount > 0 {
            HStack(spacing: 10) {
                miniStat(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                miniStat(value: "\(speciesCount)", label: "Species", icon: "leaf.fill")
                miniStat(value: "\(memoryCount)", label: "Memories", icon: "photo.stack")
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
        let entries = timelineEntries
        if entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "fish")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No activity yet")
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

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    timelineRow(entry: entry, isLast: index == entries.count - 1)
                }
            }
        }
    }

    private func timelineRow(entry: TimelineEntry, isLast: Bool) -> some View {
        let interval = entry.date.timeIntervalSince(trip.startDate)
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

                switch entry {
                case .fishCatch(let detail):
                    catchEntry(detail)
                case .memory(let path, _):
                    memoryEntry(path)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 14)
        }
    }

    private func catchEntry(_ detail: CatchDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "fish.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                Text(detail.species?.commonName ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

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
    }

    private func memoryEntry(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundStyle(CurrentsTheme.accent)
                Text("Trip Memory")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            if let img = PhotoManager.load(path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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

    /// Beautiful 1080x1350 share card with theme-matched background, logo, stats, and photo collage.
    static func renderShareCard(trip: Trip, catches: [CatchDetail]) -> UIImage {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350
        let accent = UIColor(CurrentsTheme.accent)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cardWidth, height: cardHeight))

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // --- Background gradient (theme-accented) ---
            let bgColors: [CGColor] = [
                UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0).cgColor,
                accent.withAlphaComponent(0.35).cgColor,
                UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0).cgColor
            ]
            let bgGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: bgColors as CFArray,
                locations: [0.0, 0.5, 1.0]
            )!
            cgCtx.drawLinearGradient(
                bgGradient,
                start: .zero,
                end: CGPoint(x: cardWidth, y: cardHeight),
                options: []
            )

            // --- Decorative background symbols ---
            let decorations: [(String, CGPoint, CGFloat, CGFloat)] = [
                ("water.waves", CGPoint(x: 920, y: 160), 90, 0.08),
                ("fish.fill", CGPoint(x: 140, y: 1100), 110, 0.06),
                ("leaf.fill", CGPoint(x: 960, y: 1180), 70, 0.06),
                ("cloud.fill", CGPoint(x: 200, y: 180), 80, 0.05)
            ]
            for (name, pt, size, alpha) in decorations {
                let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
                if let img = UIImage(systemName: name, withConfiguration: cfg) {
                    img.withTintColor(UIColor.white.withAlphaComponent(alpha),
                                      renderingMode: .alwaysOriginal)
                        .draw(at: pt)
                }
            }

            let margin: CGFloat = 60
            var y: CGFloat = margin + 10

            // --- Logo + wordmark ---
            if let logoImage = UIImage(named: "Logo") {
                let logoSize: CGFloat = 56
                logoImage.draw(in: CGRect(x: margin, y: y, width: logoSize, height: logoSize))
                let wordAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9)
                ]
                ("Currents" as NSString).draw(
                    at: CGPoint(x: margin + logoSize + 14, y: y + 10),
                    withAttributes: wordAttrs
                )
            } else {
                let wordAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
                    .foregroundColor: accent
                ]
                ("Currents" as NSString).draw(at: CGPoint(x: margin, y: y + 10), withAttributes: wordAttrs)
            }
            y += 90

            // --- "FISHING TRIP" label ---
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .heavy),
                .foregroundColor: accent,
                .kern: 3.0
            ]
            ("FISHING TRIP" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 36

            // --- Title (trip name) ---
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let titleRect = CGRect(x: margin, y: y, width: cardWidth - margin * 2, height: 140)
            (trip.name as NSString).draw(in: titleRect, withAttributes: titleAttrs)
            y += 90

            // --- Date ---
            let f = DateFormatter()
            f.dateStyle = .long
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65)
            ]
            (f.string(from: trip.startDate) as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttrs)
            y += 40

            // --- Duration badge ---
            if let end = trip.endDate {
                let dur = end.timeIntervalSince(trip.startDate)
                let hrs = Int(dur) / 3600
                let mins = (Int(dur) % 3600) / 60
                let durText = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"

                let padH: CGFloat = 16
                let durAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let durSize = (durText as NSString).size(withAttributes: durAttrs)
                let badgeRect = CGRect(x: margin, y: y, width: durSize.width + padH * 2, height: 40)
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 20)
                accent.withAlphaComponent(0.9).setFill()
                badgePath.fill()
                (durText as NSString).draw(
                    at: CGPoint(x: margin + padH, y: y + (40 - durSize.height) / 2),
                    withAttributes: durAttrs
                )
            }
            y += 70

            // --- Stats row ---
            let stats: [(String, String, String)] = [
                ("\(catches.count)", "CATCHES", "fish.fill"),
                ("\(Set(catches.compactMap { $0.species?.id }).count)", "SPECIES", "leaf.fill"),
                ("\(trip.allPhotoPaths.count)", "MEMORIES", "photo.stack")
            ]
            let statW = (cardWidth - margin * 2 - 24) / 3
            let statH: CGFloat = 130
            for (i, s) in stats.enumerated() {
                let x = margin + CGFloat(i) * (statW + 12)
                let rect = CGRect(x: x, y: y, width: statW, height: statH)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                UIColor.white.withAlphaComponent(0.08).setFill()
                path.fill()
                accent.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1.5
                path.stroke()

                let iconCfg = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
                if let icon = UIImage(systemName: s.2, withConfiguration: iconCfg)?
                    .withTintColor(accent, renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(x: x + 14, y: y + 14))
                }

                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
                    .foregroundColor: UIColor.white
                ]
                let vs = (s.0 as NSString).size(withAttributes: valueAttrs)
                (s.0 as NSString).draw(
                    at: CGPoint(x: x + (statW - vs.width) / 2, y: y + 46),
                    withAttributes: valueAttrs
                )

                let labAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.55),
                    .kern: 1.5
                ]
                let ls = (s.1 as NSString).size(withAttributes: labAttrs)
                (s.1 as NSString).draw(
                    at: CGPoint(x: x + (statW - ls.width) / 2, y: y + statH - 28),
                    withAttributes: labAttrs
                )
            }
            y += statH + 36

            // --- Photo collage (catches + memories mixed) ---
            var allPhotos: [UIImage] = []
            for c in catches {
                if let path = c.catchRecord.allPhotoPaths.first, let img = PhotoManager.load(path) {
                    allPhotos.append(img)
                }
            }
            for p in trip.allPhotoPaths {
                if let img = PhotoManager.load(p) {
                    allPhotos.append(img)
                }
            }

            if !allPhotos.isEmpty {
                let photos = Array(allPhotos.prefix(6))
                let collageY = y
                let availableH = cardHeight - y - 100
                drawCollage(photos: photos,
                            in: CGRect(x: margin, y: collageY, width: cardWidth - margin * 2, height: availableH),
                            ctx: cgCtx)
            }

            // --- Bottom signature ---
            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: accent.withAlphaComponent(0.85),
                .kern: 2.0
            ]
            let sig = "SHARED FROM CURRENTS"
            let sigSize = (sig as NSString).size(withAttributes: sigAttrs)
            (sig as NSString).draw(
                at: CGPoint(x: (cardWidth - sigSize.width) / 2, y: cardHeight - 50),
                withAttributes: sigAttrs
            )
        }
    }

    /// Draw an asymmetric collage of photos inside a bounding rect.
    private static func drawCollage(photos: [UIImage], in rect: CGRect, ctx: CGContext) {
        guard !photos.isEmpty else { return }
        let n = photos.count
        let gap: CGFloat = 8
        let corner: CGFloat = 14

        // Layout strategies by photo count
        var frames: [CGRect] = []
        switch n {
        case 1:
            frames = [rect]
        case 2:
            let h = (rect.height - gap) / 2
            frames = [
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h + gap, width: rect.width, height: h)
            ]
        case 3:
            let bigH = rect.height * 0.6
            let smallH = rect.height - bigH - gap
            let smallW = (rect.width - gap) / 2
            frames = [
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bigH),
                CGRect(x: rect.minX, y: rect.minY + bigH + gap, width: smallW, height: smallH),
                CGRect(x: rect.minX + smallW + gap, y: rect.minY + bigH + gap, width: smallW, height: smallH)
            ]
        case 4:
            let cellW = (rect.width - gap) / 2
            let cellH = (rect.height - gap) / 2
            frames = [
                CGRect(x: rect.minX, y: rect.minY, width: cellW, height: cellH),
                CGRect(x: rect.minX + cellW + gap, y: rect.minY, width: cellW, height: cellH),
                CGRect(x: rect.minX, y: rect.minY + cellH + gap, width: cellW, height: cellH),
                CGRect(x: rect.minX + cellW + gap, y: rect.minY + cellH + gap, width: cellW, height: cellH)
            ]
        default:
            // 5 or 6: big left, 2x2 or 2x3 right
            let leftW = rect.width * 0.55
            let rightW = rect.width - leftW - gap
            let count = min(n, 6)
            let rowsRight = count == 5 ? 2 : 3
            let cellH = (rect.height - gap * CGFloat(rowsRight - 1)) / CGFloat(rowsRight)
            frames = [CGRect(x: rect.minX, y: rect.minY, width: leftW, height: rect.height)]
            for i in 0..<(count - 1) {
                frames.append(CGRect(
                    x: rect.minX + leftW + gap,
                    y: rect.minY + CGFloat(i) * (cellH + gap),
                    width: rightW,
                    height: cellH
                ))
            }
        }

        for (i, frame) in frames.enumerated() {
            guard i < photos.count else { break }
            let photo = photos[i]
            let path = UIBezierPath(roundedRect: frame, cornerRadius: corner)
            ctx.saveGState()
            path.addClip()
            // scale-to-fill
            let scale = max(frame.width / photo.size.width, frame.height / photo.size.height)
            let drawW = photo.size.width * scale
            let drawH = photo.size.height * scale
            photo.draw(in: CGRect(
                x: frame.midX - drawW / 2,
                y: frame.midY - drawH / 2,
                width: drawW,
                height: drawH
            ))
            ctx.restoreGState()

            // subtle border
            UIColor.white.withAlphaComponent(0.15).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

// MARK: - Trip Edit Sheet

struct TripEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var weatherConditions: String
    @State private var endDate: Date?
    let originalTrip: Trip

    init(trip: Trip) {
        self.originalTrip = trip
        _name = State(initialValue: trip.name)
        _notes = State(initialValue: trip.notes ?? "")
        _weatherConditions = State(initialValue: trip.weatherConditions ?? "")
        _endDate = State(initialValue: trip.endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Info") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Weather Conditions") {
                    TextField("e.g. Overcast, 20°C", text: $weatherConditions)
                }
                Section("Timing") {
                    LabeledContent("Started") {
                        Text(originalTrip.startDate, style: .date)
                    }
                    if let end = endDate {
                        HStack {
                            Text("Ended")
                            Spacer()
                            Text(end, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("In Progress")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = originalTrip
        updated.name = name
        updated.notes = notes.isEmpty ? nil : notes
        updated.weatherConditions = weatherConditions.isEmpty ? nil : weatherConditions
        try? appState.tripRepository.save(&updated)
    }
}
