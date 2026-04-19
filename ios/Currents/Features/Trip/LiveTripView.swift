import SwiftUI
import CoreLocation

struct LiveTripView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var showingLogCatch = false
    @State private var showingCamera = false
    @State private var tripPhotos: [UIImage] = []
    @State private var showingEndConfirm = false
    @State private var nearbySpot: Spot?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingL) {
                liveTimerSection
                weatherAndBiteScoreCard
                quickActionsRow
                nearbySpotCard
                tripFeedSection
                endTripButton
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startSession() }
        .onDisappear { timer?.invalidate() }
        .task { await loadCatches() }
        .fullScreenCover(isPresented: $showingLogCatch) {
            LogCatchView()
        }
        .sheet(isPresented: $showingCamera) {
            CameraPlaceholderView(photos: $tripPhotos)
        }
        .alert("End Trip?", isPresented: $showingEndConfirm) {
            Button("End Trip", role: .destructive) { endTrip() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will finish the current session and save your trip summary.")
        }
        .onChange(of: showingLogCatch) { _, isShowing in
            if !isShowing {
                Task { await loadCatches() }
            }
        }
    }

    // MARK: - 1. Live Timer

    private var liveTimerSection: some View {
        VStack(spacing: 12) {
            // LIVE badge
            HStack(spacing: 6) {
                Circle()
                    .fill(CurrentsTheme.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: CurrentsTheme.accent, radius: 4)
                    .modifier(PulseModifier())
                Text("LIVE")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(CurrentsTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(CurrentsTheme.accent.opacity(0.15))
            .clipShape(Capsule())

            // Timer display
            HStack(spacing: 4) {
                Text(timerString)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Text("Trip Duration")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CurrentsTheme.paddingL)
        .glassCard()
    }

    private var timerString: String {
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - 2. Weather & Bite Score Card

    private var weatherAndBiteScoreCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: CurrentsTheme.paddingM) {
                // Weather column
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conditions")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if let w = weather {
                        HStack(spacing: 8) {
                            WeatherIcon(condition: w.condition)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.0f°C", w.temperatureC))
                                    .font(.title3.bold())
                                Text(w.condition.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Label(
                            String(format: "%.0f km/h", w.windSpeedKmh),
                            systemImage: "wind"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Label(
                            String(format: "%.0f hPa", w.pressureHpa),
                            systemImage: "gauge.medium"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading weather...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Bite score column
                VStack(spacing: 4) {
                    if let f = forecast {
                        ScoreGauge(score: f.score, label: "Bite Score", size: 72)
                    } else {
                        ScoreGauge(score: 0, label: "Bite Score", size: 72)
                            .redacted(reason: .placeholder)
                    }
                }
            }

            // Best hours
            if let f = forecast, !f.bestHours.isEmpty {
                Divider().opacity(0.3)
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(CurrentsTheme.accent)
                        .font(.caption)
                    Text("Best hours: \(f.bestHours.map { formatHour($0) }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
    }

    // MARK: - 3. Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                showingLogCatch = true
            } label: {
                Label("Log Catch", systemImage: "fish.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(CurrentsTheme.accent)

            Button {
                showingCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(CurrentsTheme.accent)
        }
    }

    // MARK: - 4. Nearby Spot Detection

    private var nearbySpotCard: some View {
        Group {
            if let spot = nearbySpot {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(CurrentsTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Near: \(spot.name)")
                            .font(.subheadline.bold())
                        Text("Catches will be linked to this spot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .glassCard()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "location.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No saved spot detected nearby")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Catches will use GPS coordinates")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .glassCard()
            }
        }
    }

    // MARK: - 5. Trip Feed

    private var tripFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trip Feed")
                    .font(.headline)
                Spacer()
                Text("\(catches.count) catch\(catches.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Photo thumbnails
            if !tripPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tripPhotos.indices, id: \.self) { index in
                            Image(uiImage: tripPhotos[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            // Catches list
            if catches.isEmpty && tripPhotos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fish")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No catches yet — get out there!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CurrentsTheme.paddingL)
            } else {
                ForEach(catches, id: \.catchRecord.id) { detail in
                    catchFeedRow(detail)
                    if detail.catchRecord.id != catches.last?.catchRecord.id {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .glassCard()
    }

    private func catchFeedRow(_ detail: CatchDetail) -> some View {
        HStack(spacing: 12) {
            // Species icon
            ZStack {
                Circle()
                    .fill(CurrentsTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "fish.fill")
                    .foregroundStyle(CurrentsTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.subheadline.bold())

                HStack(spacing: 8) {
                    Text(detail.catchRecord.caughtAt.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let weight = detail.catchRecord.weightKg {
                        Text(String(format: "%.1f kg", weight))
                            .font(.caption)
                            .foregroundStyle(CurrentsTheme.accent)
                    }

                    if let length = detail.catchRecord.lengthCm {
                        Text(String(format: "%.0f cm", length))
                            .font(.caption)
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                }
            }

            Spacer()

            if detail.catchRecord.released {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 6. End Trip Button

    private var endTripButton: some View {
        Button(role: .destructive) {
            showingEndConfirm = true
        } label: {
            HStack {
                Image(systemName: "stop.circle.fill")
                Text("End Trip")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    // MARK: - Logic

    private func startSession() {
        // Start live timer
        elapsed = Date.now.timeIntervalSince(trip.startDate)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsed = Date.now.timeIntervalSince(trip.startDate)
            }
        }

        // Start location updates
        appState.locationManager.startUpdating()

        // Fetch weather and forecast
        Task { @MainActor in
            guard let location = appState.locationManager.currentLocation else {
                // Wait briefly for a location fix
                try? await Task.sleep(for: .seconds(2))
                guard let loc = appState.locationManager.currentLocation else { return }
                await fetchWeatherAndForecast(coordinate: loc.coordinate)
                detectNearbySpot(coordinate: loc.coordinate)
                return
            }
            await fetchWeatherAndForecast(coordinate: location.coordinate)
            detectNearbySpot(coordinate: location.coordinate)
        }
    }

    private func fetchWeatherAndForecast(coordinate: CLLocationCoordinate2D) async {
        // Fetch weather
        let weatherData = await WeatherService.shared.current(for: coordinate)
        weather = weatherData

        // Compute forecast
        let result = ForecastEngine.forecast(
            date: .now,
            coordinate: coordinate,
            currentPressureHpa: weatherData?.pressureHpa,
            pressureChange6h: weatherData?.pressureChange6h,
            waterTempC: weatherData?.waterTempC,
            windSpeedKmh: weatherData?.windSpeedKmh,
            windDirection: weatherData?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        forecast = result
    }

    private func detectNearbySpot(coordinate: CLLocationCoordinate2D) {
        guard let allSpots = try? appState.spotRepository.fetchAll() else { return }

        let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var closestSpot: Spot?
        var closestDistance: CLLocationDistance = .greatestFiniteMagnitude

        for spot in allSpots {
            let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let distance = currentLocation.distance(from: spotLocation)
            if distance < 500 && distance < closestDistance {
                closestDistance = distance
                closestSpot = spot
            }
        }

        nearbySpot = closestSpot
    }

    private func loadCatches() async {
        catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
    }

    private func endTrip() {
        var updated = trip
        updated.endDate = .now
        try? appState.tripRepository.save(&updated)
        dismiss()
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: .now).addingTimeInterval(Double(hour) * 3600)
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Pulse Animation Modifier

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Camera Placeholder

private struct CameraPlaceholderView: View {
    @Binding var photos: [UIImage]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(CurrentsTheme.accent.opacity(0.5))

                Text("Camera")
                    .font(.title2.bold())

                Text("Camera integration coming soon.\nPhotos taken here will be attached to your trip.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Simulate capturing a placeholder image
                Button {
                    if let placeholder = createPlaceholderImage() {
                        photos.append(placeholder)
                    }
                    dismiss()
                } label: {
                    Label("Capture Test Photo", systemImage: "camera.shutter.button")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(CurrentsTheme.accent)
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createPlaceholderImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        return renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.lightGray,
                .font: UIFont.systemFont(ofSize: 20, weight: .medium)
            ]
            let text = "Trip Photo" as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (400 - textSize.width) / 2, y: (400 - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }
}
