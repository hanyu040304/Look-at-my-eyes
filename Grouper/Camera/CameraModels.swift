import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum CameraAuthorizationState {
    case unknown
    case authorized
    case denied
}

enum CaptureState: Equatable {
    case idle
    case capturing(progress: Double)
    case processing
    case completed
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .capturing, .processing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var progress: Double {
        switch self {
        case .capturing(let progress):
            return progress
        case .processing, .completed:
            return 1
        case .idle, .failed:
            return 0
        }
    }
}

enum CameraPosition: String, Equatable {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }

    var title: String {
        rawValue
    }
}

enum CaptureOrientation: String, CaseIterable, Equatable {
    case portrait
    case landscapeLeft
    case landscapeRight

    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait:
            self = .portrait
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .portraitUpsideDown:
            return nil
        default:
            return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        default:
            return nil
        }
    }

    var rotationAngle: Angle {
        switch self {
        case .portrait:
            return .zero
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        }
    }
}

struct ZoomOption: Identifiable, Equatable {
    let label: String
    let factor: CGFloat
    let preferredDeviceType: AVCaptureDevice.DeviceType?

    var id: String {
        "\(label)-\(factor)"
    }

    static let oneX = ZoomOption(label: "1x", factor: 1, preferredDeviceType: .builtInWideAngleCamera)

    func isSelected(comparedTo other: ZoomOption) -> Bool {
        abs(factor - other.factor) < 0.01 && preferredDeviceType == other.preferredDeviceType
    }
}

enum PhotoResolutionOption: String, CaseIterable, Identifiable, Equatable {
    case twoMP
    case twentyFourMP
    case fortyEightMP

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .twoMP:
            return "2MP"
        case .twentyFourMP:
            return "24MP"
        case .fortyEightMP:
            return "48MP"
        }
    }

    var targetPixelCount: Int64 {
        switch self {
        case .twoMP:
            return 2_000_000
        case .twentyFourMP:
            return 24_000_000
        case .fortyEightMP:
            return 48_000_000
        }
    }
}

struct BurstFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let timestamp: TimeInterval
    let frameIndex: Int
    let orientation: CaptureOrientation
    let cameraPosition: CameraPosition
    let zoomFactor: CGFloat

    func elapsedTime(from firstTimestamp: TimeInterval?) -> TimeInterval {
        guard let firstTimestamp else { return 0 }
        return max(0, timestamp - firstTimestamp)
    }
}
