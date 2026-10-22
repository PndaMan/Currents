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
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var isScanning = false

    /// The common kinds as one-tap chips. A different type saved earlier
    /// shows as its own chip, so editing never loses it.
    private static let types = ["Freshwater", "Marine", "Permit"]

    private var typeOptions: [String] {
        let current = licenseType.trimmingCharacters(in: .whitespaces)
        return current.isEmpty || Self.types.contains(current) ? Self.types : Self.types + [current]
    }

    /// The form as a licence, for the live card at the top.
    private var draft: FishingLicense {
        FishingLicense(id: id, title: title,
                       licenseType: licenseType.isEmpty ? nil : licenseType,
                       holderName: holderName.isEmpty ? nil : holderName,
                       licenseNumber: licenseNumber.isEmpty ? nil : licenseNumber,
                       region: region.isEmpty ? nil : region,
                       issueDate: issueDate, expiryDate: expiryDate,
                       fileName: fileName, fileKind: fileKind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LicenseCard(license: draft)
                        .licenseFormBareRow()
                }
                documentSection
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(typeOptions, id: \.self) { type in
                                Chip(type, isSelected: licenseType == type) {
                                    Haptics.selection()
                                    licenseType = licenseType == type ? "" : type
                                }
                            }
                        }
                        .padding(.vertical, DS.Space.s1)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
                    .licenseFormBareRow()
                } header: {
                    Text("Type")
                }
                Section("Details") {
                    TextField("Title", text: $title, prompt: Text("Western Cape freshwater licence"))
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
            .navigationTitle(editing != nil ? "Edit licence" : (renewing != nil ? "Add renewal" : "Add licence"))
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
        Section {
            HStack(spacing: DS.Space.s2) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(ActionTileStyle(fileName == nil ? .primary : .tonal))
                    .accessibilityLabel("Scan the licence with the camera")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ActionTileLabel("Photo", systemImage: "photo")
                }
                .buttonStyle(.dim)
                .accessibilityLabel("Choose a photo of the licence")
                Button { showingFileImporter = true } label: {
                    Label("File", systemImage: "doc")
                }
                .buttonStyle(ActionTileStyle())
                .accessibilityLabel("Choose a PDF or file")
            }
            .licenseFormBareRow()
        } header: {
            Text("Document")
        }

        if let fileName, let fileKind {
            Section {
                HStack(spacing: 12) {
                    LicenseDocumentView(license: FishingLicense(title: title, fileName: fileName, fileKind: fileKind))
                        .allowsHitTesting(false)
                        .frame(width: 56, height: 56)
                        .background(Color.dsFill2)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileKind == "pdf" ? "PDF attached" : "Photo attached")
                            .foregroundStyle(.dsText)
                        if isScanning {
                            Text("Reading the licence")
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                        }
                    }
                    Spacer(minLength: 0)
                    if isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .pfRows()
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
        if title.isEmpty { title = "Fishing licence" }
    }

    // MARK: - Load / save

    private func loadIfEditing() {
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
        try? appState.licenseRepository.save(&license)
        let all = (try? appState.licenseRepository.fetchAll()) ?? []
        Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: all) }
        ToastCenter.shared.show(editing != nil ? "Licence updated" : (renewing != nil ? "Renewal added" : "Licence added"))
        dismiss()
    }
}

private extension View {
    /// A clear, full-width form row for content that brings its own
    /// background (the card, the document tiles, the type chips).
    func licenseFormBareRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
