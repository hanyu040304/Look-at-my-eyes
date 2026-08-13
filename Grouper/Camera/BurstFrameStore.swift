import Combine
import Foundation
import Photos
import UIKit

@MainActor
final class BurstFrameStore: ObservableObject {
    @Published private(set) var frames: [BurstFrame] = []

    var count: Int {
        frames.count
    }

    var hasFrames: Bool {
        !frames.isEmpty
    }

    func replace(with frames: [BurstFrame]) {
        self.frames = frames
    }

    func clear() {
        frames.removeAll()
    }

    func exportAll(completion: @escaping (Result<Int, Error>) -> Void) {
        let images = frames.map(\.image)
        guard !images.isEmpty else {
            completion(.success(0))
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(PhotoExportError.notAuthorized))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, error in
                if success {
                    completion(.success(images.count))
                } else {
                    completion(.failure(error ?? PhotoExportError.failed))
                }
            }
        }
    }
}

enum PhotoExportError: LocalizedError {
    case notAuthorized
    case failed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有相册写入权限"
        case .failed:
            return "导出失败"
        }
    }
}
