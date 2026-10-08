import Foundation

struct BatchResult {
    let folder: URL
    let pairs: [LivePair]
    let warnings: [String]
}

enum BatchService {
    static func copy(_ source: URL, into root: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: destination) }
            catch { copyError = error }
        }
        if let error = coordinationError { throw error }
        if let error = copyError { throw error }
        return destination
    }

    static func prepare(_ urls: [URL], progress: @escaping (Int, Int) async -> Void) async throws -> BatchResult {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var images: [String: [URL]] = [:]
        var videos: [String: [URL]] = [:]
        var warnings: [String] = []
        do {
            for (index, source) in urls.enumerated() {
                try Task.checkCancellation()
                await progress(index, urls.count)
                let ext = source.pathExtension.lowercased()
                let isImage = ["heic", "heif", "jpg", "jpeg"].contains(ext)
                guard isImage || ext == "mov" else {
                    warnings.append("\(source.lastPathComponent): formato no compatible.")
                    continue
                }
                do {
                    let local = try await Task.detached(priority: .userInitiated) { try copy(source, into: folder) }.value
                    if isImage {
                        let id = try await Task.detached { try LivePhotoService.imageIdentifier(local) }.value
                        images[id, default: []].append(local)
                    } else {
                        let id = try await LivePhotoService.videoIdentifier(local)
                        videos[id, default: []].append(local)
                    }
                } catch {
                    warnings.append("\(source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            var pairs: [LivePair] = []
            // Reject missing or ambiguous matches rather than pairing by filename.
            for id in Set(images.keys).union(videos.keys).sorted() {
                let photos = images[id] ?? []
                let movies = videos[id] ?? []
                guard photos.count == 1, movies.count == 1 else {
                    let names = (photos + movies).map(\.lastPathComponent).joined(separator: ", ")
                    warnings.append("\(names): falta la pareja o hay originales duplicados con el mismo identificador.")
                    continue
                }
                pairs.append(LivePair(folder: folder, image: photos[0], video: movies[0]))
            }
            await progress(urls.count, urls.count)
            return BatchResult(folder: folder, pairs: pairs, warnings: warnings)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
