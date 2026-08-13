//
//  GroupPhotoProcessor.swift
//  Grouper
//
//  Multi-frame group photo blink repair. This keeps only the local Vision/Core Image
//  pipeline from the reference file and intentionally removes all Qwen/AI report code.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

struct CapturedFrame {
    let image: CIImage
    let timestamp: TimeInterval
    let frameIndex: Int
    let orientation: CaptureOrientation
    let cameraPosition: CameraPosition
    let zoomFactor: CGFloat
    let captureMetadata: PhotoCaptureMetadata?

    init(
        image: CIImage,
        timestamp: TimeInterval,
        frameIndex: Int,
        orientation: CaptureOrientation = .portrait,
        cameraPosition: CameraPosition = .back,
        zoomFactor: CGFloat = 1,
        captureMetadata: PhotoCaptureMetadata? = nil
    ) {
        self.image = image
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.orientation = orientation
        self.cameraPosition = cameraPosition
        self.zoomFactor = zoomFactor
        self.captureMetadata = captureMetadata
    }
}

struct PhotoCaptureMetadata {
    let capturedAt: Date
    let cameraPosition: CameraPosition
    let orientation: CaptureOrientation
    let displayZoomFactor: CGFloat
    let actualZoomFactor: CGFloat
    let photoResolution: PhotoResolutionOption
    let lensModel: String?
    let cameraDeviceType: String?
    let cameraUniqueID: String?
    let videoFieldOfView: Float?
    let sensorWidth: Int32?
    let sensorHeight: Int32?
    let photoPixelWidth: Int?
    let photoPixelHeight: Int?
    let iso: Float?
    let exposureDuration: TimeInterval?
    let sourceImageMetadata: [String: Any]?
}

struct ProcessingResult {
    let directOutput: UIImage
    let optimizedOutput: UIImage
    let captureMetadata: PhotoCaptureMetadata?
    let totalPersons: Int
    let fixedCount: Int
    let decisions: [PersonDecision]
    let baseFrameIndex: Int
    let processingTime: TimeInterval
}

struct PersonDecision {
    let personIndex: Int
    let chosenFrameIndex: Int
    let originallyClosed: Bool
    let earScore: Float
}

enum ProcessingError: LocalizedError {
    case noFramesProvided
    case noFacesDetected
    case faceDetectionFailed(Error)
    case composeFailed

    var errorDescription: String? {
        switch self {
        case .noFramesProvided:
            return "没有可处理的照片帧"
        case .noFacesDetected:
            return "没有检测到人脸"
        case .faceDetectionFailed(let error):
            return "人脸检测失败：\(error.localizedDescription)"
        case .composeFailed:
            return "照片合成失败"
        }
    }
}

final class GroupPhotoProcessor {
    private let earThreshold: Float = 0.20
    private let faceMatchThreshold: CGFloat = 0.75
    private let minimumOpenEyeMaterialMargin: Float = 0.015
    private let idealMaterialMinimumEAR: Float = 0.32
    private let idealMaterialAverageEAR: Float = 0.36
    private let useEyeOnlyBlend = true
    private let eyeBandHorizontalPaddingRatio: CGFloat = 0.22
    private let eyeBandVerticalPaddingRatio: CGFloat = 1.35
    private let eyeBlendMinFeather: CGFloat = 4
    private let eyeBlendMaxFeather: CGFloat = 12
    private let singleEyePatchHorizontalPaddingRatio: CGFloat = 0.22
    private let singleEyePatchVerticalPaddingRatio: CGFloat = 0.95
    private let singleEyeMaskHorizontalPaddingRatio: CGFloat = 0.12
    private let singleEyeMaskVerticalPaddingRatio: CGFloat = 0.58
    private let singleEyeBlendMinFeather: CGFloat = 2.5
    private let singleEyeBlendMaxFeather: CGFloat = 7
    private let colorMatchMaxBias: CGFloat = 0.10
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func process(frames: [CapturedFrame]) async throws -> ProcessingResult {
        try await process(frames: frames, preferredBaseFrameIndex: nil)
    }

    func process(baseFrame: CapturedFrame, supportingFrames: [CapturedFrame]) async throws -> ProcessingResult {
        try await process(
            frames: supportingFrames + [baseFrame],
            preferredBaseFrameIndex: baseFrame.frameIndex
        )
    }

    private func process(
        frames: [CapturedFrame],
        preferredBaseFrameIndex: Int?
    ) async throws -> ProcessingResult {
        let startedAt = Date()

        guard !frames.isEmpty else {
            throw ProcessingError.noFramesProvided
        }

        let framesWithFaces = try await detectFacesInAllFrames(frames)
        let tracks = trackFacesAcrossFrames(framesWithFaces)

        guard !tracks.isEmpty else {
            throw ProcessingError.noFacesDetected
        }

        let baseFrameArrayIndex = selectBaseFrameArrayIndex(
            framesWithFaces,
            tracks: tracks,
            preferredBaseFrameIndex: preferredBaseFrameIndex
        )
        let baseFrame = framesWithFaces[baseFrameArrayIndex]
        let decisions = selectBestFramePerPerson(
            tracks: tracks,
            baseFrameIndex: baseFrame.frame.frameIndex
        )

        let directOutput = try renderUIImage(from: baseFrame.frame.image)
        let optimizedImage = composeFinalImage(
            baseFrame: baseFrame,
            decisions: decisions,
            tracks: tracks,
            allFrames: framesWithFaces
        )
        let optimizedOutput = try renderUIImage(from: optimizedImage)
        let fixedCount = decisions.filter {
            $0.originallyClosed && $0.chosenFrameIndex != baseFrame.frame.frameIndex
        }.count

        return ProcessingResult(
            directOutput: directOutput,
            optimizedOutput: optimizedOutput,
            captureMetadata: baseFrame.frame.captureMetadata,
            totalPersons: tracks.count,
            fixedCount: fixedCount,
            decisions: decisions,
            baseFrameIndex: baseFrame.frame.frameIndex,
            processingTime: Date().timeIntervalSince(startedAt)
        )
    }

    func renderFrameImages(_ frames: [CapturedFrame]) -> [UIImage] {
        frames.compactMap { try? renderUIImage(from: $0.image) }
    }

    private struct FrameWithFaces {
        let frame: CapturedFrame
        let faces: [DetectedFace]
    }

    private struct DetectedFace {
        let boundingBox: CGRect
        let earValue: Float
        let leftEyeEAR: Float
        let rightEyeEAR: Float
        let isClosed: Bool
        let confidence: Float
        let centerPoint: CGPoint
        let landmarks: VNFaceLandmarks2D?

        var minimumEyeEAR: Float {
            min(leftEyeEAR, rightEyeEAR)
        }
    }

    private struct PersonTrack {
        let personIndex: Int
        var observations: [(frameIndex: Int, face: DetectedFace)]
    }

    private func detectFacesInAllFrames(_ frames: [CapturedFrame]) async throws -> [FrameWithFaces] {
        var results: [FrameWithFaces] = []
        results.reserveCapacity(frames.count)

        for frame in frames {
            do {
                let faces = try await detectFaces(in: frame.image)
                results.append(FrameWithFaces(frame: frame, faces: faces))
            } catch {
                throw ProcessingError.faceDetectionFailed(error)
            }
        }

        return results
    }

    private func detectFaces(in image: CIImage) async throws -> [DetectedFace] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNDetectFaceLandmarksRequest()
                    request.revision = VNDetectFaceLandmarksRequestRevision3
                    let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let faces = observations.map { observation in
                        let eyeEAR = self.computeEyeEARs(landmarks: observation.landmarks)
                        let ear = (eyeEAR.left + eyeEAR.right) / 2
                        return DetectedFace(
                            boundingBox: observation.boundingBox,
                            earValue: ear,
                            leftEyeEAR: eyeEAR.left,
                            rightEyeEAR: eyeEAR.right,
                            isClosed: ear < self.earThreshold,
                            confidence: observation.confidence,
                            centerPoint: CGPoint(
                                x: observation.boundingBox.midX,
                                y: observation.boundingBox.midY
                            ),
                            landmarks: observation.landmarks
                        )
                    }
                    continuation.resume(returning: faces)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func computeEyeEARs(landmarks: VNFaceLandmarks2D?) -> (left: Float, right: Float) {
        guard
            let landmarks,
            let leftEye = landmarks.leftEye,
            let rightEye = landmarks.rightEye
        else {
            return (1.0, 1.0)
        }

        return (computeEyeEAR(eye: leftEye), computeEyeEAR(eye: rightEye))
    }

    private func computeEyeEAR(eye: VNFaceLandmarkRegion2D) -> Float {
        let points = eye.normalizedPoints
        guard points.count >= 6 else { return 1.0 }

        let vertical1 = distance(points[1], points[5])
        let vertical2 = distance(points[2], points[4])
        let horizontal = distance(points[0], points[3])

        guard horizontal > 0.001 else { return 1.0 }
        return Float((vertical1 + vertical2) / (2 * horizontal))
    }

    private func trackFacesAcrossFrames(_ framesWithFaces: [FrameWithFaces]) -> [PersonTrack] {
        var tracks: [PersonTrack] = []

        for frameWithFaces in framesWithFaces {
            let frameIndex = frameWithFaces.frame.frameIndex

            for face in frameWithFaces.faces {
                var bestTrackIndex: Int?
                var bestDistance = CGFloat.greatestFiniteMagnitude

                for (index, track) in tracks.enumerated() {
                    guard let lastObservation = track.observations.last else { continue }

                    let distance = distance(face.centerPoint, lastObservation.face.centerPoint)
                    let averageFaceWidth = (face.boundingBox.width + lastObservation.face.boundingBox.width) / 2
                    let threshold = max(averageFaceWidth * faceMatchThreshold, 0.06)

                    if distance < threshold && distance < bestDistance {
                        bestDistance = distance
                        bestTrackIndex = index
                    }
                }

                if let bestTrackIndex {
                    tracks[bestTrackIndex].observations.append((frameIndex, face))
                } else {
                    tracks.append(
                        PersonTrack(
                            personIndex: tracks.count,
                            observations: [(frameIndex, face)]
                        )
                    )
                }
            }
        }

        let minimumObservations = max(2, framesWithFaces.count / 4)
        return tracks.filter { $0.observations.count >= minimumObservations }
    }

    private func selectBaseFrameArrayIndex(
        _ framesWithFaces: [FrameWithFaces],
        tracks: [PersonTrack],
        preferredBaseFrameIndex: Int?
    ) -> Int {
        guard !tracks.isEmpty else {
            return preferredBaseFrameIndex.flatMap { preferredIndex in
                framesWithFaces.firstIndex { $0.frame.frameIndex == preferredIndex }
            } ?? 0
        }

        let frameScores = framesWithFaces.enumerated().map { index, frameWithFaces in
            baseFrameScore(
                frameIndex: frameWithFaces.frame.frameIndex,
                tracks: tracks,
                preferredBaseFrameIndex: preferredBaseFrameIndex
            ).withArrayIndex(index)
        }

        if let allOpenFrame = frameScores
            .filter({ $0.allTrackedPeopleOpen })
            .max(by: { $0.score < $1.score }) {
            return allOpenFrame.arrayIndex
        }

        return frameScores.max(by: { $0.score < $1.score })?.arrayIndex
            ?? preferredBaseFrameIndex.flatMap { preferredIndex in
                framesWithFaces.firstIndex { $0.frame.frameIndex == preferredIndex }
            }
            ?? 0
    }

    private struct BaseFrameScore {
        let arrayIndex: Int
        let observedTrackedPeople: Int
        let openTrackedPeople: Int
        let totalTrackedPeople: Int
        let score: Float

        var allTrackedPeopleOpen: Bool {
            totalTrackedPeople > 0
                && observedTrackedPeople == totalTrackedPeople
                && openTrackedPeople == totalTrackedPeople
        }

        func withArrayIndex(_ arrayIndex: Int) -> BaseFrameScore {
            BaseFrameScore(
                arrayIndex: arrayIndex,
                observedTrackedPeople: observedTrackedPeople,
                openTrackedPeople: openTrackedPeople,
                totalTrackedPeople: totalTrackedPeople,
                score: score
            )
        }
    }

    private func baseFrameScore(
        frameIndex: Int,
        tracks: [PersonTrack],
        preferredBaseFrameIndex: Int?
    ) -> BaseFrameScore {
        let observations = tracks.compactMap { track in
            track.observations.first { $0.frameIndex == frameIndex }?.face
        }
        let observedCount = observations.count
        let openFaces = observations.filter { !$0.isClosed }
        let openCount = openFaces.count
        let averageMinimumEAR = openFaces.isEmpty
            ? Float(0)
            : openFaces.map(\.minimumEyeEAR).reduce(0, +) / Float(openFaces.count)
        let averageEAR = observations.isEmpty
            ? Float(0)
            : observations.map(\.earValue).reduce(0, +) / Float(observations.count)
        let averageConfidence = observations.isEmpty
            ? Float(0)
            : observations.map(\.confidence).reduce(0, +) / Float(observations.count)
        let preferredBonus: Float = frameIndex == preferredBaseFrameIndex ? 6 : 0

        let score = Float(openCount) * 1_000
            + Float(observedCount) * 120
            + averageMinimumEAR * 120
            + averageEAR * 45
            + averageConfidence * 20
            + preferredBonus

        return BaseFrameScore(
            arrayIndex: 0,
            observedTrackedPeople: observedCount,
            openTrackedPeople: openCount,
            totalTrackedPeople: tracks.count,
            score: score
        )
    }

    private func selectBestFramePerPerson(
        tracks: [PersonTrack],
        baseFrameIndex: Int
    ) -> [PersonDecision] {
        tracks.compactMap { track in
            guard !track.observations.isEmpty else { return nil }

            let baseObservation = track.observations.first { $0.frameIndex == baseFrameIndex }
            let originallyClosed = baseObservation?.face.isClosed ?? false

            if let baseObservation, !baseObservation.face.isClosed {
                return PersonDecision(
                    personIndex: track.personIndex,
                    chosenFrameIndex: baseFrameIndex,
                    originallyClosed: false,
                    earScore: baseObservation.face.earValue
                )
            }

            let strongOpenCandidates = track.observations.filter {
                isStrongOpenEyeMaterial($0.face)
            }
            let relaxedOpenCandidates = track.observations.filter {
                !$0.face.isClosed && hasUsableEyeLandmarks($0.face)
            }
            let openCandidates = strongOpenCandidates.isEmpty
                ? relaxedOpenCandidates
                : strongOpenCandidates

            guard !openCandidates.isEmpty else {
                let fallbackObservation = baseObservation ?? track.observations[0]
                return PersonDecision(
                    personIndex: track.personIndex,
                    chosenFrameIndex: fallbackObservation.frameIndex,
                    originallyClosed: originallyClosed,
                    earScore: fallbackObservation.face.earValue
                )
            }

            let scoredFrames = openCandidates.compactMap { observation -> (frameIndex: Int, score: Float, ear: Float)? in
                guard
                    let materialScore = openEyeMaterialScore(
                        candidate: observation.face,
                        base: baseObservation?.face,
                        allowRelaxedOpen: strongOpenCandidates.isEmpty
                    )
                else {
                    return nil
                }

                return (
                    frameIndex: observation.frameIndex,
                    score: materialScore,
                    ear: observation.face.earValue
                )
            }

            guard let bestFrame = scoredFrames.max(by: { $0.score < $1.score }) else {
                return nil
            }

            return PersonDecision(
                personIndex: track.personIndex,
                chosenFrameIndex: bestFrame.frameIndex,
                originallyClosed: originallyClosed,
                earScore: bestFrame.ear
            )
        }
    }

    private func isStrongOpenEyeMaterial(_ face: DetectedFace) -> Bool {
        guard !face.isClosed, hasUsableEyeLandmarks(face) else { return false }
        return face.minimumEyeEAR >= earThreshold + minimumOpenEyeMaterialMargin
    }

    private func hasUsableEyeLandmarks(_ face: DetectedFace) -> Bool {
        guard
            let landmarks = face.landmarks,
            let leftEye = landmarks.leftEye,
            let rightEye = landmarks.rightEye
        else {
            return false
        }

        return leftEye.normalizedPoints.count >= 4 && rightEye.normalizedPoints.count >= 4
    }

    private func openEyeMaterialScore(
        candidate: DetectedFace,
        base: DetectedFace?,
        allowRelaxedOpen: Bool
    ) -> Float? {
        guard !candidate.isClosed, hasUsableEyeLandmarks(candidate) else { return nil }

        if !allowRelaxedOpen {
            guard candidate.minimumEyeEAR >= earThreshold + minimumOpenEyeMaterialMargin else {
                return nil
            }
        }

        let minimumOpenScore = normalizedScore(
            candidate.minimumEyeEAR,
            from: earThreshold + minimumOpenEyeMaterialMargin,
            to: idealMaterialMinimumEAR
        ) * 90
        let averageOpenScore = normalizedScore(
            candidate.earValue,
            from: earThreshold + minimumOpenEyeMaterialMargin,
            to: idealMaterialAverageEAR
        ) * 35
        let eyeBalancePenalty = min(abs(candidate.leftEyeEAR - candidate.rightEyeEAR) * 90, 20)
        let confidenceScore = candidate.confidence * 15
        var score = minimumOpenScore + averageOpenScore + confidenceScore - eyeBalancePenalty

        if let base {
            score += faceSimilarityScore(candidate: candidate, base: base)
            score += eyePoseSimilarityScore(candidate: candidate, base: base)
        }

        return score
    }

    private func faceSimilarityScore(candidate: DetectedFace, base: DetectedFace) -> Float {
        let averageFaceWidth = max((candidate.boundingBox.width + base.boundingBox.width) / 2, 0.001)
        let normalizedCenterDistance = distance(candidate.centerPoint, base.centerPoint) / averageFaceWidth
        let centerScore = max(0, 22 - Float(normalizedCenterDistance) * 22)

        let widthRatio = candidate.boundingBox.width / max(base.boundingBox.width, 0.001)
        let heightRatio = candidate.boundingBox.height / max(base.boundingBox.height, 0.001)
        let widthPenalty = min(Float(abs(log(Double(widthRatio)))) * 35, 18)
        let heightPenalty = min(Float(abs(log(Double(heightRatio)))) * 35, 18)

        return centerScore - widthPenalty - heightPenalty
    }

    private func eyePoseSimilarityScore(candidate: DetectedFace, base: DetectedFace) -> Float {
        guard
            let candidatePose = eyePose(in: candidate),
            let basePose = eyePose(in: base),
            candidatePose.distance > 0.001,
            basePose.distance > 0.001
        else {
            return -25
        }

        let distanceRatio = candidatePose.distance / basePose.distance
        let distancePenalty = min(Float(abs(log(Double(distanceRatio)))) * 55, 28)
        let anglePenalty = min(Float(angleDifference(candidatePose.angle, basePose.angle)) * 140, 30)

        return 34 - distancePenalty - anglePenalty
    }

    private func eyePose(in face: DetectedFace) -> (distance: CGFloat, angle: CGFloat)? {
        guard
            let landmarks = face.landmarks,
            let leftEye = landmarks.leftEye,
            let rightEye = landmarks.rightEye
        else {
            return nil
        }

        let leftPoints = normalizedLandmarkPoints(region: leftEye, faceBox: face.boundingBox)
        let rightPoints = normalizedLandmarkPoints(region: rightEye, faceBox: face.boundingBox)
        guard leftPoints.count >= 4, rightPoints.count >= 4 else { return nil }

        let leftCenter = averagePoint(leftPoints)
        let rightCenter = averagePoint(rightPoints)
        return (
            distance: distance(leftCenter, rightCenter),
            angle: atan2(rightCenter.y - leftCenter.y, rightCenter.x - leftCenter.x)
        )
    }

    private func normalizedLandmarkPoints(
        region: VNFaceLandmarkRegion2D,
        faceBox: CGRect
    ) -> [CGPoint] {
        region.normalizedPoints.map { point in
            CGPoint(
                x: faceBox.minX + point.x * faceBox.width,
                y: faceBox.minY + point.y * faceBox.height
            )
        }
    }

    private func composeFinalImage(
        baseFrame: FrameWithFaces,
        decisions: [PersonDecision],
        tracks: [PersonTrack],
        allFrames: [FrameWithFaces]
    ) -> CIImage {
        var result = baseFrame.frame.image

        for decision in decisions {
            guard decision.originallyClosed else { continue }
            guard decision.chosenFrameIndex != baseFrame.frame.frameIndex else { continue }
            guard let track = tracks.first(where: { $0.personIndex == decision.personIndex }) else { continue }
            guard let baseObservation = track.observations.first(where: { $0.frameIndex == baseFrame.frame.frameIndex }) else { continue }
            guard let bestObservation = track.observations.first(where: { $0.frameIndex == decision.chosenFrameIndex }) else { continue }
            guard let sourceFrame = allFrames.first(where: { $0.frame.frameIndex == decision.chosenFrameIndex }) else { continue }

            if useEyeOnlyBlend {
                result = blendEyeRegion(
                    source: sourceFrame.frame.image,
                    target: result,
                    sourceFace: bestObservation.face,
                    targetFace: baseObservation.face
                )
            } else {
                result = blendWholeFaceLegacy(
                    source: sourceFrame.frame.image,
                    target: result,
                    sourceBoundingBox: bestObservation.face.boundingBox,
                    targetBoundingBox: baseObservation.face.boundingBox
                )
            }
        }

        return result
    }

    private func blendEyeRegion(
        source: CIImage,
        target: CIImage,
        sourceFace: DetectedFace,
        targetFace: DetectedFace
    ) -> CIImage {
        guard
            let sourceLandmarks = sourceFace.landmarks,
            let targetLandmarks = targetFace.landmarks,
            let sourceLeftEye = sourceLandmarks.leftEye,
            let sourceRightEye = sourceLandmarks.rightEye,
            let targetLeftEye = targetLandmarks.leftEye,
            let targetRightEye = targetLandmarks.rightEye
        else {
            return target
        }

        let sourceLeftPoints = landmarkPoints(
            region: sourceLeftEye,
            faceBox: sourceFace.boundingBox,
            imageExtent: source.extent
        )
        let sourceRightPoints = landmarkPoints(
            region: sourceRightEye,
            faceBox: sourceFace.boundingBox,
            imageExtent: source.extent
        )
        let targetLeftPoints = landmarkPoints(
            region: targetLeftEye,
            faceBox: targetFace.boundingBox,
            imageExtent: target.extent
        )
        let targetRightPoints = landmarkPoints(
            region: targetRightEye,
            faceBox: targetFace.boundingBox,
            imageExtent: target.extent
        )

        guard
            sourceLeftPoints.count >= 4,
            sourceRightPoints.count >= 4,
            targetLeftPoints.count >= 4,
            targetRightPoints.count >= 4
        else {
            return target
        }

        let sourceLeftCenter = averagePoint(sourceLeftPoints)
        let sourceRightCenter = averagePoint(sourceRightPoints)
        let targetLeftCenter = averagePoint(targetLeftPoints)
        let targetRightCenter = averagePoint(targetRightPoints)
        let sourceEyeDistance = distance(sourceLeftCenter, sourceRightCenter)
        let targetEyeDistance = distance(targetLeftCenter, targetRightCenter)

        guard sourceEyeDistance > 4, targetEyeDistance > 4 else { return target }

        let scaleRatio = targetEyeDistance / sourceEyeDistance
        guard scaleRatio >= 0.85, scaleRatio <= 1.18 else { return target }

        let sourceAngle = atan2(
            sourceRightCenter.y - sourceLeftCenter.y,
            sourceRightCenter.x - sourceLeftCenter.x
        )
        let targetAngle = atan2(
            targetRightCenter.y - targetLeftCenter.y,
            targetRightCenter.x - targetLeftCenter.x
        )
        guard angleDifference(sourceAngle, targetAngle) <= 0.20 else { return target }

        let leftBlended = blendSingleEyeRegion(
            source: source,
            target: target,
            sourceEyePoints: sourceLeftPoints,
            targetEyePoints: targetLeftPoints,
            sourceFaceBox: sourceFace.boundingBox,
            targetFaceBox: targetFace.boundingBox
        )

        return blendSingleEyeRegion(
            source: source,
            target: leftBlended,
            sourceEyePoints: sourceRightPoints,
            targetEyePoints: targetRightPoints,
            sourceFaceBox: sourceFace.boundingBox,
            targetFaceBox: targetFace.boundingBox
        )
    }

    private func blendSingleEyeRegion(
        source: CIImage,
        target: CIImage,
        sourceEyePoints: [CGPoint],
        targetEyePoints: [CGPoint],
        sourceFaceBox: CGRect,
        targetFaceBox: CGRect
    ) -> CIImage {
        guard
            let sourceAxis = eyeAxis(from: sourceEyePoints),
            let targetAxis = eyeAxis(from: targetEyePoints)
        else {
            return target
        }

        let sourceEyeWidth = distance(sourceAxis.start, sourceAxis.end)
        let targetEyeWidth = distance(targetAxis.start, targetAxis.end)

        guard sourceEyeWidth > 4, targetEyeWidth > 4 else { return target }

        let scaleRatio = targetEyeWidth / sourceEyeWidth
        guard scaleRatio >= 0.82, scaleRatio <= 1.22 else { return target }
        guard angleDifference(sourceAxis.angle, targetAxis.angle) <= 0.18 else { return target }

        let sourcePatchRect = makeSingleEyeRect(
            eyePoints: sourceEyePoints,
            faceBox: sourceFaceBox,
            imageExtent: source.extent,
            horizontalPaddingRatio: singleEyePatchHorizontalPaddingRatio,
            verticalPaddingRatio: singleEyePatchVerticalPaddingRatio
        )
        let targetSampleRect = makeSingleEyeRect(
            eyePoints: targetEyePoints,
            faceBox: targetFaceBox,
            imageExtent: target.extent,
            horizontalPaddingRatio: singleEyePatchHorizontalPaddingRatio,
            verticalPaddingRatio: singleEyePatchVerticalPaddingRatio
        )
        let targetMaskRect = makeSingleEyeRect(
            eyePoints: targetEyePoints,
            faceBox: targetFaceBox,
            imageExtent: target.extent,
            horizontalPaddingRatio: singleEyeMaskHorizontalPaddingRatio,
            verticalPaddingRatio: singleEyeMaskVerticalPaddingRatio
        )

        guard
            sourcePatchRect.width > 6,
            sourcePatchRect.height > 6,
            targetSampleRect.width > 6,
            targetSampleRect.height > 6,
            targetMaskRect.width > 4,
            targetMaskRect.height > 4
        else {
            return target
        }

        let transform = similarityTransform(
            sourceLeft: sourceAxis.start,
            sourceRight: sourceAxis.end,
            targetLeft: targetAxis.start,
            targetRight: targetAxis.end
        )
        let transformedPatch = source
            .cropped(to: sourcePatchRect)
            .transformed(by: transform)
        let colorMatchedPatch = matchPatchColor(
            sourcePatch: transformedPatch,
            targetImage: target,
            sampleRect: targetSampleRect
        )
        let featherRadius = max(
            singleEyeBlendMinFeather,
            min(singleEyeBlendMaxFeather, targetMaskRect.height * 0.20)
        )
        let mask = createFeatheredSingleEyeMask(
            rect: targetMaskRect,
            imageExtent: target.extent,
            featherRadius: featherRadius
        )

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = colorMatchedPatch
        blendFilter.backgroundImage = target
        blendFilter.maskImage = mask

        return blendFilter.outputImage?.cropped(to: target.extent) ?? target
    }

    private func blendWholeFaceLegacy(
        source: CIImage,
        target: CIImage,
        sourceBoundingBox: CGRect,
        targetBoundingBox: CGRect
    ) -> CIImage {
        let sourceExtent = source.extent
        let targetExtent = target.extent
        let sourceFaceRect = pixelRect(from: sourceBoundingBox, in: sourceExtent)
        let targetFaceRect = pixelRect(from: targetBoundingBox, in: targetExtent)
        let sourcePatchRect = paddedPatchRect(from: sourceFaceRect, in: sourceExtent)
        let targetPatchRect = paddedPatchRect(from: targetFaceRect, in: targetExtent)

        guard !sourcePatchRect.isEmpty, !targetPatchRect.isEmpty else { return target }

        let sourcePatch = source.cropped(to: sourcePatchRect)
        let scaleX = targetPatchRect.width / sourcePatchRect.width
        let scaleY = targetPatchRect.height / sourcePatchRect.height
        let transform = CGAffineTransform(
            translationX: targetPatchRect.minX - sourcePatchRect.minX * scaleX,
            y: targetPatchRect.minY - sourcePatchRect.minY * scaleY
        ).scaledBy(x: scaleX, y: scaleY)
        let transformedSourcePatch = sourcePatch.transformed(by: transform)
        let mask = createFeatheredEllipseMask(rect: targetPatchRect, imageExtent: targetExtent)

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = transformedSourcePatch
        blendFilter.backgroundImage = target
        blendFilter.maskImage = mask

        return blendFilter.outputImage?.cropped(to: targetExtent) ?? target
    }

    private func paddedPatchRect(from rect: CGRect, in imageExtent: CGRect) -> CGRect {
        rect.insetBy(
            dx: -rect.width * 0.22,
            dy: -rect.height * 0.28
        ).intersection(imageExtent)
    }

    private func landmarkPoints(
        region: VNFaceLandmarkRegion2D,
        faceBox: CGRect,
        imageExtent: CGRect
    ) -> [CGPoint] {
        region.normalizedPoints.map { point in
            let normalizedX = faceBox.minX + point.x * faceBox.width
            let normalizedY = faceBox.minY + point.y * faceBox.height

            return CGPoint(
                x: imageExtent.minX + normalizedX * imageExtent.width,
                y: imageExtent.minY + normalizedY * imageExtent.height
            )
        }
    }

    private func makeEyeBandRect(
        leftEyePoints: [CGPoint],
        rightEyePoints: [CGPoint],
        faceBox: CGRect,
        imageExtent: CGRect
    ) -> CGRect {
        let allPoints = leftEyePoints + rightEyePoints
        guard !allPoints.isEmpty else { return .zero }

        let minX = allPoints.map(\.x).min() ?? 0
        let maxX = allPoints.map(\.x).max() ?? 0
        let minY = allPoints.map(\.y).min() ?? 0
        let maxY = allPoints.map(\.y).max() ?? 0
        var eyeRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        let faceRect = pixelRect(from: faceBox, in: imageExtent)
        let horizontalPadding = eyeRect.width * eyeBandHorizontalPaddingRatio
        let verticalPadding = max(
            eyeRect.height * eyeBandVerticalPaddingRatio,
            faceRect.height * 0.045
        )

        eyeRect = eyeRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return eyeRect.intersection(imageExtent)
    }

    private func makeSingleEyeRect(
        eyePoints: [CGPoint],
        faceBox: CGRect,
        imageExtent: CGRect,
        horizontalPaddingRatio: CGFloat,
        verticalPaddingRatio: CGFloat
    ) -> CGRect {
        guard !eyePoints.isEmpty else { return .zero }

        let minX = eyePoints.map(\.x).min() ?? 0
        let maxX = eyePoints.map(\.x).max() ?? 0
        let minY = eyePoints.map(\.y).min() ?? 0
        let maxY = eyePoints.map(\.y).max() ?? 0
        var eyeRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        let faceRect = pixelRect(from: faceBox, in: imageExtent)
        let horizontalPadding = eyeRect.width * horizontalPaddingRatio
        let verticalPadding = max(
            eyeRect.height * verticalPaddingRatio,
            faceRect.height * 0.018
        )

        eyeRect = eyeRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return eyeRect.intersection(imageExtent)
    }

    private func eyeAxis(from points: [CGPoint]) -> (start: CGPoint, end: CGPoint, angle: CGFloat)? {
        guard points.count >= 2 else { return nil }

        var bestPair: (CGPoint, CGPoint)?
        var bestDistance: CGFloat = 0

        for firstIndex in points.indices {
            for secondIndex in points.indices where secondIndex > firstIndex {
                let firstPoint = points[firstIndex]
                let secondPoint = points[secondIndex]
                let currentDistance = distance(firstPoint, secondPoint)

                if currentDistance > bestDistance {
                    bestDistance = currentDistance
                    bestPair = (firstPoint, secondPoint)
                }
            }
        }

        guard var pair = bestPair, bestDistance > 0.001 else { return nil }

        if pair.0.x > pair.1.x {
            pair = (pair.1, pair.0)
        }

        return (
            start: pair.0,
            end: pair.1,
            angle: atan2(pair.1.y - pair.0.y, pair.1.x - pair.0.x)
        )
    }

    private func similarityTransform(
        sourceLeft: CGPoint,
        sourceRight: CGPoint,
        targetLeft: CGPoint,
        targetRight: CGPoint
    ) -> CGAffineTransform {
        let sourceMid = averagePoint([sourceLeft, sourceRight])
        let targetMid = averagePoint([targetLeft, targetRight])
        let sourceVector = CGPoint(
            x: sourceRight.x - sourceLeft.x,
            y: sourceRight.y - sourceLeft.y
        )
        let targetVector = CGPoint(
            x: targetRight.x - targetLeft.x,
            y: targetRight.y - targetLeft.y
        )
        let sourceLength = hypot(sourceVector.x, sourceVector.y)
        let targetLength = hypot(targetVector.x, targetVector.y)

        guard sourceLength > 0.001 else { return .identity }

        let scale = targetLength / sourceLength
        let sourceAngle = atan2(sourceVector.y, sourceVector.x)
        let targetAngle = atan2(targetVector.y, targetVector.x)
        let angle = targetAngle - sourceAngle
        let a = cos(angle) * scale
        let b = sin(angle) * scale
        let c = -sin(angle) * scale
        let d = cos(angle) * scale
        let tx = targetMid.x - (a * sourceMid.x + c * sourceMid.y)
        let ty = targetMid.y - (b * sourceMid.x + d * sourceMid.y)

        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    private func matchPatchColor(
        sourcePatch: CIImage,
        targetImage: CIImage,
        sampleRect: CGRect
    ) -> CIImage {
        guard
            let sourceAverage = averageRGB(of: sourcePatch, in: sampleRect),
            let targetAverage = averageRGB(of: targetImage, in: sampleRect)
        else {
            return sourcePatch
        }

        let rBias = clamp(targetAverage.r - sourceAverage.r, -colorMatchMaxBias, colorMatchMaxBias)
        let gBias = clamp(targetAverage.g - sourceAverage.g, -colorMatchMaxBias, colorMatchMaxBias)
        let bBias = clamp(targetAverage.b - sourceAverage.b, -colorMatchMaxBias, colorMatchMaxBias)

        return sourcePatch.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: rBias, y: gBias, z: bBias, w: 0),
            ]
        )
    }

    private func averageRGB(of image: CIImage, in rect: CGRect) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let extent = rect.intersection(image.extent)
        guard extent.width > 1, extent.height > 1 else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = image.cropped(to: extent)
        filter.extent = extent

        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return (
            r: CGFloat(bitmap[0]) / 255,
            g: CGFloat(bitmap[1]) / 255,
            b: CGFloat(bitmap[2]) / 255
        )
    }

    private func createFeatheredEyeBandMask(
        rect: CGRect,
        imageExtent: CGRect,
        featherRadius: CGFloat
    ) -> CIImage {
        let width = Int(imageExtent.width.rounded())
        let height = Int(imageExtent.height.rounded())

        guard width > 0, height > 0 else {
            return CIImage(color: .black).cropped(to: imageExtent)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let maskImage = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let flippedRect = CGRect(
                x: rect.minX - imageExtent.minX,
                y: imageExtent.height - (rect.maxY - imageExtent.minY),
                width: rect.width,
                height: rect.height
            )
            let cornerRadius = min(flippedRect.width, flippedRect.height) * 0.45
            let path = UIBezierPath(roundedRect: flippedRect, cornerRadius: cornerRadius)

            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
        }

        guard let cgMask = maskImage.cgImage else {
            return CIImage(color: .black).cropped(to: imageExtent)
        }

        let hardMask = CIImage(cgImage: cgMask).transformed(
            by: CGAffineTransform(translationX: imageExtent.minX, y: imageExtent.minY)
        )
        return hardMask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius])
            .cropped(to: imageExtent)
    }

    private func createFeatheredSingleEyeMask(
        rect: CGRect,
        imageExtent: CGRect,
        featherRadius: CGFloat
    ) -> CIImage {
        let baseSize = CGSize(width: 256, height: 160)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: baseSize, format: format)
        let maskImage = renderer.image { context in
            let cgContext = context.cgContext
            let baseRect = CGRect(origin: .zero, size: baseSize)
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fill(baseRect)

            let insetRect = baseRect.insetBy(dx: baseSize.width * 0.12, dy: baseSize.height * 0.20)
            let path = UIBezierPath(
                roundedRect: insetRect,
                cornerRadius: min(insetRect.width, insetRect.height) * 0.48
            )
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
        }

        guard let cgMask = maskImage.cgImage else {
            return CIImage(color: .black).cropped(to: imageExtent)
        }

        let scaleX = rect.width / baseSize.width
        let scaleY = rect.height / baseSize.height
        let maskTransform = CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: scaleY,
            tx: rect.minX,
            ty: rect.minY
        )
        let mask = CIImage(cgImage: cgMask).transformed(by: maskTransform)
        let blackBackground = CIImage(color: .black).cropped(to: imageExtent)
        let featheredMask = mask.composited(over: blackBackground)

        return featheredMask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius])
            .cropped(to: imageExtent)
    }

    private func pixelRect(from normalizedRect: CGRect, in imageExtent: CGRect) -> CGRect {
        CGRect(
            x: imageExtent.minX + normalizedRect.minX * imageExtent.width,
            y: imageExtent.minY + normalizedRect.minY * imageExtent.height,
            width: normalizedRect.width * imageExtent.width,
            height: normalizedRect.height * imageExtent.height
        )
    }

    private func createFeatheredEllipseMask(rect: CGRect, imageExtent: CGRect) -> CIImage {
        let baseSize: CGFloat = 1024
        let baseRect = CGRect(x: 0, y: 0, width: baseSize, height: baseSize)
        let blurRadius = max(2, min(rect.width, rect.height) * 0.035)
        let radialGradient = CIFilter.radialGradient()
        radialGradient.center = CGPoint(x: baseRect.midX, y: baseRect.midY)
        radialGradient.radius0 = Float(baseSize * 0.34)
        radialGradient.radius1 = Float(baseSize * 0.48)
        radialGradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        radialGradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let ellipseTransform = CGAffineTransform(
            a: rect.width / baseSize,
            b: 0,
            c: 0,
            d: rect.height / baseSize,
            tx: rect.minX,
            ty: rect.minY
        )
        let ellipseMask = (radialGradient.outputImage ?? CIImage(color: .black))
            .cropped(to: baseRect)
            .transformed(by: ellipseTransform)

        let blackBackground = CIImage(color: .black).cropped(to: imageExtent)
        let featheredMask = ellipseMask.composited(over: blackBackground)
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = featheredMask
        blurFilter.radius = Float(blurRadius)

        return (blurFilter.outputImage ?? featheredMask).cropped(to: imageExtent)
    }

    private func renderUIImage(from ciImage: CIImage) throws -> UIImage {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.composeFailed
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return sqrt(dx * dx + dy * dy)
    }

    private func averagePoint(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }

        return CGPoint(
            x: total.x / CGFloat(points.count),
            y: total.y / CGFloat(points.count)
        )
    }

    private func angleDifference(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let difference = abs(first - second).truncatingRemainder(dividingBy: .pi * 2)
        return min(difference, .pi * 2 - difference)
    }

    private func normalizedScore(_ value: Float, from minimumValue: Float, to maximumValue: Float) -> Float {
        guard maximumValue > minimumValue else { return 0 }
        return clamp((value - minimumValue) / (maximumValue - minimumValue), 0, 1)
    }

    private func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    private func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }
}
