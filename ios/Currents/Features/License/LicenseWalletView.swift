import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Wallet of fishing licences and permits with document storage, OCR-assisted
/// detail capture, and expiry reminders. Pushed from Profile (`AppRoute.licenses`).
struct LicenseWalletView: View {
    @Environment(AppState.self) private var appState
    @State private var licenses: [FishingLicense] = []
    @State private var showingAdd = false
    @State private var didLoad = false
    @State private var titleShown = false
    @State private var toDelete: FishingLicense?

    /// The licence closest to expiring within 30 days, for the notice.
    private var expiringSoon: FishingLicense? {
        licenses
            .filter { ($0.daysUntilExpiry ?? -1) >= 0 && ($0.daysUntilExpiry ?? 99) <= 30 }
            .min { ($0.daysUntilExpiry ?? 0) < ($1.daysUntilExpiry ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DetailHeader(title: "Licences", subtitle: "Angling licences and permits")

                if didLoad && licenses.isEmpty {
                    ContentUnavailableView {
                        Label("No licences yet", systemImage: "person.text.rectangle")
                    } description: {
                        Text("Keep your angling licences and permits here. Currents reads the expiry date and reminds you before it lapses.")
                    } actions: {
                        Button("Add licence") { showingAdd = true }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    }
                    .padding(.top, DS.Space.s6)
                } else {
                    if let soon = expiringSoon, let days = soon.daysUntilExpiry {
                        NavigationLink(value: LicenseRoute(id: soon.id)) {
                            PFNotice(systemImage: "calendar.badge.clock", tint: .dsScoreLow,
                                     title: days == 0 ? "\(soon.title) expires today"
                                        : (days == 1 ? "\(soon.title) expires tomorrow" : "\(soon.title) expires in \(days) days"),
                                     message: "Renew it before your next trip.") {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.dsText3)
                            }
                        }
                        .buttonStyle(.dim)
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(licenses) { license in
                            NavigationLink(value: LicenseRoute(id: license.id)) {
                                LicenseRow(license: license)
                            }
                            .buttonStyle(.dim)
                            .contextMenu {
                                Button(role: .destructive) { toDelete = license } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if !licenses.isEmpty {
                        PFFootnote("Stored on this phone only. Works with no signal, so you can show it at the water.")
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(.green)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Licences", shown: titleShown)
        .navigationDestination(for: LicenseRoute.self) { route in
            if let license = licenses.first(where: { $0.id == route.id }) {
                LicenseDetailView(license: license) { reload() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add licence")
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            AddLicenseSheet()
        }
        .confirmationDialog("Delete this licence?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: toDelete) { license in
            Button("Delete licence", role: .destructive) { delete(license) }
        } message: { _ in
            Text("The licence, its document and its reminders are removed from this phone.")
        }
        .task { reload() }
    }

    private func reload() {
        licenses = (try? appState.licenseRepository.fetchAll()) ?? []
        didLoad = true
        Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: licenses) }
    }

    private func delete(_ license: FishingLicense) {
        try? appState.licenseRepository.delete(license)
        Haptics.warning()
        ToastCenter.shared.show("Licence deleted", style: .info, haptic: false)
        reload()
    }
}

struct LicenseRoute: Hashable {
    let id: String
}

// MARK: - Expiry status

extension FishingLicense {
    /// Short status for rows and the profile: Expired, Expires today, 12 days
    /// left, Valid until 3 Mar 2027.
    var expiryStatus: (text: String, color: Color)? {
        guard let days = daysUntilExpiry, let expiryDate else { return nil }
        if days < 0 { return ("Expired", .dsScoreSlow) }
        if days == 0 { return ("Expires today", .dsScoreSlow) }
        if days <= 30 { return (days == 1 ? "1 day left" : "\(days) days left", .dsScoreLow) }
        return ("Valid until \(expiryDate.formatted(date: .abbreviated, time: .omitted))", .dsText2)
    }

    /// Freshwater or marine look for the row card, guessed from the type and title.
    var isMarine: Bool {
        let text = "\(title) \(licenseType ?? "")".lowercased()
        return ["marine", "sea", "coastal", "salt", "ocean"].contains { text.contains($0) }
    }
}

// MARK: - Row

struct LicenseRow: View {
    let license: FishingLicense

    var body: some View {
        HStack(spacing: 14) {
            ThumbView(systemImage: license.isMarine ? "water.waves" : "tree.fill",
                      tint: license.isMarine ? .blue : .green, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(license.title)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                if let sub = license.region ?? license.licenseType, !sub.isEmpty {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
                if let status = license.expiryStatus {
                    Text(status.text)
                        .font(.footnote)
                        .foregroundStyle(status.color)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.dsText3)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail

struct LicenseDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var license: FishingLicense
    var onChange: () -> Void
    @State private var showingEdit = false
    @State private var showingRenewal = false
    @State private var showingDeleteConfirm = false
    @State private var showingDocument = false
    @State private var titleShown = false

    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { result.append((label, value)) }
        }
        add("Type", license.licenseType)
        add("Holder", license.holderName)
        add("Number", license.licenseNumber)
        add("Region", license.region)
        add("Issued", license.issueDate.map { $0.formatted(date: .abbreviated, time: .omitted) })
        add("Expires", license.expiryDate.map { $0.formatted(date: .abbreviated, time: .omitted) })
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    DetailHeader(over: license.licenseType, title: license.title,
                                 subtitle: license.expiryStatus?.text)
                    ActionTriple {
                        Button { showingRenewal = true } label: {
                            Label("Add renewal", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(ActionTileStyle(.primary))
                        Button { showingEdit = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(ActionTileStyle())
                        Button { showingDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(ActionTileStyle(.destructive))
                    }
                }

                if license.fileName != nil {
                    Button { showingDocument = true } label: {
                        LicenseDocumentView(license: license)
                            .frame(height: 320)
                            .frame(maxWidth: .infinity)
                            .background(Color.dsFill)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Label("View full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.regularMaterial, in: Capsule()) // ui-lint: allow, label floats over the licence document
                                    .padding(10)
                            }
                    }
                    .buttonStyle(.dim)
                    .padding(.horizontal, DS.gutter)
                    .accessibilityLabel("View the licence document full screen")
                }

                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Details")
                        PFKeyValueCard(rows: rows)
                    }
                }

                if let notes = license.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Notes")
                        Text(notes)
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.s4)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                    }
                }

                if license.expiryDate != nil {
                    PFFootnote("Reminders come a month, two weeks, a week and three days before it expires, and on the day.")
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(license.isMarine ? .blue : .green)
        .pfTrackScroll($titleShown, threshold: 80)
        .pfScrollTitle(license.title, shown: titleShown)
        .sheet(isPresented: $showingEdit, onDismiss: refresh) {
            AddLicenseSheet(editing: license)
        }
        .sheet(isPresented: $showingRenewal, onDismiss: onChange) {
            AddLicenseSheet(renewing: license)
        }
        .confirmationDialog("Delete this licence?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete licence", role: .destructive) {
                try? appState.licenseRepository.delete(license)
                Haptics.warning()
                ToastCenter.shared.show("Licence deleted", style: .info, haptic: false)
                onChange()
                dismiss()
            }
        } message: {
            Text("The licence, its document and its reminders are removed from this phone.")
        }
        .fullScreenCover(isPresented: $showingDocument) {
            LicenseDocumentFullScreen(license: license)
        }
    }

    private func refresh() {
        license = (try? appState.licenseRepository.fetchAll())?.first { $0.id == license.id } ?? license
        onChange()
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
            Rectangle().fill(Color.dsFill)
            Image(systemName: "doc.text.image").font(.largeTitle).foregroundStyle(.dsText2)
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

// MARK: - Fullscreen document viewer

/// Full-screen, zoomable view of the licence document: the whole PDF (scrolls
/// and pinch-zooms) or the photo (pinch-zooms), with a Done button.
struct LicenseDocumentFullScreen: View {
    let license: FishingLicense
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let name = license.fileName {
                    let url = LicenseFileStore.url(for: name)
                    if license.fileKind == "pdf" {
                        PDFFullView(url: url).ignoresSafeArea(edges: .bottom)
                    } else if let img = UIImage(contentsOfFile: url.path) {
                        ZoomableImage(image: img)
                    } else {
                        ContentUnavailableView("Can't open the document", systemImage: "doc.text.image")
                    }
                } else {
                    ContentUnavailableView("No document", systemImage: "doc.text.image")
                }
            }
            .navigationTitle(license.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// PDF viewer configured for full-document reading (all pages, zoomable).
private struct PDFFullView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.maxScaleFactor = 6
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(url: url) }
    }
}

// Full-document image zoom reuses `ZoomableImage` from FullscreenPhotoViewer.
