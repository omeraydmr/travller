import PhotosUI
import SwiftUI
import StublyKit

/// Bir seyahat için kapak fotoğrafı seçtirir. `target` dolunca fotoğraf seçici açılır.
struct CoverPhotoPicker: ViewModifier {
    @Environment(TripStore.self) private var store
    @Binding var target: Trip.ID?
    @State private var pendingID: Trip.ID?
    @State private var isPresented = false
    @State private var item: PhotosPickerItem?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images, photoLibrary: .shared())
            .onChange(of: target) { _, newTarget in
                // Hedefi hemen sıfırla ki aynı seyahat için tekrar seçilebilsin.
                guard let newTarget else { return }
                pendingID = newTarget
                target = nil
                isPresented = true
            }
            .onChange(of: item) { _, newItem in
                guard let newItem, let id = pendingID else { return }
                Task {
                    defer { item = nil }
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            throw CoverImageStore.CoverError.unreadableImage
                        }
                        try withAnimation(.easeInOut(duration: 0.3)) {
                            try store.setCoverPhoto(data, for: id)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Fotoğraf eklenemedi", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension View {
    func coverPhotoPicker(for target: Binding<Trip.ID?>) -> some View {
        modifier(CoverPhotoPicker(target: target))
    }
}
