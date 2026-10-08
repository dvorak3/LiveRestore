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


}

enum LivePhotoService {
    static func imageIdentifier(_ url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
              let identifier = maker["17"] as? String, !identifier.isEmpty else {
            throw RestoreError(message: "La imagen no conserva el identificador Live Photo original.")
        }
        return identifier
    }

    static func videoIdentifier(_ url: URL) async throws -> String {
        let metadata = try await AVURLAsset(url: url).load(.metadata)
        for item in metadata where item.identifier?.rawValue == "mdta/com.apple.quicktime.content.identifier" {
            if let identifier = try await item.load(.stringValue), !identifier.isEmpty { return identifier }
        }
        throw RestoreError(message: "El MOV no conserva el identificador Live Photo original.")
    }

    static func validateIdentifiers(_ pair: LivePair) async throws {
        let imageID = try imageIdentifier(pair.image)
        let movieID = try await videoIdentifier(pair.video)
        guard imageID == movieID else {
            throw RestoreError(message: "La imagen y el MOV no pertenecen a la misma Live Photo.")
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
