import PhotosUI
import QuickLook
import SwiftUI
import StublyKit
import UniformTypeIdentifiers

/// Belge kasası: pasaport, vize, sigorta, bilet ve rezervasyon dosyaları. Dosyalar uygulama klasöründe
/// şifreli (Data Protection) saklanır; "yalnızca bu cihazda" işaretlenmeyenler ekiple eşitlenir.
struct DocumentsCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var isPickingFile = false
    @State private var isShowingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: PendingFile?
    @State private var previewURL: URL?

    struct PendingFile: Identifiable {
        let id = UUID()
        let data: Data
        let fileExtension: String
        let suggestedTitle: String
    }

    var body: some View {
        let documents = trip.documentList
        ModuleCard(String(localized: "Belgeler"), symbol: "doc.on.doc.fill", accessory: {
            Menu {
                Button("Dosya seç (PDF, görsel)", systemImage: "folder") { isPickingFile = true }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Fotoğraflardan", systemImage: "photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Kamerayla tara", systemImage: "camera") { isShowingCamera = true }
                }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.circleIcon(size: 32))
            .accessibilityLabel("Belge ekle")
        }) {
            if documents.isEmpty {
                EmptyHint(symbol: "doc.badge.plus",
                          text: String(localized: "Pasaport, sigorta poliçesi, bilet ve rezervasyonları burada sakla; internetsiz de açılır."))
                    .tray()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                        if index > 0 { Divider().overlay(Color.line) }
                        row(document)
                    }
                }
                .tray(padding: 14)
            }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image]) { outcome in
            guard case let .success(url) = outcome else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pending = PendingFile(data: data, fileExtension: url.pathExtension.isEmpty ? "pdf" : url.pathExtension,
                                      suggestedTitle: url.deletingPathExtension().lastPathComponent)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = CoverImageStore.downsample(data: data, maxPixelSize: 2400),
                   let jpeg = image.jpegData(compressionQuality: 0.85) {
                    pending = PendingFile(data: jpeg, fileExtension: "jpg", suggestedTitle: "")
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onCapture: { image in
                if let jpeg = image.jpegData(compressionQuality: 0.85) {
                    pending = PendingFile(data: jpeg, fileExtension: "jpg", suggestedTitle: "")
                }
            }, onClose: { isShowingCamera = false })
            .ignoresSafeArea()
        }
        .sheet(item: $pending) { file in
            DocumentDetailsSheet(trip: trip, file: file)
        }
        .quickLookPreview($previewURL)
    }

    private func row(_ document: TravelDocument) -> some View {
        let url = CoverImageStore.documents.fileURL(named: document.fileName)
        return Button {
            previewURL = url
        } label: {
            HStack(spacing: 12) {
                Image(systemName: DocumentText.symbol(document.kind))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.blue.base)
                    .frame(width: 40, height: 40)
                    .background(Accent.blue.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(DocumentText.title(document.kind))
                        if let member = trip.member(document.memberID) { Text("· \(member.name)") }
                        if document.isPrivate { Image(systemName: "lock.fill") }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    if url == nil {
                        Text(document.isPrivate ? String(localized: "Yalnızca ekleyen cihazda") : String(localized: "Henüz indirilmedi"))
                            .font(.caption2)
                            .foregroundStyle(Color.food)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.ink3)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .contextMenu {
            if let url {
                ShareLink(item: url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
            }
            Button("Sil", systemImage: "trash", role: .destructive) {
                withAnimation {
                    store.update(trip.id) { $0.documents?.removeAll { $0.id == document.id } }
                    CoverImageStore.documents.delete(named: document.fileName)
                }
            }
        }
    }
}

/// Yeni belgenin adı, türü, sahibi ve gizliliği.
private struct DocumentDetailsSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let file: DocumentsCard.PendingFile

    @State private var title: String
    @State private var kind: TravelDocument.Kind = .other
    @State private var memberID: UUID?
    @State private var isPrivate = false
    @State private var errorText: String?

    init(trip: Trip, file: DocumentsCard.PendingFile) {
        self.trip = trip
        self.file = file
        _title = State(initialValue: file.suggestedTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Belge adı", text: $title)
                    Picker("Tür", selection: $kind) {
                        ForEach(TravelDocument.Kind.allCases, id: \.self) { kind in
                            Label(DocumentText.title(kind), systemImage: DocumentText.symbol(kind)).tag(kind)
                        }
                    }
                    Picker("Kime ait", selection: $memberID) {
                        Text("Herkes").tag(UUID?.none)
                        ForEach(trip.members) { member in
                            Text(member.name).tag(UUID?.some(member.id))
                        }
                    }
                }
                Section {
                    Toggle("Yalnızca bu cihazda", isOn: $isPrivate)
                } footer: {
                    Text(isPrivate
                         ? String(localized: "Dosya iCloud'a yüklenmez; ekip yalnızca belgenin adını görür.")
                         : String(localized: "Seyahat paylaşılıyorsa dosya ekipteki herkese iCloud üzerinden gider."))
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Color.food) }
                }
            }
            .navigationTitle("Belge ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: kind) { _, newValue in
                // Pasaport ve vize sayfaları varsayılan olarak cihazda kalır.
                if newValue == .passport || newValue == .visa { isPrivate = true }
                if title.isEmpty { title = DocumentText.title(newValue) }
            }
        }
    }

    private func save() {
        do {
            let name = try CoverImageStore.documents.saveRaw(file.data, fileExtension: file.fileExtension)
            let document = TravelDocument(title: title.trimmingCharacters(in: .whitespaces), kind: kind, fileName: name,
                                          memberID: memberID, isPrivate: isPrivate)
            store.update(trip.id) { $0.documents = ($0.documents ?? []) + [document] }
            dismiss()
        } catch {
            errorText = "Belge kaydedilemedi: \(error.localizedDescription)"
        }
    }
}

enum DocumentText {
    static func title(_ kind: TravelDocument.Kind) -> String {
        switch kind {
        case .passport: String(localized: "Pasaport")
        case .visa: String(localized: "Vize")
        case .insurance: String(localized: "Sigorta")
        case .ticket: String(localized: "Bilet")
        case .reservation: String(localized: "Rezervasyon")
        case .other: String(localized: "Diğer")
        }
    }

    static func symbol(_ kind: TravelDocument.Kind) -> String {
        switch kind {
        case .passport: "person.text.rectangle"
        case .visa: "checkmark.seal"
        case .insurance: "cross.case"
        case .ticket: "airplane"
        case .reservation: "bed.double"
        case .other: "doc"
        }
    }
}
