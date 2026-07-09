import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Wallet of fishing licences / permits with document storage, OCR-assisted
/// detail capture, and expiry reminders.
struct LicenseWalletView: View {
    @Environment(AppState.self) private var appState
    @State private var licenses: [FishingLicense] = []
    @State private var showingAdd = false

    var body: some View {
        Group {
            if licenses.isEmpty {
                ContentUnavailableView {
                    Label("No Licences Yet", systemImage: "doc.text.image")
                } description: {
                    Text("Add your fishing licence or permit — Currents reads the expiry and reminds you before it lapses.")
                } actions: {
                    Button("Add Licence") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                        .tint(CurrentsTheme.accent)
                }
            } else {
                List {
                    ForEach(licenses) { license in
                        NavigationLink {
                            LicenseDetailView(license: license) { reload() }
                        } label: {
                            LicenseRow(license: license)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Licences & Permits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            AddLicenseSheet()
        }
        .task { reload() }
    }

    private func reload() {
        licenses = (try? appState.licenseRepository.fetchAll()) ?? []
        Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: licenses) }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? appState.licenseRepository.delete(licenses[index])
        }
        reload()
    }
}

// MARK: - Row

struct LicenseRow: View {
    let license: FishingLicense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: license.fileKind == "pdf" ? "doc.richtext" : "photo")
                .font(.title2)
                .foregroundStyle(CurrentsTheme.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(license.title).font(.subheadline.bold())
                if let region = license.region, !region.isEmpty {
                    Text(region).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            expiryBadge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var expiryBadge: some View {
        if let days = license.daysUntilExpiry {
            let (text, color): (String, Color) = {
                if days < 0 { return ("Expired", .red) }
                if days == 0 { return ("Expires today", .red) }
                if days <= 30 { return ("\(days)d left", .orange) }
                return ("\(days)d left", .secondary)
            }()
            Text(text)
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
    }
}

// MARK: - Detail

struct LicenseDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var license: FishingLicense
    var onChange: () -> Void
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                LicenseDocumentView(license: license)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Type", license.licenseType)
                    detailRow("Holder", license.holderName)
                    detailRow("Number", license.licenseNumber)
                    detailRow("Region", license.region)
                    detailRow("Issued", license.issueDate.map { $0.formatted(date: .abbreviated, time: .omitted) })
                    detailRow("Expires", license.expiryDate.map { $0.formatted(date: .abbreviated, time: .omitted) })
                    if let notes = license.notes, !notes.isEmpty {
                        detailRow("Notes", notes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Licence", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(license.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: {
            license = (try? appState.licenseRepository.fetchAll())?.first { $0.id == license.id } ?? license
            onChange()
        }) {
            AddLicenseSheet(editing: license)
        }
        .alert("Delete Licence?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.licenseRepository.delete(license)
                onChange()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text(value).font(.subheadline)
                Spacer()
            }
        }
    }
}

// MARK: - Document display

struct LicenseDocumentView: View {
    let license: FishingLicense

    var body: some View {
        if let name = license.fileName {
            let url = LicenseFileStore.url(for: name)
            if license.fileKind == "pdf" {
                PDFKitView(url: url)
            } else if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "doc.text.image").font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(url: url) }
    }
}
