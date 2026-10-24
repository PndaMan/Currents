import StoreKit
import SwiftUI

/// Pages pushed from About.
enum AboutRoute: Hashable {
    case tips
    case acknowledgements
}

/// Leave a tip: one row per tip on sale, with the App Store's own name and
/// price, then the Patron badge any tip earns.
struct TipJarView: View {
    @Environment(\.purchase) private var purchase

    private var jar: TipJar { TipJar.shared }

    var body: some View {
        TodayPage("Leave a tip", subtitle: "Tips help keep Currents free.") {
            if jar.products.isEmpty {
                InlineEmpty(systemImage: "heart", text: "Tips are not available right now. Try again later.")
            } else {
                CardSection(note: note) {
                    ForEach(Array(jar.products.enumerated()), id: \.element.id) { index, product in
                        TipRow(product: product, systemImage: Self.icon(index),
                               isBuying: jar.purchasing == product.id,
                               isEnabled: jar.purchasing == nil && jar.canPay) {
                            Task { await jar.buy(product, with: purchase) }
                        }
                    }
                }
            }
            if let patron = TitleFlair.resolve("Patron") {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(isPatron ? "Your badge" : "A small thank you")
                    TitleBadge(flair: patron, subtitle: "Thank you so much")
                    SectionFootnote(badgeNote)
                }
            }
        }
        .task {
            if jar.state != .loaded { await jar.load() }
        }
    }

    /// Reads the observed count so the page updates the moment a tip lands.
    private var isPatron: Bool { jar.tipCount > 0 || BadgeDefinition.isSupporter }

    /// Under the example badge: what earns it, or that it is already yours.
    private var badgeNote: String {
        isPatron
            ? "It's on your profile. You can wear it as your title."
            : "Any tip, whatever the size, adds this mythic badge to your profile."
    }

    /// The thank-you line, or why tips cannot go through right now.
    private var note: String? {
        if !jar.canPay { return "Purchases are turned off on this phone." }
        if jar.awaitingApproval { return "Your tip is waiting for approval." }
        switch jar.tipCount {
        case 0: return nil
        case 1: return "Thank you for your tip. It means a lot."
        default: return "Thank you for your \(jar.tipCount) tips. They mean a lot."
        }
    }

    private static func icon(_ index: Int) -> String {
        ["cup.and.saucer.fill", "fork.knife", "gift.fill"][min(index, 2)]
    }
}

/// One tip: its name from the App Store and a price button.
private struct TipRow: View {
    let product: Product
    let systemImage: String
    let isBuying: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                TintIcon(systemImage: systemImage, tint: .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .foregroundStyle(.dsText)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    // Keeps the width while the spinner shows.
                    Text(product.displayPrice).hidden()
                    if isBuying {
                        ProgressView()
                    } else {
                        Text(product.displayPrice)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.dsOnPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(Color.dsPrimaryButton, in: Capsule())
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.displayName), \(spokenPrice)")
        .accessibilityHint(isBuying ? "Buying" : "Opens the App Store purchase sheet")
        .accessibilityAddTraits(.isButton)
    }

    /// "18.99 South African rand" rather than "R 18,99".
    private var spokenPrice: String {
        product.price.formatted(product.priceFormatStyle.presentation(.fullName))
    }
}
