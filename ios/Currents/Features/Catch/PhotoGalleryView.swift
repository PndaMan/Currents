import SwiftUI

struct PhotoGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var selectedDetail: CatchDetail?

    private var catchesWithPhotos: [CatchDetail] {
        catches.filter { $0.catchRecord.photoPath != nil }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if catchesWithPhotos.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Photos from your catches will appear here")
                )
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(catchesWithPhotos, id: \.catchRecord.id) { detail in
                        if let photoPath = detail.catchRecord.photoPath,
                           let image = PhotoManager.load(photoPath) {
                            Button {
                                selectedDetail = detail
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .overlay(alignment: .bottomLeading) {
                                        if let species = detail.species?.commonName {
                                            Text(species)
                                                .font(.caption2.bold())
                                                .padding(4)
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .padding(4)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Gallery")
        .sheet(item: $selectedDetail) { detail in
            NavigationStack {
                CatchDetailView(detail: detail)
            }
            .presentationDetents([.large])
        }
        .task {
            catches = (try? appState.catchRepository.fetchAll(limit: 500)) ?? []
        }
    }
}

extension CatchDetail: Identifiable {
    var id: String { catchRecord.id }
}
