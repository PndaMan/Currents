import SwiftUI

struct CatchComparisonView: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var leftCatch: CatchDetail?
    @State private var rightCatch: CatchDetail?

    private var isSelectingLeft: Bool { leftCatch == nil }
    private var isSelectingRight: Bool { leftCatch != nil && rightCatch == nil }
    private var bothSelected: Bool { leftCatch != nil && rightCatch != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                if bothSelected, let left = leftCatch, let right = rightCatch {
                    comparisonContent(left: left, right: right)
                } else {
                    selectionHeader
                    catchSelectionList
                }
            }
            .padding()
        }
        .navigationTitle("Compare Catches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if bothSelected {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        withAnimation {
                            leftCatch = nil
                            rightCatch = nil
                        }
                    }
                    .foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
        .task {
            catches = (try? appState.catchRepository.fetchAll()) ?? []
        }
    }

    // MARK: - Selection UI

    private var selectionHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: isSelectingLeft ? "1.circle.fill" : "2.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(CurrentsTheme.accent)
            Text(isSelectingLeft ? "Select First Catch" : "Select Second Catch")
                .font(.headline)
            Text(isSelectingLeft
                 ? "Choose a catch to compare"
                 : "Now pick another catch to compare against")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let left = leftCatch {
                HStack(spacing: 8) {
                    selectedCatchPill(detail: left, label: "First")
                    Button {
                        withAnimation { leftCatch = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, CurrentsTheme.paddingM)
    }

    private func selectedCatchPill(detail: CatchDetail, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "fish.fill")
                .foregroundStyle(CurrentsTheme.accent)
            Text(detail.species?.commonName ?? "Unknown")
                .font(.subheadline.bold())
            Text("(\(label))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassPill()
    }

    private var catchSelectionList: some View {
        LazyVStack(spacing: 10) {
            ForEach(catches, id: \.catchRecord.id) { detail in
                // Don't show the already-selected left catch
                if detail.catchRecord.id != leftCatch?.catchRecord.id {
                    Button {
                        withAnimation {
                            if isSelectingLeft {
                                leftCatch = detail
                            } else if isSelectingRight {
                                rightCatch = detail
                            }
                        }
                    } label: {
                        catchSelectionRow(detail: detail)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func catchSelectionRow(detail: CatchDetail) -> some View {
        HStack(spacing: 14) {
            if let photoPath = detail.catchRecord.allPhotoPaths.first,
               let image = PhotoManager.load(photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CurrentsTheme.accent.opacity(0.15))
                    Image(systemName: "fish.fill")
                        .font(.title3)
                        .foregroundStyle(CurrentsTheme.accent)
                }
                .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if let weight = detail.catchRecord.weightKg {
                        Text(String(format: "%.2f kg", weight))
                            .font(.caption)
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                    if let length = detail.catchRecord.lengthCm {
                        Text(String(format: "%.1f cm", length))
                            .font(.caption)
                            .foregroundStyle(CurrentsTheme.accent.opacity(0.7))
                    }
                }
            }

            Spacer()

            Text(detail.catchRecord.caughtAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
    }

    // MARK: - Comparison Content

    @ViewBuilder
    private func comparisonContent(left: CatchDetail, right: CatchDetail) -> some View {
        // Photos
        photoComparison(left: left, right: right)

        // Species
        comparisonRow(title: "Species") {
            Text(left.species?.commonName ?? "Unknown")
                .font(.subheadline.bold())
        } rightContent: {
            Text(right.species?.commonName ?? "Unknown")
                .font(.subheadline.bold())
        }

        // Weight
        comparisonRow(title: "Weight") {
            weightLabel(value: left.catchRecord.weightKg,
                        isHighlighted: isBetter(left: left.catchRecord.weightKg,
                                                right: right.catchRecord.weightKg))
        } rightContent: {
            weightLabel(value: right.catchRecord.weightKg,
                        isHighlighted: isBetter(left: right.catchRecord.weightKg,
                                                right: left.catchRecord.weightKg))
        }

        // Length
        comparisonRow(title: "Length") {
            lengthLabel(value: left.catchRecord.lengthCm,
                        isHighlighted: isBetter(left: left.catchRecord.lengthCm,
                                                right: right.catchRecord.lengthCm))
        } rightContent: {
            lengthLabel(value: right.catchRecord.lengthCm,
                        isHighlighted: isBetter(left: right.catchRecord.lengthCm,
                                                right: left.catchRecord.lengthCm))
        }

        // Date
        comparisonRow(title: "Date") {
            Text(left.catchRecord.caughtAt, style: .date)
                .font(.subheadline)
        } rightContent: {
            Text(right.catchRecord.caughtAt, style: .date)
                .font(.subheadline)
        }

        // Spot
        comparisonRow(title: "Spot") {
            Label(left.spot?.name ?? "Unknown", systemImage: "mappin")
                .font(.subheadline)
                .lineLimit(1)
        } rightContent: {
            Label(right.spot?.name ?? "Unknown", systemImage: "mappin")
                .font(.subheadline)
                .lineLimit(1)
        }

        // Forecast Score
        comparisonRow(title: "Forecast Score") {
            scoreBadge(score: left.catchRecord.forecastScoreAtCapture)
        } rightContent: {
            scoreBadge(score: right.catchRecord.forecastScoreAtCapture)
        }

        // Released
        comparisonRow(title: "Released") {
            releasedBadge(released: left.catchRecord.released)
        } rightContent: {
            releasedBadge(released: right.catchRecord.released)
        }
    }

    // MARK: - Photo Comparison

    private func photoComparison(left: CatchDetail, right: CatchDetail) -> some View {
        HStack(spacing: 12) {
            catchPhoto(detail: left)
            catchPhoto(detail: right)
        }
    }

    private func catchPhoto(detail: CatchDetail) -> some View {
        Group {
            if let photoPath = detail.catchRecord.allPhotoPaths.first,
               let image = PhotoManager.load(photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius)
                        .fill(CurrentsTheme.accent.opacity(0.1))
                    VStack(spacing: 8) {
                        Image(systemName: "fish.fill")
                            .font(.largeTitle)
                            .foregroundStyle(CurrentsTheme.accent.opacity(0.4))
                        Text("No Photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
    }

    // MARK: - Comparison Row

    private func comparisonRow<L: View, R: View>(
        title: String,
        @ViewBuilder leftContent: () -> L,
        @ViewBuilder rightContent: () -> R
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                leftContent()
                    .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 24)

                rightContent()
                    .frame(maxWidth: .infinity)
            }
        }
        .glassCard()
    }

    // MARK: - Metric Labels

    private func weightLabel(value: Double?, isHighlighted: Bool) -> some View {
        Group {
            if let value {
                Text(String(format: "%.2f kg", value))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(isHighlighted ? CurrentsTheme.accent : .primary)
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lengthLabel(value: Double?, isHighlighted: Bool) -> some View {
        Group {
            if let value {
                Text(String(format: "%.1f cm", value))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(isHighlighted ? CurrentsTheme.accent : .primary)
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scoreBadge(score: Int?) -> some View {
        Group {
            if let score {
                Text("\(score)")
                    .font(.subheadline.bold().monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(CurrentsTheme.scoreColor(score).opacity(0.2))
                    .foregroundStyle(CurrentsTheme.scoreColor(score))
                    .clipShape(Capsule())
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func releasedBadge(released: Bool) -> some View {
        Label(released ? "Released" : "Kept",
              systemImage: released ? "arrow.uturn.backward" : "bag.fill")
            .font(.subheadline)
            .foregroundStyle(released ? CurrentsTheme.accent : .primary)
    }

    // MARK: - Helpers

    /// Returns true if `left` is strictly greater than `right` (both non-nil).
    private func isBetter(left: Double?, right: Double?) -> Bool {
        guard let l = left, let r = right else { return false }
        return l > r
    }
}
