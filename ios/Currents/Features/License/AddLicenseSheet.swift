import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AddLicenseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when editing an existing licence.
    var editing: FishingLicense? = nil
    /// Non-nil when adding next year's licence: title, type, holder and region
    /// carry over; dates and the document start empty. The old one is kept.
    var renewing: FishingLicense? = nil

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

    /// The common kinds. A different type saved earlier stays in the list,
    /// so editing never loses it.
    private static let types = ["Freshwater", "Marine", "Permit"]

    private var typeOptions: [String] {
        let current = licenseType.trimmingCharacters(in: .whitespaces)
        return current.isEmpty || Self.types.contains(current) ? Self.types : Self.types + [current]
    }

    private var navigationTitle: String {
        if editing != nil { return "Edit licence" }
        return renewing != nil ? "Add renewal" : "Add licence"
    }

    var body: some View {
        NavigationStack {
            Form {
                documentSection
                Section("Details") {
                    TextField("Title", text: $title, prompt: Text("Western Cape freshwater licence"))
                    Picker("Type", selection: $licenseType.haptic()) {
                        Text("None").tag("")
                        ForEach(typeOptions, id: \.self) { Text($0).tag($0) }
                    }
                    field("Holder", text: $holderName, prompt: "Your name")
                    field("Number", text: $licenseNumber, prompt: "As printed")
                    field("Region", text: $region, prompt: "Where it is valid")
                }
                .pfRows()
                Section {
                    dateRow("Issued", date: $issueDate)
                    dateRow("Expires", date: $expiryDate)
                } header: {
                    Text("Validity")
                } footer: {
                    if expiryDate != nil {
                        Text("Reminders start a month before expiry.")
                    }
                }
                .pfRows()
                Section("Notes") {
                    TextField("Notes", text: $notes, prompt: Text("Where you bought it, conditions"), axis: .vertical)
                        .lineLimit(2...5)
                }
                .pfRows()
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(title.isEmpty)
                }
            }
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
        }
    }

    // MARK: - Document section

    /// The attached document as itself, with ways to replace or remove it;
    /// before one is attached, the three ways to add it.
    private var documentSection: some View {
        Section {
            if let fileName {
                FilePreview(url: LicenseFileStore.url(for: fileName), systemImage: "doc.text.image",
                            renderSize: 400, contentMode: .fit, cornerRadius: DS.Radius.thumb,
                            placeholderAspect: FishingLicense.cardAspect)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .padding(.vertical, DS.Space.s2)
                    .accessibilityLabel(fileKind == "pdf" ? "Attached PDF" : "Attached photo")
                if isScanning {
                    Label {
                        Text("Reading the licence")
                    } icon: {
                        ProgressView()
                    }
                    .foregroundStyle(.dsText2)
                }
                Menu {
                    sourceButtons
                } label: {
                    Label("Replace document", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { removeDocument() } label: {
                    Label("Remove document", systemImage: "trash")
                }
            } else {
                sourceButtons
            }
        } header: {
            Text("Document")
        } footer: {
            Text("Dates, number and holder are read from the document. Check them before you save.")
        }
        .pfRows()
    }

    @ViewBuilder private var sourceButtons: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showingCamera = true } label: {
                Label("Scan with camera", systemImage: "camera")
            }
        }
        Button { showingPhotos = true } label: {
            Label("Choose photo", systemImage: "photo")
        }
        Button { showingFileImporter = true } label: {
            Label("Choose file", systemImage: "doc")
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }

    /// A date that may be left out: the compact picker with a clear button
    /// once set, or a button to add it.
    @ViewBuilder private func dateRow(_ label: String, date: Binding<Date?>) -> some View {
        LabeledContent(label) {
            if let value = date.wrappedValue {
                HStack(spacing: DS.Space.s2) {
                    DatePicker(label, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                    Button { date.wrappedValue = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.dsText3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear the \(label.lowercased()) date")
                }
            } else {
                Button("Add date") { date.wrappedValue = .now }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add the \(label.lowercased()) date")
            }
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
        Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: all) }
        ToastCenter.shared.show(editing != nil ? "Licence updated" : (renewing != nil ? "Renewal added" : "Licence added"))
        dismiss()
    }
}
