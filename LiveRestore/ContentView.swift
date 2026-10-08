import SwiftUI
import Photos
import PhotosUI

struct RestoreItem: Identifiable {
    enum Status { case pending, saved, failed }
    let id = UUID()
    let pair: LivePair
    var status: Status = .pending
    var detail = "Lista para restaurar"
}

@MainActor
final class RestoreModel: ObservableObject {
    @Published var items: [RestoreItem] = []
    @Published var live: PHLivePhoto?
    @Published var previewName = ""
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var warnings: [String] = []
    @Published var message = "Selecciona todas las imágenes y sus MOV originales desde Archivos."
    @Published var stopping = false
    private var folder: URL?
    var remaining: Int { items.filter { $0.status != .saved }.count }

    func select(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        progress = 0
        live = nil
        items = []
        warnings = []
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        message = "Leyendo los originales…"
        Task {
            do {
                let batch = try await BatchService.prepare(urls) { done, total in
                    await MainActor.run {
                        self.progress = Double(done) / Double(max(total, 1))
                        self.message = "Leyendo archivos: \(done)/\(total)"
                    }
                }
                folder = batch.folder
                items = batch.pairs.map { RestoreItem(pair: $0) }
                warnings = batch.warnings
                message = "\(items.count) parejas encontradas. \(warnings.count) incidencias."
                if let first = items.first {
                    do {
                        live = try await LivePhotoService.preview(first.pair)
                        previewName = first.pair.image.lastPathComponent
                    } catch {
                        warnings.append("Vista previa de \(first.pair.image.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    func save() {
        guard !busy, remaining > 0 else { return }
        busy = true
        stopping = false
        progress = 0
        live = nil
        Task {
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized else {
                message = "Permite añadir fotos en Ajustes → LiveRestore → Fotos y vuelve a intentarlo."
                busy = false
                return
            }
            let indices = items.indices.filter { items[$0].status != .saved }
            var completed = 0
            for index in indices {
                if stopping { break }
                message = "Restaurando \(completed + 1)/\(indices.count): \(items[index].pair.image.lastPathComponent)"
                do {
                    try await validate(items[index].pair)
                    try await LivePhotoService.save(items[index].pair)
                    items[index].status = .saved
                    items[index].detail = "Guardada en Fotos"
                } catch {
                    items[index].status = .failed
                    items[index].detail = error.localizedDescription
                }
                completed += 1
                progress = Double(completed) / Double(max(indices.count, 1))
            }
            let saved = items.filter { $0.status == .saved }.count
            let failed = items.filter { $0.status == .failed }.count
            let pending = items.filter { $0.status == .pending }.count
            message = "\(saved) guardadas · \(failed) fallidas · \(pending) pendientes."
            if remaining == 0, let folder {
                try? FileManager.default.removeItem(at: folder)
                self.folder = nil
            }
            busy = false
            stopping = false
        }
    }

    private func validate(_ pair: LivePair) async throws {
        // Keep only one decoded Live Photo in memory during a batch.
        let preview = try await LivePhotoService.preview(pair)
        _ = preview
    }
}

struct ContentView: View {
    @StateObject private var model = RestoreModel()
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Recupera el movimiento", systemImage: "livephoto").font(.largeTitle.bold())
                    Text("Restaura varias Live Photos de una sola vez.").font(.title3).foregroundStyle(.secondary)
                    if let live = model.live {
                        LivePreview(live: live).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 22))
                        Text("Vista previa: \(model.previewName)").font(.caption)
                    }
                    Text(model.message).accessibilityIdentifier("status")
                    if model.busy { ProgressView(value: model.progress) }
                    Button { picking = true } label: {
                        Label("Elegir imágenes y MOV", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.bordered).disabled(model.busy)
                    Button { model.save() } label: {
                        Label("Restaurar \(model.remaining) Live Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).disabled(model.busy || model.remaining == 0)
                    if model.busy && !model.items.isEmpty {
                        Button(model.stopping ? "Deteniendo…" : "Detener después de esta foto") { model.stopping = true }
                            .disabled(model.stopping)
                    }
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.pair.image.lastPathComponent, systemImage: icon(item.status)).font(.subheadline.bold())
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !model.warnings.isEmpty {
                        DisclosureGroup("Archivos omitidos / avisos (\(model.warnings.count))") {
                            ForEach(Array(model.warnings.enumerated()), id: \.offset) { entry in
                                Text(entry.element).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }
                    }
                    Text("Selecciona las imágenes y sus vídeos originales. Se emparejan por sus metadatos aunque los nombres sean diferentes. Mantén la app abierta durante la restauración.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("NAS: Archivos → Explorar → ⋯ → Conectarse al servidor.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("LiveRestore").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $picking) { FilePicker(selected: { urls in picking = false; model.select(urls) }) }
        }
    }

    private func icon(_ status: RestoreItem.Status) -> String {
        switch status {
        case .pending: return "livephoto"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
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
