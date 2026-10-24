import StoreKit
import SwiftUI

/// Pages pushed from About.
enum AboutRoute: Hashable {
    case tips
    case acknowledgements
}

/// Leave a tip: one row per tip on sale, with its name, one line and the
/// App Store price, then the Patron badge any tip earns.
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
                        let copy = TipCopy.of(product, index: index)
                        TipRow(product: product, name: copy.name, line: copy.line, systemImage: copy.icon,
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
                        .padding(.horizontal, DS.gutter)
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
}

/// The words for each tip, kept here rather than taken from App Store
/// Connect, so they read like the rest of the app. Matched on the product
/// ids in `TipJar.productIds`, cheapest first.
@MainActor
private struct TipCopy {
    let name: String
    let line: String
    let icon: String

    private static let all = [
        TipCopy(name: "Small tip", line: "Buys the developer a coffee", icon: "cup.and.saucer.fill"),
        TipCopy(name: "Medium tip", line: "Buys the developer lunch", icon: "fork.knife"),
        TipCopy(name: "Large tip", line: "A generous thank you", icon: "gift.fill"),
    ]

    /// The copy for a tip, or the store's own name for an id not listed
    /// here, with the icon for its place in the list.
    static func of(_ product: Product, index: Int) -> TipCopy {
        if let i = TipJar.productIds.firstIndex(of: product.id), all.indices.contains(i) {
            return all[i]
        }
        let icon = all[min(max(0, index), all.count - 1)].icon
        return TipCopy(name: product.displayName, line: "", icon: icon)
    }
}

/// One tip: its name, one line and a price button.
private struct TipRow: View {
    let product: Product
    let name: String
    let line: String
    let systemImage: String
    let isBuying: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                TintIcon(systemImage: systemImage, tint: .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.dsText)
                    if !line.isEmpty {
                        Text(line)
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
        .accessibilityLabel("\(name), \(spokenPrice)")
        .accessibilityHint(isBuying ? "Buying" : "Opens the App Store purchase sheet")
        .accessibilityAddTraits(.isButton)
    }

    /// "18.99 South African rand" rather than "R 18,99".
    private var spokenPrice: String {
        product.price.formatted(product.priceFormatStyle.presentation(.fullName))
    }
}
