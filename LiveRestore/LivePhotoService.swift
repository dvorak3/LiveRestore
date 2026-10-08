import AVFoundation
import ImageIO
import Photos
import UIKit

struct RestoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct LivePair {
    let folder: URL
    let image: URL
    let video: URL

    static func stage(_ urls: [URL]) throws -> LivePair {
        let images = urls.filter { ["heic", "heif", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        let movies = urls.filter { $0.pathExtension.lowercased() == "mov" }
        guard urls.count == 2, images.count == 1, movies.count == 1 else {
            throw RestoreError(message: "Selecciona exactamente una imagen HEIC/JPEG y su vídeo MOV original.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            func copy(_ source: URL) throws -> URL {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let destination = folder.appendingPathComponent(source.lastPathComponent)
                // Coordinate reads from Files providers (including SMB/iCloud).
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
            return try LivePair(folder: folder, image: copy(images[0]), video: copy(movies[0]))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func discard() { try? FileManager.default.removeItem(at: folder) }
}

enum LivePhotoService {
    static func validateIdentifiers(_ pair: LivePair) async throws {
        guard let source = CGImageSourceCreateWithURL(pair.image as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
              let imageID = maker["17"] as? String, !imageID.isEmpty else {
            throw RestoreError(message: "La imagen no conserva el identificador de una Live Photo original. Esta versión restaura parejas originales; no convierte vídeos sueltos.")
        }
        let asset = AVURLAsset(url: pair.video)
        let metadata = try await asset.load(.metadata)
        var movieID: String?
        for item in metadata where item.identifier?.rawValue == "mdta/com.apple.quicktime.content.identifier" {
            movieID = try await item.load(.stringValue)
            if movieID != nil { break }
        }
        guard let movieID, imageID == movieID else {
            throw RestoreError(message: "El HEIC y el MOV no tienen el mismo identificador Live Photo. Selecciona los dos originales de la misma foto.")
        }
    }

    static func preview(_ pair: LivePair) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: [pair.image, pair.video], placeholderImage: nil,
                                targetSize: CGSize(width: 1000, height: 1000), contentMode: .aspectFit) { live, info in
                // Apple can call this multiple times with a degraded intermediate result.
                if (info[PHLivePhotoInfoIsDegradedKey] as? NSNumber)?.boolValue == true { return }
                if let live {
                    continuation.resume(returning: live)
                } else {
                    let error = info[PHLivePhotoInfoErrorKey] as? Error
                    continuation.resume(throwing: error ?? RestoreError(message: "iOS no reconoce esta pareja como una Live Photo válida. Comprueba que el MOV conserva los metadatos originales."))
                }
            }
        }
    }

    static func save(_ pair: LivePair) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw RestoreError(message: "Permite añadir fotos en Ajustes → LiveRestore → Fotos y vuelve a intentarlo.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.originalFilename = pair.image.lastPathComponent
            photoOptions.shouldMoveFile = false
            let videoOptions = PHAssetResourceCreationOptions()
            videoOptions.originalFilename = pair.video.lastPathComponent
            videoOptions.shouldMoveFile = false
            request.addResource(with: .photo, fileURL: pair.image, options: photoOptions)
            request.addResource(with: .pairedVideo, fileURL: pair.video, options: videoOptions)
        }
    }
}
