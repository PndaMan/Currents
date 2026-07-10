import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AddLicenseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when editing an existing licence.
    var editing: FishingLicense? = nil

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
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                documentSection
                Section("Details") {
                    TextField("Title (e.g. WCape Recreational Permit)", text: $title)
                    TextField("Type", text: $licenseType)
                    TextField("Holder name", text: $holderName)
                    TextField("Licence number", text: $licenseNumber)
                    TextField("Region / authority", text: $region)
                }
                Section("Validity") {
                    optionalDatePicker("Issue date", date: $issueDate)
                    optionalDatePicker("Expiry date", date: $expiryDate)
                    if expiryDate != nil {
                        Text("You'll be reminded 1 month, 2 weeks, 1 week, 3 days before, and on the day.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(editing == nil ? "Add Licence" : "Edit Licence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(title.isEmpty)
                }
            }
            .onAppear(perform: loadIfEditing)
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                if case .success(let url) = result { importFile(url) }
            }
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
                }
            }
        }
    }

    // MARK: - Document section

    @ViewBuilder private var documentSection: some View {
        Section("Document") {
            if let fileName, let fileKind {
                LicenseDocumentView(license: FishingLicense(title: title, fileName: fileName, fileKind: fileKind))
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if isScanning {
                HStack(spacing: 8) { ProgressView(); Text("Reading licence…").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Button { showingFileImporter = true } label: { Label("PDF / File", systemImage: "doc") }
                    .buttonStyle(.borderless)
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Photo", systemImage: "photo") }
                    .buttonStyle(.borderless)
                Spacer()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: { Label("Scan", systemImage: "camera") }
                        .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder private func optionalDatePicker(_ label: String, date: Binding<Date?>) -> some View {
        Toggle(isOn: Binding(get: { date.wrappedValue != nil },
                             set: { date.wrappedValue = $0 ? (date.wrappedValue ?? .now) : nil })) {
            Text(label)
        }
        if let value = date.wrappedValue {
            DatePicker(label, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                       displayedComponents: .date)
                .labelsHidden()
        }
    }

    // MARK: - Import + OCR

    private func importFile(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let ext = isPDF ? "pdf" : (url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())
        guard let stored = LicenseFileStore.store(data: data, ext: ext, id: id) else { return }
        fileName = stored
        fileKind = isPDF ? "pdf" : "image"
        if isPDF { runOCR(pdf: LicenseFileStore.url(for: stored)) }
        else if let img = UIImage(data: data) { runOCR(image: img) }
    }

    private func importImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9),
              let stored = LicenseFileStore.store(data: data, ext: "jpg", id: id) else { return }
        fileName = stored
        fileKind = "image"
        runOCR(image: image)
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
        if title.isEmpty { title = "Fishing Licence" }
    }

    // MARK: - Load / save

    private func loadIfEditing() {
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
            title: title.isEmpty ? "Fishing Licence" : title,
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
        try? appState.licenseRepository.save(&license)
        let all = (try? appState.licenseRepository.fetchAll()) ?? []
        Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: all) }
        dismiss()
    }
}
