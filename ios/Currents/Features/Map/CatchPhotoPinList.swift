import SwiftUI

/// Catches from a photo stack that zooming cannot split, newest first. Drives
/// `.sheet(item:)` in MapTab.
struct CatchStackSelection: Identifiable {
    let id = UUID()
    let catches: [CatchDetail]
}

/// Every catch in a stack logged on the same few metres, newest first, as
/// Logbook rows. Tapping a row hands the catch back and closes the sheet, so
/// the map can open it the way a single catch pin does.
struct CatchStackSheet: View {
    let catches: [CatchDetail]
    var onOpen: (CatchDetail) -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        catches.count == 1 ? "1 catch here" : "\(catches.count) catches here"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if catches.isEmpty {
                        InlineEmpty(systemImage: "fish",
                                    text: "No catches here. Catches you log at this place show up here.")
                            .padding(.top, DS.Space.s2)
                    } else {
                        ForEach(catches) { detail in
                            Button {
                                onOpen(detail)
                                dismiss()
                            } label: {
                                row(detail)
                            }
                            .buttonStyle(.dsRow)
                            .accessibilityHint("Opens this catch")
                        }
                    }
                }
                .padding(.vertical, DS.Space.s2)
                .pageWidth()
            }
            .detailScrollEdge()
            .background(Color.dsBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton()
                }
            }
        }
        .dsSheet([.medium, .large])
    }

    /// The Logbook's catch row: day over the species, size and release below.
    private func row(_ detail: CatchDetail) -> some View {
        let record = detail.catchRecord
        var subtitle = LogbookFormat.size(record) ?? ""
        if record.released { subtitle += subtitle.isEmpty ? "Released" : ", released" }
        return ArtRow(over: LogbookFormat.relativeDay(record.caughtAt),
                      title: detail.species?.commonName ?? "Unknown species",
                      subtitle: subtitle,
                      chevron: true) {
            CatchThumb(detail: detail)
        }
    }
}
