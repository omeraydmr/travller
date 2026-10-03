import SwiftUI
import StublyKit

/// QR ile davet: iCloud paylaşımını "bağlantıya sahip herkes, salt okur" yapar ve bağlantıyı büyük bir QR olarak
/// gösterir. Okutan kişi seyahati görür; düzenleme yetkisini sahip Ekip'te "Ekibe ekle" ile verir.
struct InviteQRSheet: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var errorText: String?
    @State private var isClosing = false
    private var sync: CloudSync { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("QR ile davet et")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
            .task { await open() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        if sync.sharedWithMe.contains(trip.id) {
            ContentUnavailableView("Yalnızca seyahatin sahibi davet edebilir", systemImage: "person.crop.circle.badge.exclamationmark")
        } else if !sync.isAvailable {
            ContentUnavailableView("iCloud gerekli", systemImage: "icloud.slash",
                                   description: Text("QR ile davet için iCloud'a giriş yapmış olmalısın."))
        } else if let errorText {
            ContentUnavailableView {
                Label("Bağlantı hazırlanamadı", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorText)
            } actions: {
                Button("Tekrar dene") { Task { await open() } }
            }
        } else if let url, let image = QRCode.image(for: url.absoluteString) {
            VStack(spacing: 16) {
                // Okunabilirlik için temada da beyaz zemin üzerinde siyah.
                Image(uiImage: image)
                    .renderingMode(.template)
                    .interpolation(.none)
                    .resizable()
                    .foregroundStyle(.black)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(width: 260, height: 260)
                    .accessibilityLabel(Text("\(trip.name) davet QR kodu"))
                VStack(spacing: 4) {
                    Text(trip.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text("Telefonunun kamerasıyla okutan kişi seyahati görür. Düzenleyebilmesi için Ekip'te onu ekibe ekle.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                }
                ShareLink(item: url, preview: SharePreview("\(trip.name) · Stubly")) {
                    Label("Bağlantıyı paylaş", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                Button(role: .destructive) {
                    Task { await close() }
                } label: {
                    Label("Bağlantıyı kapat", systemImage: "xmark.circle")
                }
                .disabled(isClosing)
                Text("Kapatınca bu QR ve bağlantıyla kimse yeni katılamaz.")
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.center)
            }
        } else {
            ProgressView("Bağlantı hazırlanıyor…")
                .padding(.top, 80)
        }
    }

    private func open() async {
        guard !sync.sharedWithMe.contains(trip.id), sync.isAvailable else { return }
        errorText = nil
        do {
            url = try await sync.openInviteLink(for: trip.id)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func close() async {
        isClosing = true
        defer { isClosing = false }
        do {
            try await sync.closeInviteLink(for: trip.id)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
