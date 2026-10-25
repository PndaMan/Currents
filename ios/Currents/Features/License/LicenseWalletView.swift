import SwiftUI
import PDFKit
import UserNotifications

/// Licences and permits, each shown by its own document (the photo, or the
/// first page of the PDF), with OCR-assisted details and expiry reminders.
/// Pushed from Profile (`AppRoute.licenses`).
struct LicenseWalletView: View {
    @Environment(AppState.self) private var appState
    @State private var licenses: [FishingLicense] = []
    @State private var showingAdd = false
    @State private var didLoad = false
    @State private var loadFailed = false
    @State private var toDelete: FishingLicense?
    @State private var opened: LicenseRoute?

    /// Still valid or undated, soonest expiry first (the repository's order).
    private var current: [FishingLicense] { licenses.filter { !$0.isExpired } }
    /// Kept apart, the way Wallet keeps expired passes out of the way.
    private var expired: [FishingLicense] { licenses.filter(\.isExpired) }

    var body: some View {
        List {
            if didLoad && !loadFailed && licenses.isEmpty {
                emptyHero
                    .dsListRow()
                addButton
                    .padding(.top, DS.Space.s5)
                    .dsListRow()
            } else {
                DetailHeader(title: "Licences", subtitle: summary)
                    .padding(.bottom, DS.Space.s2)
                    .dsListRow()
            }
            if loadFailed {
                InlineEmpty(systemImage: "exclamationmark.triangle",
                            text: "Your licences could not be read. Nothing is lost.",
                            actionTitle: "Try again") { reload() }
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
        .pageTitleFade("Licences")
        .navigationDestination(item: $opened) { route in
            if let license = licenses.first(where: { $0.id == route.id }) {
                LicenseDetailView(license: license) { reload() }
            }
        }
        // Reload once the detail page has gone, so a deleted licence never
        // leaves the page blank while it pops.
        .onChange(of: opened) { _, route in
            if route == nil { reload() }
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
    /// Each row carries its own expiry status, so this only counts.
    private var summary: String? {
        guard didLoad, !loadFailed, !licenses.isEmpty else { return nil }
        let due = current.filter(\.isRenewalDue).count
        if due > 0 { return due == 1 ? "1 licence to renew" : "\(due) licences to renew" }
        if current.isEmpty {
            return expired.count == 1 ? "1 expired licence" : "\(expired.count) expired licences"
        }
        return current.count == 1 ? "1 valid licence" : "\(current.count) valid licences"
    }

    /// Nothing kept yet: the licence art, one line and the one action, the
    /// way Target greets an angler who has not picked a species.
    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbView(systemImage: "person.text.rectangle.fill", tint: .green, size: 112)
                .padding(.horizontal, DS.gutter)
                .accessibilityHidden(true)
            DetailHeader(title: "Licences",
                         subtitle: "Scan a licence to keep it here, with a reminder before it expires.")
                .padding(.top, DS.Space.s4)
        }
    }

    private var addButton: some View {
        Button { showingAdd = true } label: {
            Label("Add licence", systemImage: "plus")
        }
        .buttonStyle(.dsPrimary)
        .padding(.horizontal, DS.gutter)
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
        do {
            licenses = try appState.licenseRepository.fetchAll()
            loadFailed = false
        } catch {
            // Say so rather than show an empty wallet, and leave the
            // reminders alone: rescheduling from an empty list clears them.
            licenses = []
            loadFailed = true
            didLoad = true
            return
        }
        didLoad = true
        let all = licenses
        Task { await LicenseReminders.reschedule(all) }
    }

    private func delete(_ license: FishingLicense) {
        do {
            try appState.licenseRepository.delete(license)
        } catch {
            ToastCenter.shared.show("Couldn't delete the licence", style: .error)
            return
        }
        Haptics.warning()
        ToastCenter.shared.show("Licence deleted", style: .info, haptic: false)
        reload()
    }
}

// MARK: - Reminders

/// Licence expiry reminders. They are scheduled only once notifications are
/// already allowed, so opening Licences never brings up the system prompt;
/// the add sheet asks, with a primer, when the first expiry date is saved.
enum LicenseReminders {
    /// Reschedules every reminder, leaving out licences that a renewal has
    /// replaced. Never asks for permission.
    static func reschedule(_ licenses: [FishingLicense]) async {
        guard await isAllowed() else { return }
        await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: current(licenses))
    }

    static func isAllowed() async -> Bool {
        let status = await NotificationManager.shared.checkPermissionStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Drops a licence when a newer one with the same title, type and region
    /// exists: that is its renewal, which carries those fields over.
    static func current(_ licenses: [FishingLicense]) -> [FishingLicense] {
        licenses.filter { license in
            !licenses.contains { other in
                other.id != license.id && sameLicence(other, license) && isNewer(other, than: license)
            }
        }
    }

    private static func sameLicence(_ a: FishingLicense, _ b: FishingLicense) -> Bool {
        a.title.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(b.title.trimmingCharacters(in: .whitespaces)) == .orderedSame
            && (a.licenseType ?? "") == (b.licenseType ?? "")
            && (a.region ?? "") == (b.region ?? "")
    }

    /// Later expiry when both have one, otherwise the one added later.
    private static func isNewer(_ a: FishingLicense, than b: FishingLicense) -> Bool {
        if let ae = a.expiryDate, let be = b.expiryDate, ae != be { return ae > be }
        return a.createdAt > b.createdAt
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
    /// 12 days left, Valid until 3 March 2027. Warning colours use the score
    /// ink so they stay readable on light rows.
    var expiryStatus: (text: String, color: Color)? {
        guard let days = daysUntilExpiry, let expiryDate else { return nil }
        if days < 0 { return ("Expired", DS.scoreInk(0)) }
        if days == 0 { return ("Expires today", DS.scoreInk(0)) }
        if days <= 30 { return (days == 1 ? "1 day left" : "\(days) days left", DS.scoreInk(30)) }
        return ("Valid until \(LogbookFormat.fullDate(expiryDate))", .dsText2)
    }

    /// The renewal notice's tint: the raw colour of the score `expiryStatus`
    /// inks for its text, since the notice inks its own glyph.
    var renewalTint: Color {
        DS.scoreColor((daysUntilExpiry ?? 0) <= 0 ? 0 : 30)
    }
}

// MARK: - Row

/// A licence in the list: its document cropped to card shape, where it is
/// for over the title, and where it stands on expiry.
struct LicenseRow: View {
    let license: FishingLicense
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The region, else the licence type, as the over-line.
    private var place: String? {
        let text = (license.region ?? license.licenseType ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// The card beside the text, or above it at accessibility sizes, where
    /// beside it the title broke into a few letters a line.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: DS.Space.s3))
    }

    var body: some View {
        layout {
            LicenseThumbnail(license: license)
            VStack(alignment: .leading, spacing: 2) {
                if let place {
                    Text(place)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
                Text(license.title)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if let status = license.expiryStatus {
                    Text(status.text)
                        .font(.subheadline)
                        .foregroundStyle(status.color)
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
        FilePreview(url: license.documentURL, systemImage: "person.text.rectangle.fill",
                    renderSize: width * 1.5, tint: .green)
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
    /// Set when a renewal was saved, so the page returns to the wallet.
    @State private var renewalSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if license.fileName != nil {
                    document
                }
                DetailHeader(title: license.title, subtitle: license.isRenewalDue ? nil : license.expiryStatus?.text)
                if license.isRenewalDue, let status = license.expiryStatus {
                    PFNotice(systemImage: license.isExpired ? "exclamationmark.triangle.fill" : "clock.fill",
                             tint: license.renewalTint, title: status.text,
                             message: license.isExpired ? "Add the renewal once you have it."
                                                        : "Add the renewal when you buy it.")
                }
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
        .pageTitleFade(license.title, threshold: license.fileName == nil ? nil : 300)
        .sheet(isPresented: $showingEdit, onDismiss: refresh) {
            AddLicenseSheet(editing: license)
        }
        .sheet(isPresented: $showingRenewal, onDismiss: renewalClosed) {
            AddLicenseSheet(renewing: license, onSaved: { renewalSaved = true })
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

    /// Leaves the page first; the wallet reloads once it has gone, so the
    /// page never shows blank while it pops.
    private func delete() {
        do {
            try appState.licenseRepository.delete(license)
        } catch {
            ToastCenter.shared.show("Couldn't delete the licence", style: .error)
            return
        }
        Haptics.warning()
        ToastCenter.shared.show("Licence deleted", style: .info, haptic: false)
        dismiss()
    }

    /// After a renewal is saved the old licence is done with: back to the
    /// wallet, which reloads as this page pops.
    private func renewalClosed() {
        if renewalSaved {
            dismiss()
        } else {
            onChange()
        }
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

    private var rows: [(String, String)] {
        var result: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { result.append((label, value)) }
        }
        add("Holder", license.holderName)
        add("Number", license.licenseNumber)
        add("Type", license.licenseType)
        add("Region", license.region)
        add("Issued", license.issueDate.map(Self.day))
        add("Expires", license.expiryDate.map(Self.day))
        return result
    }

    /// "21 February 2027", day before month as everywhere else.
    private static func day(_ date: Date) -> String {
        LogbookFormat.fullDate(date)
    }

    var body: some View {
        let shown = rows
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Details")
                KeyValueList(rows: shown)
            }
        }
    }
}

// MARK: - Fullscreen document viewer

/// Full-screen, zoomable view of the licence document: the whole PDF (scrolls
/// and pinch-zooms) or the photo (pinch-zooms), with a Done button.
struct LicenseDocumentFullScreen: View {
    let license: FishingLicense

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
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
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
