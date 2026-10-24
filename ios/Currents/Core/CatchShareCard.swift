import SwiftUI

/// Generates a shareable image card for a catch, in the same card family as
/// the spot, trip and tournament cards: the photo as the cover, then the
/// species, its numbers and the wordmark footer.
@MainActor
enum CatchShareCard {

    /// Render a shareable catch card (1080 by 1350, Instagram 4:5). Pass
    /// `isArtwork` when `photo` is the species art standing in for a photo,
    /// so it is fitted on its colour instead of cropped.
    static func render(detail: CatchDetail, photo: UIImage, isArtwork: Bool = false) async -> UIImage? {
        ShareCardRenderer.image(CatchShareCardView(detail: detail, photo: photo, isArtwork: isArtwork))
    }
}

// MARK: - Card

private struct CatchShareCardView: View {
    let detail: CatchDetail
    let photo: UIImage
    let isArtwork: Bool

    private var record: Catch { detail.catchRecord }
    private var imperial: Bool { Units.isImperial }

    /// "12 October 2026, Blue Lagoon, released"
    private var overLine: String {
        var parts = [LogbookFormat.fullDate(record.caughtAt)]
        if let spot = detail.spot { parts.append(spot.name) }
        if record.released { parts.append(parts.count == 1 ? "Released" : "released") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ShareCardCanvas {
            cover
            Text(overLine)
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, DS.Space.s4)
            Text(detail.species?.commonName ?? "Unknown species")
                .font(.title.bold())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let scientific = detail.species?.scientificName, !scientific.isEmpty {
                Text(scientific)
                    .font(.callout.italic())
                    .foregroundStyle(Color.dsText2)
                    .lineLimit(1)
            }
            stats
                .padding(.top, DS.Space.s3)
            Spacer(minLength: DS.Space.s3)
            ShareCardFooter(detail: "Tight lines")
        }
    }

    @ViewBuilder
    private var stats: some View {
        let length = record.lengthCm.map { Units.length(cm: $0, imperial: imperial) }
        let weight = record.weightKg.map { Units.weight(kg: $0, imperial: imperial) }
        let score = record.forecastScoreAtCapture
        if length != nil || weight != nil || score != nil {
            HStack(spacing: DS.Space.s2) {
                if let length { ShareCardStat(value: length, label: "Length") }
                if let weight { ShareCardStat(value: weight, label: "Weight") }
                if let score { ShareCardStat(value: "\(score)", label: "Bite score") }
            }
        }
    }

    /// The photo cropped to fill, or the species art fitted on its colour.
    private var cover: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .overlay {
                if isArtwork {
                    ZStack {
                        Color.dsFill
                        (detail.species?.artTint ?? DS.accent).opacity(0.3)
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .padding(DS.Space.s5)
                    }
                } else {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
