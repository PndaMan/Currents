import SwiftUI
import PDFKit

/// Licences and permits, each shown by its own document (the photo, or the
/// first page of the PDF), with OCR-assisted details and expiry reminders.
/// Pushed from Profile (`AppRoute.licenses`).
struct LicenseWalletView: View {
    @Environment(AppState.self) private var appState
    @State private var licenses: [FishingLicense] = []
    @State private var showingAdd = false
    @State private var didLoad = false
    @State private var titleShown = false
    @State private var toDelete: FishingLicense?
    @State private var opened: LicenseRoute?

    /// Still valid or undated, soonest expiry first (the repository's order).
    private var current: [FishingLicense] { licenses.filter { !$0.isExpired } }
    /// Kept apart, the way Wallet keeps expired passes out of the way.
    private var expired: [FishingLicense] { licenses.filter(\.isExpired) }

    var body: some View {
        List {
            DetailHeader(title: "Licences", subtitle: summary)
                .padding(.bottom, DS.Space.s2)
                .dsListRow()
            if didLoad && licenses.isEmpty {
                emptyState
                    .padding(.top, DS.Space.s4)
                    .dsListRow()
            }
            if !current.isEmpty {
                // Rows, not section headers: plain-list headers pin and
                // draw over the rows on this clear background.
                Section {
                    rows(current)
                }
            }
            if !expired.isEmpty {
                Section {
                    SectionTitle("Expired", detail: "\(expired.count)")
                        .padding(.top, DS.Space.s5)
                        .dsListRow()
                    rows(expired)
                }
            }
        }
        .dsPlainList()
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Licences", shown: titleShown)
        .navigationDestination(item: $opened) { route in
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

    /// One line under the title: what needs doing, or how many are kept.
    private var summary: String? {
        guard didLoad, !licenses.isEmpty else { return nil }
        if let due = current.first(where: \.isRenewalDue), let status = due.expiryStatus {
            return "\(due.title): \(status.text.lowercased())"
        }
        return current.count == 1 ? "1 valid licence" : "\(current.count) valid licences"
    }

    private var emptyState: some View {
        InlineEmpty(systemImage: "person.text.rectangle",
                    text: "Scan a licence to keep it here, with a reminder before it expires.",
                    actionTitle: "Add licence") { showingAdd = true }
    }

    private func rows(_ list: [FishingLicense]) -> some View {
        ForEach(list) { license in
            Button { opened = LicenseRoute(id: license.id) } label: {
                HStack(spacing: DS.Space.s3) {
                    LicenseRow(license: license)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText3)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 6)
            }
            .buttonStyle(.dsRow)
            .dsListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { toDelete = license } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button(role: .destructive) { toDelete = license } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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

// MARK: - Expiry status and document

extension FishingLicense {
    /// Width over height of a licence card (ISO ID-1, 85.6 by 54 mm). Row
    /// thumbnails crop to it so photos and PDFs line up.
    static let cardAspect: CGFloat = 85.6 / 54

    /// The stored photo or PDF, if one was added.
    var documentURL: URL? { fileName.map(LicenseFileStore.url(for:)) }

    /// Within a month of expiry or past it: renewal is the main action.
    var isRenewalDue: Bool { (daysUntilExpiry ?? Int.max) <= 30 }

    /// Short status for rows and the detail page: Expired, Expires today,
    /// 12 days left, Valid until 3 Mar 2027. Warning colours use the score
    /// ink so they stay readable on light rows.
    var expiryStatus: (text: String, color: Color)? {
        guard let days = daysUntilExpiry, let expiryDate else { return nil }
        if days < 0 { return ("Expired", DS.scoreInk(0)) }
        if days == 0 { return ("Expires today", DS.scoreInk(0)) }
        if days <= 30 { return (days == 1 ? "1 day left" : "\(days) days left", DS.scoreInk(30)) }
        return ("Valid until \(expiryDate.formatted(date: .abbreviated, time: .omitted))", .dsText2)
    }
}

// MARK: - Row

/// A licence in the list: its document cropped to card shape, the title and
/// where it stands on expiry.
struct LicenseRow: View {
    let license: FishingLicense

    private var secondary: (text: String, color: Color)? {
        if let status = license.expiryStatus { return status }
        let place = license.region ?? license.licenseType ?? ""
        return place.isEmpty ? nil : (place, .dsText2)
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            LicenseThumbnail(license: license)
            VStack(alignment: .leading, spacing: 2) {
                Text(license.title)
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                if let secondary {
                    Text(secondary.text)
                        .font(.subheadline)
                        .foregroundStyle(secondary.color)
                }
            }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
    }
}

/// The licence document cropped to a card, or a card symbol when none is stored.
struct LicenseThumbnail: View {
    let license: FishingLicense
    var width: CGFloat = 72

    var body: some View {
        // Rendered larger than the frame so a portrait PDF page or a
        // landscape photo still covers the card after cropping.
        FilePreview(url: license.documentURL, systemImage: "person.text.rectangle",
                    renderSize: width * 1.5)
            .frame(width: width, height: width / FishingLicense.cardAspect)
            .accessibilityHidden(true)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if license.fileName != nil {
                    document
                }
                DetailHeader(title: license.title, subtitle: license.expiryStatus?.text)
                actions
                    .padding(.top, DS.Space.s4)
                if license.fileName == nil {
                    CardGroup {
                        Button { showingEdit = true } label: {
                            CardRow("Add a photo or PDF", systemImage: "doc.badge.plus", tint: .blue, chevron: true)
                        }
                        .buttonStyle(.dsCardRow)
                    }
                    .padding(.top, DS.Space.s6)
                }
                LicenseFieldsSection(license: license)
                    .padding(.top, DS.Space.s6)
                if let notes = license.notes, !notes.isEmpty {
                    SectionTitle("Notes")
                        .padding(.top, DS.Space.s6)
                    Text(notes)
                        .foregroundStyle(.dsText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: license.fileName == nil ? 60 : 300)
        .pfScrollTitle(license.title, shown: titleShown)
        .sheet(isPresented: $showingEdit, onDismiss: refresh) {
            AddLicenseSheet(editing: license)
        }
        .sheet(isPresented: $showingRenewal, onDismiss: onChange) {
            AddLicenseSheet(renewing: license)
        }
        .confirmationDialog("Delete this licence?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete licence", role: .destructive) { delete() }
        } message: {
            Text("The licence, its document and its reminders are removed from this phone.")
        }
        .fullScreenCover(isPresented: $showingDocument) {
            LicenseDocumentFullScreen(license: license)
        }
    }

    /// The document itself, whole, at the top of the page. Tap for full screen.
    private var document: some View {
        Button { showingDocument = true } label: {
            FilePreview(url: license.documentURL, systemImage: "doc.text.image", renderSize: 400,
                        contentMode: .fit, cornerRadius: DS.Radius.thumb,
                        placeholderAspect: FishingLicense.cardAspect)
                .frame(maxWidth: .infinity, maxHeight: 260)
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s3)
        .accessibilityLabel(license.fileKind == "pdf" ? "Licence PDF" : "Licence photo")
        .accessibilityHint("Opens it full screen")
    }

    private var actions: some View {
        let renewalDue = license.isRenewalDue
        return ActionTriple {
            Button { showingEdit = true } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(ActionTileStyle(renewalDue ? .tonal : .primary))
            Button { showingRenewal = true } label: {
                Label("Add renewal", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ActionTileStyle(renewalDue ? .primary : .tonal))
            Button { showingDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(ActionTileStyle(.destructive))
        }
    }

    private func delete() {
        try? appState.licenseRepository.delete(license)
        Haptics.warning()
        ToastCenter.shared.show("Licence deleted", style: .info, haptic: false)
        onChange()
        dismiss()
    }

    private func refresh() {
        license = (try? appState.licenseRepository.fetchAll())?.first { $0.id == license.id } ?? license
        onChange()
    }
}

/// The licence's details as labelled rows, the facts a ranger asks for.
/// Left out entirely when nothing was filled in.
private struct LicenseFieldsSection: View {
    let license: FishingLicense

    private struct Field: Identifiable {
        let label: String
        let value: String
        var color: Color = .dsText2
        var id: String { label }
    }

    private var fields: [Field] {
        var result: [Field] = []
        func add(_ label: String, _ value: String?, color: Color = .dsText2) {
            if let value, !value.isEmpty { result.append(Field(label: label, value: value, color: color)) }
        }
        add("Holder", license.holderName)
        add("Number", license.licenseNumber)
        add("Type", license.licenseType)
        add("Region", license.region)
        add("Issued", license.issueDate.map(Self.day))
        let expiryColor: Color = license.isRenewalDue ? (license.expiryStatus?.color ?? .dsText2) : .dsText2
        add("Expires", license.expiryDate.map(Self.day), color: expiryColor)
        return result
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        let shown = fields
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Details")
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, field in
                        fieldRow(field)
                        if index < shown.count - 1 { PFDivider() }
                    }
                }
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    private func fieldRow(_ field: Field) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Text(field.label)
                .foregroundStyle(.dsText)
            Spacer(minLength: DS.Space.s4)
            Text(field.value)
                .foregroundStyle(field.color)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.body)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
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
                if let url = license.documentURL {
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
