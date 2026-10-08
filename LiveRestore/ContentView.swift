import SwiftUI
import Photos
import PhotosUI

@MainActor
final class RestoreModel: ObservableObject {
    @Published var pair: LivePair?
    @Published var live: PHLivePhoto?
    @Published var busy = false
    @Published var saved = false
    @Published var message = "Selecciona los dos originales de tu Live Photo desde Archivos."

    func select(_ urls: [URL]) {
        guard !busy else { return }
        busy = true
        saved = false
        live = nil
        pair?.discard()
        pair = nil
        message = "Preparando y comprobando la pareja…"
        Task {
            var staged: LivePair?
            do {
                // Copying a MOV from a file provider must not block the UI.
                let candidate = try await Task.detached(priority: .userInitiated) { try LivePair.stage(urls) }.value
                staged = candidate
                try await LivePhotoService.validateIdentifiers(candidate)
                let preview = try await LivePhotoService.preview(candidate)
                pair = candidate
                live = preview
                message = "Pareja válida. Mantén pulsada la vista previa para ver el movimiento."
            } catch {
                staged?.discard()
                message = error.localizedDescription
            }
            busy = false
        }
    }

    func save() {
        guard let pair, live != nil, !busy, !saved else { return }
        busy = true
        message = "Guardando en Fotos…"
        Task {
            do {
                try await LivePhotoService.save(pair)
                saved = true
                message = "Guardada en Fotos como Live Photo. Búscala en las fotos añadidas recientemente."
            } catch {
                message = "No se ha podido guardar: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = RestoreModel()
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Recupera el movimiento", systemImage: "livephoto")
                        .font(.largeTitle.bold())
                    Text("Tu foto y su vídeo, juntos otra vez en Fotos.")
                        .font(.title3).foregroundStyle(.secondary)
                    if let live = model.live {
                        LivePreview(live: live)
                            .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22).fill(Color.accentColor.opacity(0.09))
                            VStack(spacing: 12) {
                                Image(systemName: "livephoto").font(.system(size: 64))
                                Text("HEIC + MOV originales").font(.headline)
                            }.foregroundStyle(Color.accentColor)
                        }.frame(height: 240)
                    }
                    if let pair = model.pair {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(pair.image.lastPathComponent, systemImage: "photo")
                            Label(pair.video.lastPathComponent, systemImage: "video")
                        }.font(.footnote).textSelection(.enabled)
                    }
                    Text(model.message).accessibilityIdentifier("status")
                    if model.busy { ProgressView().frame(maxWidth: .infinity) }
                    Button { picking = true } label: {
                        Label("Elegir HEIC y MOV", systemImage: "folder")
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.bordered).disabled(model.busy)
                    Button { model.save() } label: {
                        Label(model.saved ? "Live Photo guardada" : "Guardar Live Photo en Fotos",
                              systemImage: model.saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent)
                        .disabled(model.live == nil || model.busy || model.saved)
                    Text("Para tu NAS: Archivos → Explorar → ⋯ → Conectarse al servidor. Después selecciona ambos archivos aquí. Se conservan sus bytes originales.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("LiveRestore").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $picking) {
                FilePicker(selected: { urls in picking = false; model.select(urls) })
            }
        }
    }
}

struct LivePreview: UIViewRepresentable {
    let live: PHLivePhoto
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = live
        return view
    }
    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== live { view.livePhoto = live }
    }
}
