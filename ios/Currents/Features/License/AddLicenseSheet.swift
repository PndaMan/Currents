import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UserNotifications

/// Adds, edits or renews a licence, built like the spot form: the document
/// first, then the details read from it, then the dates.
struct AddLicenseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when editing an existing licence.
    var editing: FishingLicense? = nil
    /// Non-nil when adding next year's licence: title, type, holder and region
    /// carry over; dates and the document start empty. The old one is kept.
    var renewing: FishingLicense? = nil
    /// Called once the licence is saved, before the sheet closes.
    var onSaved: (() -> Void)? = nil

    @State private var id = UUID().uuidString
    @State private var title = ""
    @State private var licenseType = ""
    @State private var holderName = ""
    @State private var licenseNumber = ""
    @State private var region = ""
    @State private var issueDate: Date?
    @State private var expiryDate: Date?
    @State private var notes = ""
    @State private var fileName: String?
    @State private var fileKind: String?

    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var isScanning = false
    @State private var saved = false
    @State private var didLoad = false
    /// What the form held when it opened, so a swipe can't drop an edit.
    @State private var original = Fields()

    @State private var showingReminderPrimer = false
    /// The licences to remind about once the angler answers the primer.
    @State private var pendingReminders: [FishingLicense] = []
    @AppStorage("licenceReminderPrimerShown") private var primerShown = false
    /// Read by `LicenseOCR` for numeric dates such as 03/04.
    @AppStorage("dateOrder") private var dateOrder = "auto"

    /// The common kinds. A different type saved earlier stays in the list,
    /// so editing never loses it.
    private static let types = ["Freshwater", "Marine", "Permit"]

    /// "" is no type.
    private var typeOptions: [String] {
        let current = licenseType.trimmingCharacters(in: .whitespaces)
        let kinds = current.isEmpty || Self.types.contains(current) ? Self.types : Self.types + [current]
        return [""] + kinds
    }

    private var navigationTitle: String {
        if editing != nil { return "Edit licence" }
        return renewing != nil ? "Add renewal" : "Add licence"
    }

    private struct Fields: Equatable {
        var title = ""
        var licenseType = ""
        var holderName = ""
        var licenseNumber = ""
        var region = ""
        var issueDate: Date?
        var expiryDate: Date?
        var notes = ""
        var fileName: String?
    }

    private var current: Fields {
        Fields(title: title, licenseType: licenseType, holderName: holderName, licenseNumber: licenseNumber,
               region: region, issueDate: issueDate, expiryDate: expiryDate, notes: notes, fileName: fileName)
    }

    private var hasChanges: Bool { current != original }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !saved }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    documentField
                    field("Title") {
                        TextField("Western Cape freshwater licence", text: $title)
                            .submitLabel(.done)
                            .modifier(LicenceFieldStyle())
                    }
                    field("Type") {
                        FilterChips(typeOptions, selection: $licenseType, title: { $0.isEmpty ? "None" : $0 })
                    }
                    field("Holder") {
                        TextField("Your name", text: $holderName)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .modifier(LicenceFieldStyle())
                    }
                    field("Number") {
                        TextField("As printed", text: $licenseNumber)
                            .submitLabel(.done)
                            .modifier(LicenceFieldStyle())
                    }
                    field("Region") {
                        TextField("Where it is valid", text: $region)
                            .submitLabel(.done)
                            .modifier(LicenceFieldStyle())
                    }
                    validityField
                    dateOrderField
                    field("Notes") {
                        TextField("Where you bought it, conditions", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                            .modifier(LicenceFieldStyle(multiline: true))
                    }
                }
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .detailScrollEdge()
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dsBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onAppear(perform: loadIfEditing)
            // The camera cover also fires onDisappear; only a real close
            // drops an unsaved pick.
            .onDisappear {
                if !saved && !showingCamera { discardUnsavedFile() }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                if case .success(let url) = result { importFile(url) }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in importImage(image) }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        importImage(img)
                    }
                    photoItem = nil
                }
            }
            .alert("Get a reminder before it expires?", isPresented: $showingReminderPrimer) {
                Button("Not now", role: .cancel) { dismiss() }
                Button("Allow") { allowReminders() }
            } message: {
                Text("Currents reminds you a month before, and again as the day gets close.")
            }
        }
        .dsSheet([.large])
    }

    // MARK: - Document

    /// The attached document as itself, or an empty card, with the three
    /// ways to add or replace it.
    private var documentField: some View {
        field("Document") {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                FilePreview(url: fileName.map(LicenseFileStore.url(for:)),
                            systemImage: fileName == nil ? "person.text.rectangle.fill" : "doc.text.image",
                            renderSize: 400, contentMode: .fit, cornerRadius: DS.Radius.thumb,
                            placeholderAspect: FishingLicense.cardAspect, tint: .green)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .padding(.horizontal, DS.gutter)
                    .accessibilityLabel(documentLabel)
                if isScanning {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView()
                        Text("Reading the licence")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                    .padding(.horizontal, DS.gutter)
                }
                ActionTriple {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: {
                            Label("Scan", systemImage: "camera")
                        }
                        .buttonStyle(ActionTileStyle(fileName == nil ? .primary : .tonal))
                        .accessibilityLabel("Scan with camera")
                    }
                    Button { showingPhotos = true } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    .buttonStyle(ActionTileStyle())
                    .accessibilityLabel("Choose a photo")
                    Button { showingFileImporter = true } label: {
                        Label("File", systemImage: "doc")
                    }
                    .buttonStyle(ActionTileStyle())
                    .accessibilityLabel("Choose a file")
                }
                if fileName != nil {
                    CardGroup {
                        Button(role: .destructive) { removeDocument() } label: {
                            CardRow("Remove document", systemImage: "trash", tint: .red)
                        }
                        .buttonStyle(.dsCardRow)
                    }
                }
                SectionFootnote("Details are read from the document. Check them.")
            }
        }
    }

    private var documentLabel: String {
        guard fileName != nil else { return "No document yet" }
        return fileKind == "pdf" ? "Attached PDF" : "Attached photo"
    }

    // MARK: - Dates

    private var validityField: some View {
        field("Validity") {
            VStack(alignment: .leading, spacing: 0) {
                CardGroup {
                    dateRow("Issued", tint: .blue, date: $issueDate)
                    dateRow("Expires", tint: .red, date: $expiryDate)
                }
                if expiryDate != nil {
                    SectionFootnote("Reminders start a month before expiry.")
                }
            }
        }
    }

    /// A date that may be left out: the compact picker with a clear button
    /// once set, or a button to add it.
    private func dateRow(_ label: String, tint: Color, date: Binding<Date?>) -> some View {
        CardRow(label, systemImage: "calendar", tint: tint, combinesChildren: false) {
            if let value = date.wrappedValue {
                HStack(spacing: DS.Space.s2) {
                    DatePicker(label, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                    Button { date.wrappedValue = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.dsText3)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Clear the \(label.lowercased()) date")
                }
            } else {
                Button("Add date") { date.wrappedValue = .now }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
                    .accessibilityLabel("Add the \(label.lowercased()) date")
            }
        }
    }

    /// How a scanned numeric date is read. Stored under the key the scanner
    /// reads, so it applies to the next scan.
    private var dateOrderField: some View {
        field("Dates on your licence") {
            VStack(alignment: .leading, spacing: 0) {
                FilterChips(["auto", "dayFirst", "monthFirst"], selection: $dateOrder, title: { (order: String) -> String in
                    switch order {
                    case "dayFirst": return "Day first"
                    case "monthFirst": return "Month first"
                    default: return "Automatic"
                    }
                })
                SectionFootnote(LicenseOCR.dayFirst
                                ? "A scan reads 03/04 as 3 April."
                                : "A scan reads 03/04 as 4 March.")
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter)
            content()
        }
    }

    // MARK: - Import + OCR

    private func importFile(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let ext = isPDF ? "pdf" : (url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())
        guard let stored = adopt(data: data, ext: ext, kind: isPDF ? "pdf" : "image") else { return }
        if isPDF { runOCR(pdf: LicenseFileStore.url(for: stored)) }
        else if let img = UIImage(data: data) { runOCR(image: img) }
    }

    private func importImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9),
              adopt(data: data, ext: "jpg", kind: "image") != nil else { return }
        runOCR(image: image)
    }

    /// Stores a newly chosen document under a name of its own, so the saved
    /// one stays untouched until Save, and drops the previous unsaved pick.
    private func adopt(data: Data, ext: String, kind: String) -> String? {
        let name = "\(id)-\(UUID().uuidString.prefix(8))"
        guard let stored = LicenseFileStore.store(data: data, ext: ext, id: name) else { return nil }
        discardUnsavedFile()
        fileName = stored
        fileKind = kind
        return stored
    }

    private func removeDocument() {
        discardUnsavedFile()
        fileName = nil
        fileKind = nil
    }

    /// Deletes the attached file unless it is the one already saved with the
    /// licence being edited.
    private func discardUnsavedFile() {
        if let fileName, fileName != editing?.fileName {
            LicenseFileStore.delete(fileName)
        }
    }

    private func runOCR(image: UIImage) {
        isScanning = true
        Task {
            let r = await LicenseOCR.scan(image: image)
            applyOCR(r); isScanning = false
        }
    }
    private func runOCR(pdf: URL) {
        isScanning = true
        Task {
            let r = await LicenseOCR.scan(pdf: pdf)
            applyOCR(r); isScanning = false
        }
    }

    private func applyOCR(_ r: LicenseOCR.Result) {
        if expiryDate == nil { expiryDate = r.expiry }
        if issueDate == nil { issueDate = r.issue }
        if licenseNumber.isEmpty, let n = r.number { licenseNumber = n }
        if holderName.isEmpty, let h = r.holder { holderName = h }
        if title.isEmpty { title = "Fishing licence" }
    }

    // MARK: - Load / save

    /// Runs once: onAppear fires again when the camera cover closes.
    private func loadIfEditing() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = current }
        if editing == nil, let r = renewing {
            title = r.title
            licenseType = r.licenseType ?? ""; holderName = r.holderName ?? ""
            region = r.region ?? ""
            return
        }
        guard let e = editing else { return }
        id = e.id; title = e.title
        licenseType = e.licenseType ?? ""; holderName = e.holderName ?? ""
        licenseNumber = e.licenseNumber ?? ""; region = e.region ?? ""
        issueDate = e.issueDate; expiryDate = e.expiryDate; notes = e.notes ?? ""
        fileName = e.fileName; fileKind = e.fileKind
    }

    private func save() {
        var license = FishingLicense(
            id: id,
            title: title.isEmpty ? "Fishing licence" : title,
            licenseType: licenseType.isEmpty ? nil : licenseType,
            holderName: holderName.isEmpty ? nil : holderName,
            licenseNumber: licenseNumber.isEmpty ? nil : licenseNumber,
            region: region.isEmpty ? nil : region,
            issueDate: issueDate,
            expiryDate: expiryDate,
            fileName: fileName,
            fileKind: fileKind,
            notes: notes.isEmpty ? nil : notes,
            createdAt: editing?.createdAt ?? .now
        )
        do {
            try appState.licenseRepository.save(&license)
        } catch {
            ToastCenter.shared.show("Couldn't save the licence", style: .error)
            return
        }
        saved = true
        // The document was replaced or removed: the old file goes too.
        if let old = editing?.fileName, old != fileName {
            LicenseFileStore.delete(old)
        }
        let all = (try? appState.licenseRepository.fetchAll()) ?? []
        ToastCenter.shared.show(editing != nil ? "Licence updated" : (renewing != nil ? "Renewal added" : "Licence added"))
        onSaved?()
        let hasExpiry = license.expiryDate != nil
        Task {
            // The first licence with an expiry date is the moment reminders
            // matter, so that is when Currents asks, once, with a primer.
            let status = await NotificationManager.shared.checkPermissionStatus()
            if hasExpiry && !primerShown && status == .notDetermined {
                primerShown = true
                pendingReminders = all
                showingReminderPrimer = true
                return
            }
            await LicenseReminders.reschedule(all)
            dismiss()
        }
    }

    private func allowReminders() {
        Task {
            _ = await NotificationManager.shared.requestPermission()
            await LicenseReminders.reschedule(pendingReminders)
            dismiss()
        }
    }
}

/// A text field on a filled rounded rectangle, as on the spot form.
private struct LicenceFieldStyle: ViewModifier {
    var multiline = false

    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, multiline ? DS.Space.s4 : 0)
            .frame(minHeight: 50)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .padding(.horizontal, DS.gutter)
    }
}
