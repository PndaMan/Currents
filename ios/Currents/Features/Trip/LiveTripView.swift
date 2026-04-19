import SwiftUI
import CoreLocation
import PhotosUI

struct LiveTripView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var showingLogCatch = false
    @State private var showingEndConfirm = false
    @State private var nearbySpot: Spot?
    @State private var animateGradient = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var tripPhotos: [UIImage] = []

    private func timerString(for date: Date) -> String {
        let elapsed = Int(date.timeIntervalSince(trip.startDate))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Animated gradient background
            animatedBackground

            ScrollView {
                VStack(spacing: 18) {
                    liveTimerCard
                    weatherForecastCard
                    if let spot = nearbySpot {
                        nearbySpotCard(spot)
                    }
                    quickActionsRow
                    if !tripPhotos.isEmpty {
                        tripPhotosStrip
                    }
                    tripFeedSection
                    endTripButton
                }
                .padding()
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
        .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
            Task { await loadCatches() }
        }) {
            LogCatchView()
        }
        .onChange(of: photoPickerItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .alert("End Trip?", isPresented: $showingEndConfirm) {
            Button("End Trip", role: .destructive) { endTrip() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will finish the current session and save your trip summary.")
        }
    }

    // MARK: - Animated Background

    private var animatedBackground: some View {
        LinearGradient(
            colors: [
                CurrentsTheme.accent.opacity(0.4),
                Color.black.opacity(0.85),
                CurrentsTheme.accent.opacity(0.2)
            ],
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .overlay(
            // Subtle wave shimmer
            Color.black.opacity(0.3).ignoresSafeArea()
        )
    }

    // MARK: - Live Timer Card

    private var liveTimerCard: some View {
        TimelineView(.periodic(from: trip.startDate, by: 1)) { context in
            VStack(spacing: 12) {
                // LIVE pill with pulsing dot
                HStack(spacing: 6) {
                    PulsingDot(color: CurrentsTheme.accent)
                    Text("LIVE SESSION")
                        .font(.caption.bold())
                        .tracking(1.5)
                        .foregroundStyle(CurrentsTheme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(CurrentsTheme.accent.opacity(0.15))
                .clipShape(Capsule())

                // Big timer
                Text(timerString(for: context.date))
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: CurrentsTheme.accent.opacity(0.6), radius: 12)
                    .contentTransition(.numericText())

                Text("Trip Duration")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(CurrentsTheme.accent.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: CurrentsTheme.accent.opacity(0.2), radius: 20)
        }
    }

    // MARK: - Weather + Forecast Card

    private var weatherForecastCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONDITIONS")
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.5))

                if let w = weather {
                    HStack(spacing: 6) {
                        WeatherIcon(condition: w.condition)
                            .font(.title2)
                            .foregroundStyle(.white)
                        Text("\(Int(w.temperatureC))°")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    Label("\(Int(w.windSpeedKmh)) km/h", systemImage: "wind")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if let waterTemp = w.waterTempC {
                        Label("\(Int(waterTemp))° water", systemImage: "water.waves")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Text("BITE")
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.5))
                if let f = forecast {
                    ZStack {
                        Circle()
                            .stroke(CurrentsTheme.accent.opacity(0.2), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(f.score) / 100)
                            .stroke(CurrentsTheme.scoreColor(f.score),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.6), value: f.score)
                        Text("\(f.score)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 70, height: 70)
                } else {
                    ProgressView()
                        .tint(CurrentsTheme.accent)
                        .frame(width: 70, height: 70)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Nearby Spot

    private func nearbySpotCard(_ spot: Spot) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CurrentsTheme.accent.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(CurrentsTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Near: \(spot.name)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Catches will link to this spot")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CurrentsTheme.accent)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                showingLogCatch = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "fish.fill")
                        .font(.title2)
                    Text("Log Catch")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [CurrentsTheme.accent, CurrentsTheme.accent.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: CurrentsTheme.accent.opacity(0.4), radius: 8, y: 4)
            }

            PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                    Text("Trip Photo")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(CurrentsTheme.accent.opacity(0.4), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Trip Photos Strip

    private var tripPhotosStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundStyle(CurrentsTheme.accent)
                Text("Trip Memories")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(tripPhotos.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tripPhotos.indices, id: \.self) { index in
                        Image(uiImage: tripPhotos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Trip Feed

    private var tripFeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundStyle(CurrentsTheme.accent)
                Text("Trip Feed")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(catches.count) catch\(catches.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if catches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fish")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No catches yet — get out there!")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(catches, id: \.catchRecord.id) { detail in
                    catchFeedRow(detail)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func catchFeedRow(_ detail: CatchDetail) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CurrentsTheme.accent.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "fish.fill")
                    .foregroundStyle(CurrentsTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.species?.commonName ?? "Catch")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let w = detail.catchRecord.weightKg {
                        Text(String(format: "%.1fkg", w))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let l = detail.catchRecord.lengthCm {
                        Text(String(format: "%.0fcm", l))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Spacer()
            Text(detail.catchRecord.caughtAt, style: .time)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - End Trip

    private var endTripButton: some View {
        Button(role: .destructive) {
            showingEndConfirm = true
        } label: {
            Label("End Trip", systemImage: "stop.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Logic

    private func loadData() async {
        await loadCatches()
        let coord = appState.locationManager.currentLocation?.coordinate ??
            CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        let w = await WeatherService.shared.current(for: coord)
        weather = w
        forecast = ForecastEngine.forecast(
            date: .now,
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC,
            windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        detectNearbySpot(coordinate: coord)
    }

    private func loadCatches() async {
        catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                tripPhotos.append(img)
            }
        }
        photoPickerItems = []
    }

    private func detectNearbySpot(coordinate: CLLocationCoordinate2D) {
        guard let allSpots = try? appState.spotRepository.fetchAll() else { return }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var closest: Spot?
        var closestDist: CLLocationDistance = .greatestFiniteMagnitude
        for spot in allSpots {
            let d = here.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
            if d < 500 && d < closestDist {
                closestDist = d
                closest = spot
            }
        }
        nearbySpot = closest
    }

    private func endTrip() {
        var updated = trip
        updated.endDate = .now
        try? appState.tripRepository.save(&updated)
        dismiss()
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .shadow(color: color, radius: 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.4
                }
            }
    }
}
