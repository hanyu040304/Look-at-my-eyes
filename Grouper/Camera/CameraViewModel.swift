import AVFoundation
import Combine
import CoreImage
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class CameraViewModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    let burstStore = BurstFrameStore()

    @Published var authorizationState: CameraAuthorizationState = .unknown
    @Published var captureState: CaptureState = .idle
    @Published var cameraPosition: CameraPosition = .back
    @Published var selectedZoom: ZoomOption = .oneX
    @Published var availableZoomOptions: [ZoomOption] = []
    @Published var selectedPhotoResolution: PhotoResolutionOption = .twentyFourMP
    @Published var availablePhotoResolutionOptions: [PhotoResolutionOption] = [.twoMP, .twentyFourMP]
    @Published var orientation: CaptureOrientation = .portrait
    @Published var showBurstGallery = false
    @Published var showResultPreview = false
    @Published var latestResult: ProcessingResult?
    @Published var errorMessage: String?
    @Published var isSessionRunning = false

    private struct PendingCapture {
        let supportingFrames: [CapturedFrame]
        let galleryFrames: [BurstFrame]
        let orientation: CaptureOrientation
        let cameraPosition: CameraPosition
        let zoomFactor: CGFloat
        let photoResolution: PhotoResolutionOption
        let highResolutionFrameIndex: Int
    }

    private struct PhotoLibraryImage {
        let image: UIImage
        let metadata: PhotoCaptureMetadata?
        let role: String
    }

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.look-at-my-eyes.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.look-at-my-eyes.camera.video")
    private let frameBufferQueue = DispatchQueue(label: "com.look-at-my-eyes.camera.frames")
    private let frameRenderContext = CIContext(options: [.useSoftwareRenderer: false])
    private let groupPhotoProcessor = GroupPhotoProcessor()

    private var isConfigured = false
    private var activeCameraInput: AVCaptureDeviceInput?
    private var activeCamera: AVCaptureDevice?
    private var pendingCapture: PendingCapture?
    private var orientationObserver: NSObjectProtocol?
    private var burstFrames: [CapturedFrame] = []
    private var lastBurstFrameTimestamp: TimeInterval = 0
    private var nextFrameIndex = 0
    private var isCollectingBurst = false
    private var burstStartedAt: TimeInterval = 0
    private var lastSelectedBackZoom: CGFloat = 1

    private let burstDuration: TimeInterval = 1.2
    private let burstFrameInterval: TimeInterval = 0.12
    private let processedFrameLongSide: CGFloat = 1920

    var canCapture: Bool {
        authorizationState == .authorized && isSessionRunning && !captureState.isBusy
    }

    var canChangeCameraSettings: Bool {
        authorizationState == .authorized && isSessionRunning && !captureState.isBusy
    }

    var burstFrameCount: Int {
        burstStore.count
    }

    func start() async {
        startOrientationUpdates()

        let isAuthorized = await requestCameraAccess()
        guard isAuthorized else {
            authorizationState = .denied
            errorMessage = "需要相机权限"
            return
        }

        authorizationState = .authorized

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.configureSessionIfNeeded()

            if self.isConfigured, !self.session.isRunning {
                self.session.startRunning()
            }

            let didStart = self.session.isRunning
            DispatchQueue.main.async {
                self.isSessionRunning = didStart
                if !didStart {
                    self.errorMessage = "相机启动失败，请重新打开应用"
                }
            }
        }
    }

    func stop() {
        stopOrientationUpdates()

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func startBurstCapture() {
        guard canCapture else { return }

        let lockedOrientation = lockedCaptureOrientation()
        orientation = lockedOrientation
        captureState = .capturing(progress: 0)
        errorMessage = nil
        resetBurstBuffer()

        frameBufferQueue.async { [weak self] in
            guard let self else { return }
            self.isCollectingBurst = true
            self.burstStartedAt = CACurrentMediaTime()
            self.lastBurstFrameTimestamp = 0
            self.nextFrameIndex = 0
        }

        Task { [weak self] in
            guard let self else { return }

            let start = Date()
            while Date().timeIntervalSince(start) < self.burstDuration {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let progress = min(Date().timeIntervalSince(start) / self.burstDuration, 1)
                await MainActor.run {
                    self.captureState = .capturing(progress: progress)
                }
            }

            await MainActor.run {
                self.finishBurstCapture(orientation: lockedOrientation)
            }
        }
    }

    func selectZoom(_ option: ZoomOption) {
        guard canChangeCameraSettings else { return }

        if cameraPosition == .front {
            selectedZoom = option
            return
        }

        switchCamera(to: .back, preferredZoom: option.factor)
    }

    func flipCamera() {
        guard canChangeCameraSettings else { return }

        let nextPosition: CameraPosition = cameraPosition == .back ? .front : .back
        switchCamera(to: nextPosition, preferredZoom: 1)
    }

    func cyclePhotoResolution() {
        guard canChangeCameraSettings else { return }
        guard !availablePhotoResolutionOptions.isEmpty else { return }

        let currentIndex = availablePhotoResolutionOptions.firstIndex(of: selectedPhotoResolution) ?? 0
        let nextIndex = availablePhotoResolutionOptions.index(after: currentIndex)
        selectedPhotoResolution = availablePhotoResolutionOptions[
            nextIndex == availablePhotoResolutionOptions.endIndex ? availablePhotoResolutionOptions.startIndex : nextIndex
        ]
    }

    func openBurstGallery() {
        guard burstStore.hasFrames else {
            showToast("暂无连拍帧")
            return
        }

        showBurstGallery = true
    }

    func saveOptimizedResult() {
        guard let latestResult else { return }
        saveImagesToPhotoLibrary([
            PhotoLibraryImage(
                image: latestResult.optimizedOutput,
                metadata: latestResult.captureMetadata,
                role: "optimized"
            )
        ]) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showToast("已保存结果")
                case .failure(let error):
                    self?.showToast(error.localizedDescription)
                }
            }
        }
    }

    func saveDirectAndOptimizedResult() {
        guard let latestResult else { return }
        saveImagesToPhotoLibrary([
            PhotoLibraryImage(
                image: latestResult.directOutput,
                metadata: latestResult.captureMetadata,
                role: "direct"
            ),
            PhotoLibraryImage(
                image: latestResult.optimizedOutput,
                metadata: latestResult.captureMetadata,
                role: "optimized"
            ),
        ]) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showToast("已保存原图和优化图")
                case .failure(let error):
                    self?.showToast(error.localizedDescription)
                }
            }
        }
    }

    func clearLatestBurst() {
        burstStore.clear()
    }

    func showToast(_ message: String) {
        errorMessage = message

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                if self?.errorMessage == message {
                    self?.errorMessage = nil
                }
            }
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let camera = preferredCamera(for: .back, zoom: 1) else {
            DispatchQueue.main.async {
                self.errorMessage = "没有找到可用摄像头"
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            configureVideoOutput()

            guard
                session.canAddInput(input),
                session.canAddOutput(videoOutput),
                session.canAddOutput(photoOutput)
            else {
                DispatchQueue.main.async {
                    self.errorMessage = "相机配置失败"
                }
                return
            }

            session.addInput(input)
            session.addOutput(videoOutput)
            session.addOutput(photoOutput)
            activeCameraInput = input
            activeCamera = camera
            configurePhotoOutput(for: camera)
            configureOutputConnections(for: camera)
            updateZoomOptions(for: .back, camera: camera, selectedFactor: 1)
            updatePhotoResolutionOptions(for: camera)
            isConfigured = true
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "相机配置失败：\(error.localizedDescription)"
            }
        }
    }

    private func configureVideoOutput() {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
    }

    private func configurePhotoOutput(for camera: AVCaptureDevice) {
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let dimensions = largestPhotoDimensions(for: camera) {
            photoOutput.maxPhotoDimensions = dimensions
        }
    }

    private func configureOutputConnections(for camera: AVCaptureDevice) {
        if let videoConnection = videoOutput.connection(with: .video),
           videoConnection.isVideoMirroringSupported {
            videoConnection.automaticallyAdjustsVideoMirroring = false
            videoConnection.isVideoMirrored = false
        }

        guard let photoConnection = photoOutput.connection(with: .video) else { return }

        if photoConnection.isVideoMirroringSupported {
            photoConnection.automaticallyAdjustsVideoMirroring = false
            photoConnection.isVideoMirrored = false
        }
    }

    private func finishBurstCapture(orientation: CaptureOrientation) {
        captureState = .processing

        frameBufferQueue.sync {
            isCollectingBurst = false
        }

        let supportingFrames = burstFrameSnapshot()
        guard supportingFrames.count >= 4 else {
            captureState = .failed("连拍帧不足")
            showToast("请保持相机打开，稍后再拍")
            resetCaptureStateAfterDelay()
            return
        }

        let galleryFrames = makeGalleryFrames(from: supportingFrames)
        burstStore.replace(with: galleryFrames)

        guard let camera = activeCamera else {
            processCapturedFrames(
                baseFrame: supportingFrames.last,
                supportingFrames: supportingFrames,
                galleryFrames: galleryFrames
            )
            return
        }

        pendingCapture = PendingCapture(
            supportingFrames: supportingFrames,
            galleryFrames: galleryFrames,
            orientation: orientation,
            cameraPosition: cameraPosition,
            zoomFactor: selectedZoom.factor,
            photoResolution: selectedPhotoResolution,
            highResolutionFrameIndex: (supportingFrames.map(\.frameIndex).max() ?? supportingFrames.count - 1) + 1
        )

        let settings = makePhotoSettings(for: camera)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func processCapturedFrames(
        baseFrame: CapturedFrame?,
        supportingFrames: [CapturedFrame],
        galleryFrames: [BurstFrame]
    ) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let result: ProcessingResult
                if let baseFrame {
                    result = try await self.groupPhotoProcessor.process(
                        baseFrame: baseFrame,
                        supportingFrames: supportingFrames
                    )
                } else {
                    result = try await self.groupPhotoProcessor.process(frames: supportingFrames)
                }

                await MainActor.run {
                    self.latestResult = result
                    self.burstStore.replace(with: galleryFrames)
                    self.captureState = .completed
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.showResultPreview = true
                    self.resetCaptureStateAfterDelay()
                }
            } catch {
                await MainActor.run {
                    self.captureState = .failed(error.localizedDescription)
                    self.showToast("处理失败：\(error.localizedDescription)")
                    self.resetCaptureStateAfterDelay()
                }
            }
        }
    }

    private func resetCaptureStateAfterDelay() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            await MainActor.run {
                if self?.captureState == .completed {
                    self?.captureState = .idle
                }
                if case .failed = self?.captureState {
                    self?.captureState = .idle
                }
            }
        }
    }

    private func switchCamera(to position: CameraPosition, preferredZoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }

            guard let camera = self.preferredCamera(for: position.avPosition, zoom: preferredZoom) else {
                DispatchQueue.main.async {
                    self.showToast("没有找到可用摄像头")
                }
                return
            }

            if self.cameraPosition == position,
               let activeCamera = self.activeCamera,
               activeCamera.uniqueID == camera.uniqueID {
                self.applyZoom(preferredZoom, to: activeCamera)
                self.updateZoomOptions(for: position, camera: activeCamera, selectedFactor: preferredZoom)
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: camera)
                let previousInput = self.activeCameraInput

                self.session.beginConfiguration()

                if let previousInput {
                    self.session.removeInput(previousInput)
                }

                guard self.session.canAddInput(newInput) else {
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                    }
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.showToast("摄像头切换失败")
                    }
                    return
                }

                self.session.addInput(newInput)
                self.activeCameraInput = newInput
                self.activeCamera = camera
                self.configurePhotoOutput(for: camera)
                self.configureOutputConnections(for: camera)
                self.session.commitConfiguration()
                self.resetBurstBuffer()
                self.applyZoom(preferredZoom, to: camera)
                self.updateZoomOptions(for: position, camera: camera, selectedFactor: preferredZoom)
                self.updatePhotoResolutionOptions(for: camera)
            } catch {
                DispatchQueue.main.async {
                    self.showToast("摄像头切换失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func preferredCamera(
        for position: AVCaptureDevice.Position,
        zoom: CGFloat
    ) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        let deviceTypes: [AVCaptureDevice.DeviceType]
        if zoom <= 0.75 {
            deviceTypes = [.builtInUltraWideCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        } else if zoom >= 5 {
            deviceTypes = [.builtInTelephotoCamera, .builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera]
        } else {
            deviceTypes = [.builtInWideAngleCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
        }

        for deviceType in deviceTypes {
            if let camera = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                return camera
            }
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func updateZoomOptions(
        for position: CameraPosition,
        camera: AVCaptureDevice,
        selectedFactor: CGFloat
    ) {
        let options: [ZoomOption]

        if position == .front {
            options = [
                ZoomOption(label: "1x", factor: 1, preferredDeviceType: .builtInWideAngleCamera)
            ]
        } else {
            let candidates = [
                ZoomOption(label: "0.5x", factor: 0.5, preferredDeviceType: .builtInUltraWideCamera),
                ZoomOption(label: "1x", factor: 1, preferredDeviceType: .builtInWideAngleCamera),
                ZoomOption(label: "2x", factor: 2, preferredDeviceType: .builtInWideAngleCamera),
                ZoomOption(label: "5x", factor: 5, preferredDeviceType: .builtInTelephotoCamera),
            ]

            options = candidates.filter { option in
                isZoomOptionAvailable(option, on: camera)
            }
        }

        let selected = options.first { abs($0.factor - selectedFactor) < 0.01 }
            ?? options.first { abs($0.factor - 1) < 0.01 }
            ?? options.first
            ?? .oneX

        DispatchQueue.main.async {
            self.cameraPosition = position
            self.availableZoomOptions = options
            self.selectedZoom = selected

            if position == .back {
                self.lastSelectedBackZoom = selected.factor
            }
        }
    }

    private func updatePhotoResolutionOptions(for camera: AVCaptureDevice) {
        let options = availablePhotoResolutionOptions(for: camera)

        DispatchQueue.main.async {
            self.availablePhotoResolutionOptions = options
            if !options.contains(self.selectedPhotoResolution) {
                self.selectedPhotoResolution = options.last ?? .twoMP
            }
        }
    }

    private func availablePhotoResolutionOptions(for camera: AVCaptureDevice) -> [PhotoResolutionOption] {
        let maxPixelCount = supportedPhotoDimensions(for: camera)
            .map(pixelCount)
            .max() ?? 0

        let options = PhotoResolutionOption.allCases.filter { option in
            switch option {
            case .twoMP:
                return true
            case .twentyFourMP, .fortyEightMP:
                return maxPixelCount >= Int64(Double(option.targetPixelCount) * 0.82)
            }
        }

        return options.isEmpty ? [.twoMP] : options
    }

    private func isZoomSupported(_ displayZoom: CGFloat, by camera: AVCaptureDevice) -> Bool {
        let actualZoom = actualZoomFactor(for: displayZoom, on: camera)
        return actualZoom >= camera.minAvailableVideoZoomFactor - 0.01
            && actualZoom <= camera.maxAvailableVideoZoomFactor + 0.01
    }

    private func isZoomOptionAvailable(_ option: ZoomOption, on camera: AVCaptureDevice) -> Bool {
        if abs(option.factor - 0.5) < 0.01 {
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
        }

        if abs(option.factor - 5) < 0.01 {
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil
                || isZoomSupported(option.factor, by: camera)
        }

        return isZoomSupported(option.factor, by: camera)
    }

    private func applyZoom(_ displayZoom: CGFloat, to camera: AVCaptureDevice) {
        let actualZoom = actualZoomFactor(for: displayZoom, on: camera)
        let clampedZoom = min(max(actualZoom, camera.minAvailableVideoZoomFactor), camera.maxAvailableVideoZoomFactor)

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            camera.videoZoomFactor = clampedZoom
        } catch {
            DispatchQueue.main.async {
                self.showToast("焦段切换失败")
            }
        }
    }

    private func actualZoomFactor(for displayZoom: CGFloat, on camera: AVCaptureDevice) -> CGFloat {
        displayZoom / displayZoomMultiplier(for: camera)
    }

    private func displayZoomFactor(for actualZoom: CGFloat, on camera: AVCaptureDevice) -> CGFloat {
        actualZoom * displayZoomMultiplier(for: camera)
    }

    private func displayZoomMultiplier(for camera: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            return max(camera.displayVideoZoomFactorMultiplier, 0.0001)
        }

        return 1
    }

    private func makePhotoSettings(for camera: AVCaptureDevice) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality

        if let dimensions = photoDimensions(for: selectedPhotoResolution, on: camera) {
            settings.maxPhotoDimensions = dimensions
        }

        return settings
    }

    private func largestPhotoDimensions(for camera: AVCaptureDevice) -> CMVideoDimensions? {
        supportedPhotoDimensions(for: camera).max { first, second in
            Int64(first.width) * Int64(first.height) < Int64(second.width) * Int64(second.height)
        }
    }

    private func supportedPhotoDimensions(for camera: AVCaptureDevice) -> [CMVideoDimensions] {
        camera.activeFormat.supportedMaxPhotoDimensions.sorted { first, second in
            pixelCount(first) < pixelCount(second)
        }
    }

    private func photoDimensions(
        for resolution: PhotoResolutionOption,
        on camera: AVCaptureDevice
    ) -> CMVideoDimensions? {
        let dimensions = supportedPhotoDimensions(for: camera)
        guard !dimensions.isEmpty else { return nil }

        if resolution == .twoMP {
            return dimensions.first
        }

        let targetPixelCount = resolution.targetPixelCount
        return dimensions.min { first, second in
            abs(pixelCount(first) - targetPixelCount) < abs(pixelCount(second) - targetPixelCount)
        }
    }

    private func pixelCount(_ dimensions: CMVideoDimensions) -> Int64 {
        Int64(dimensions.width) * Int64(dimensions.height)
    }

    private func makeCaptureMetadata(
        camera: AVCaptureDevice?,
        orientation: CaptureOrientation,
        cameraPosition: CameraPosition,
        displayZoomFactor: CGFloat,
        photoResolution: PhotoResolutionOption,
        capturedAt: Date = Date(),
        sourceImageMetadata: [String: Any]? = nil,
        photoPixelWidth: Int? = nil,
        photoPixelHeight: Int? = nil
    ) -> PhotoCaptureMetadata {
        let formatDimensions = camera.map {
            CMVideoFormatDescriptionGetDimensions($0.activeFormat.formatDescription)
        }
        let exposureDuration = camera
            .map { CMTimeGetSeconds($0.exposureDuration) }
            .flatMap { $0.isFinite ? $0 : nil }

        return PhotoCaptureMetadata(
            capturedAt: capturedAt,
            cameraPosition: cameraPosition,
            orientation: orientation,
            displayZoomFactor: displayZoomFactor,
            actualZoomFactor: camera?.videoZoomFactor ?? displayZoomFactor,
            photoResolution: photoResolution,
            lensModel: camera?.localizedName,
            cameraDeviceType: camera?.deviceType.rawValue,
            cameraUniqueID: camera?.uniqueID,
            videoFieldOfView: camera?.activeFormat.videoFieldOfView,
            sensorWidth: formatDimensions?.width,
            sensorHeight: formatDimensions?.height,
            photoPixelWidth: photoPixelWidth,
            photoPixelHeight: photoPixelHeight,
            iso: camera?.iso,
            exposureDuration: exposureDuration,
            sourceImageMetadata: sourceImageMetadata
        )
    }

    private func resetBurstBuffer() {
        frameBufferQueue.async { [weak self] in
            self?.burstFrames.removeAll()
            self?.lastBurstFrameTimestamp = 0
            self?.nextFrameIndex = 0
        }
    }

    private func burstFrameSnapshot() -> [CapturedFrame] {
        frameBufferQueue.sync {
            burstFrames
        }
    }

    private func appendBurstFrame(_ frame: CapturedFrame) {
        burstFrames.append(frame)
        if burstFrames.count > 12 {
            burstFrames.removeFirst(burstFrames.count - 12)
        }
    }

    private func makeGalleryFrames(from frames: [CapturedFrame]) -> [BurstFrame] {
        frames.compactMap { frame in
            guard let image = uiImage(from: frame.image) else { return nil }

            return BurstFrame(
                image: image,
                timestamp: frame.timestamp,
                frameIndex: frame.frameIndex,
                orientation: frame.orientation,
                cameraPosition: frame.cameraPosition,
                zoomFactor: frame.zoomFactor
            )
        }
    }

    private func uiImage(from image: CIImage) -> UIImage? {
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        guard let cgImage = frameRenderContext.createCGImage(normalized, from: normalized.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func stableProcessingImage(
        from image: CIImage,
        orientation: CaptureOrientation,
        cameraPosition: CameraPosition
    ) -> CIImage? {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let scale = longSide > processedFrameLongSide ? processedFrameLongSide / longSide : 1
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let orientedImage = normalizedImage(
            scaledImage,
            for: orientation,
            cameraPosition: cameraPosition
        )

        guard let cgImage = frameRenderContext.createCGImage(orientedImage, from: orientedImage.extent) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func normalizedImage(
        _ image: CIImage,
        for orientation: CaptureOrientation,
        cameraPosition: CameraPosition
    ) -> CIImage {
        let zeroBasedImage = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
        )
        let orientedImage = zeroBasedImage.oriented(
            cgImagePropertyOrientation(for: orientation, cameraPosition: cameraPosition)
        )
        return orientedImage.transformed(
            by: CGAffineTransform(translationX: -orientedImage.extent.minX, y: -orientedImage.extent.minY)
        )
    }

    private func photoOutputImage(
        from image: CIImage,
        for resolution: PhotoResolutionOption
    ) -> CIImage {
        let image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let pixelCount = image.extent.width * image.extent.height
        let targetPixelCount = CGFloat(resolution.targetPixelCount)

        guard pixelCount > targetPixelCount * 1.12 else { return image }

        let scale = sqrt(targetPixelCount / pixelCount)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaledImage.transformed(
            by: CGAffineTransform(translationX: -scaledImage.extent.minX, y: -scaledImage.extent.minY)
        )
    }

    private func cgImagePropertyOrientation(
        for orientation: CaptureOrientation,
        cameraPosition: CameraPosition
    ) -> CGImagePropertyOrientation {
        switch cameraPosition {
        case .back:
            return backCameraImageOrientation(for: orientation)
        case .front:
            return frontCameraImageOrientation(for: orientation)
        }
    }

    private func backCameraImageOrientation(for orientation: CaptureOrientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .portrait:
            return .right
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        }
    }

    private func frontCameraImageOrientation(for orientation: CaptureOrientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .portrait:
            return .leftMirrored
        case .landscapeLeft:
            return .downMirrored
        case .landscapeRight:
            return .upMirrored
        }
    }

    private func saveImagesToPhotoLibrary(
        _ photos: [PhotoLibraryImage],
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard !photos.isEmpty else {
            completion(.success(0))
            return
        }

        let fileURLs: [URL]
        do {
            fileURLs = try photos.map { try makePhotoLibraryFile(for: $0) }
        } catch {
            completion(.failure(error))
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.removeTemporaryFiles(fileURLs)
                completion(.failure(PhotoExportError.notAuthorized))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                for (index, fileURL) in fileURLs.enumerated() {
                    let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                    request?.creationDate = photos[index].metadata?.capturedAt
                }
            } completionHandler: { success, error in
                self.removeTemporaryFiles(fileURLs)
                if success {
                    completion(.success(photos.count))
                } else {
                    completion(.failure(error ?? PhotoExportError.failed))
                }
            }
        }
    }

    private func makePhotoLibraryFile(for photo: PhotoLibraryImage) throws -> URL {
        guard let cgImage = photo.image.cgImage else {
            throw PhotoExportError.failed
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Grouper-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoExportError.failed
        }

        let metadata = makeImageMetadata(for: photo)
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PhotoExportError.failed
        }

        return fileURL
    }

    private func makeImageMetadata(for photo: PhotoLibraryImage) -> [String: Any] {
        let metadata = photo.metadata
        let captureDate = metadata?.capturedAt ?? Date()
        let dateString = imageMetadataDateString(from: captureDate)
        let imageDescription = imageMetadataDescription(for: photo)

        var imageProperties = metadata?.sourceImageMetadata ?? [:]
        imageProperties[kCGImagePropertyOrientation as String] = CGImagePropertyOrientation.up.rawValue
        imageProperties[kCGImageDestinationLossyCompressionQuality as String] = 1.0

        var exif = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = exif[kCGImagePropertyExifDateTimeOriginal as String] ?? dateString
        exif[kCGImagePropertyExifDateTimeDigitized as String] = exif[kCGImagePropertyExifDateTimeDigitized as String] ?? dateString
        exif[kCGImagePropertyExifUserComment as String] = imageDescription

        if let photoPixelWidth = metadata?.photoPixelWidth, let photoPixelHeight = metadata?.photoPixelHeight {
            exif[kCGImagePropertyExifPixelXDimension as String] = photoPixelWidth
            exif[kCGImagePropertyExifPixelYDimension as String] = photoPixelHeight
        }

        if exif[kCGImagePropertyExifLensModel as String] == nil, let lensModel = metadata?.lensModel {
            exif[kCGImagePropertyExifLensModel as String] = lensModel
        }

        if let iso = metadata?.iso {
            exif[kCGImagePropertyExifISOSpeedRatings as String] = exif[kCGImagePropertyExifISOSpeedRatings as String] ?? [Int(iso.rounded())]
        }

        if let exposureDuration = metadata?.exposureDuration {
            exif[kCGImagePropertyExifExposureTime as String] = exif[kCGImagePropertyExifExposureTime as String] ?? exposureDuration
        }

        var tiff = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFDateTime as String] = tiff[kCGImagePropertyTIFFDateTime as String] ?? dateString
        tiff[kCGImagePropertyTIFFSoftware as String] = "Grouper"
        tiff[kCGImagePropertyTIFFImageDescription as String] = imageDescription

        imageProperties[kCGImagePropertyExifDictionary as String] = exif
        imageProperties[kCGImagePropertyTIFFDictionary as String] = tiff
        return imageProperties
    }

    private func imageMetadataDescription(for photo: PhotoLibraryImage) -> String {
        guard let metadata = photo.metadata else {
            return "Grouper \(photo.role) photo"
        }

        let exposureDescription = metadata.exposureDuration.map {
            String(format: "%.6fs", $0)
        } ?? "unknown"
        let isoDescription = metadata.iso.map {
            String(format: "%.0f", $0)
        } ?? "unknown"
        let fieldOfViewDescription = metadata.videoFieldOfView.map {
            String(format: "%.1f", $0)
        } ?? "unknown"
        let sensorDescription: String
        if let sensorWidth = metadata.sensorWidth, let sensorHeight = metadata.sensorHeight {
            sensorDescription = "\(sensorWidth)x\(sensorHeight)"
        } else {
            sensorDescription = "unknown"
        }
        let photoPixelDescription: String
        if let photoPixelWidth = metadata.photoPixelWidth, let photoPixelHeight = metadata.photoPixelHeight {
            photoPixelDescription = "\(photoPixelWidth)x\(photoPixelHeight)"
        } else {
            photoPixelDescription = "unknown"
        }

        return [
            "Grouper \(photo.role) photo",
            "cameraPosition=\(metadata.cameraPosition.title)",
            "orientation=\(metadata.orientation.rawValue)",
            "photoResolution=\(metadata.photoResolution.label)",
            String(format: "displayZoom=%.2fx", metadata.displayZoomFactor),
            String(format: "actualZoom=%.2fx", metadata.actualZoomFactor),
            "lensModel=\(metadata.lensModel ?? "unknown")",
            "deviceType=\(metadata.cameraDeviceType ?? "unknown")",
            "deviceUniqueID=\(metadata.cameraUniqueID ?? "unknown")",
            "fieldOfView=\(fieldOfViewDescription)",
            "sensorDimensions=\(sensorDescription)",
            "photoPixels=\(photoPixelDescription)",
            "iso=\(isoDescription)",
            "exposure=\(exposureDescription)",
        ].joined(separator: "; ")
    }

    private func imageMetadataDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func removeTemporaryFiles(_ fileURLs: [URL]) {
        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func startOrientationUpdates() {
        guard orientationObserver == nil else { return }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        if let initialOrientation = currentCaptureOrientation() {
            orientation = initialOrientation
        }

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.captureState.isBusy else { return }

            guard let nextOrientation = self.currentCaptureOrientation() else { return }
            guard nextOrientation != self.orientation else { return }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                self.orientation = nextOrientation
            }
        }
    }

    private func stopOrientationUpdates() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }

        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func currentCaptureOrientation() -> CaptureOrientation? {
        if let physicalOrientation = currentPhysicalCaptureOrientation() { return physicalOrientation }

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { CaptureOrientation(interfaceOrientation: $0.effectiveGeometry.interfaceOrientation) }
            .first
    }

    private func currentPhysicalCaptureOrientation() -> CaptureOrientation? {
        CaptureOrientation(deviceOrientation: UIDevice.current.orientation)
    }

    private func lockedCaptureOrientation() -> CaptureOrientation {
        currentPhysicalCaptureOrientation() ?? orientation
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let pendingCapture else {
            captureState = .failed("照片读取失败")
            resetCaptureStateAfterDelay()
            return
        }

        self.pendingCapture = nil

        if let error {
            showToast("高清拍摄失败：\(error.localizedDescription)")
            processCapturedFrames(
                baseFrame: pendingCapture.supportingFrames.last,
                supportingFrames: pendingCapture.supportingFrames,
                galleryFrames: pendingCapture.galleryFrames
            )
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let image = CIImage(data: data, options: [.applyOrientationProperty: false])
        else {
            processCapturedFrames(
                baseFrame: pendingCapture.supportingFrames.last,
                supportingFrames: pendingCapture.supportingFrames,
                galleryFrames: pendingCapture.galleryFrames
            )
            return
        }

        let highResolutionImage = normalizedImage(
            image,
            for: pendingCapture.orientation,
            cameraPosition: pendingCapture.cameraPosition
        )
        let outputImage = photoOutputImage(
            from: highResolutionImage,
            for: pendingCapture.photoResolution
        )
        let highResolutionMetadata = makeCaptureMetadata(
            camera: activeCamera,
            orientation: pendingCapture.orientation,
            cameraPosition: pendingCapture.cameraPosition,
            displayZoomFactor: pendingCapture.zoomFactor,
            photoResolution: pendingCapture.photoResolution,
            sourceImageMetadata: photo.metadata,
            photoPixelWidth: Int(outputImage.extent.width.rounded()),
            photoPixelHeight: Int(outputImage.extent.height.rounded())
        )
        let highResolutionFrame = CapturedFrame(
            image: outputImage,
            timestamp: Date().timeIntervalSince1970,
            frameIndex: pendingCapture.highResolutionFrameIndex,
            orientation: pendingCapture.orientation,
            cameraPosition: pendingCapture.cameraPosition,
            zoomFactor: pendingCapture.zoomFactor,
            captureMetadata: highResolutionMetadata
        )

        processCapturedFrames(
            baseFrame: highResolutionFrame,
            supportingFrames: pendingCapture.supportingFrames,
            galleryFrames: pendingCapture.galleryFrames
        )
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameBufferQueue.async { [weak self] in
            guard let self, self.isCollectingBurst else { return }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp - self.lastBurstFrameTimestamp >= self.burstFrameInterval else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            self.lastBurstFrameTimestamp = timestamp

            let currentOrientation = self.orientation
            let currentCameraPosition = self.cameraPosition
            let currentZoom = self.selectedZoom.factor
            let captureMetadata = self.makeCaptureMetadata(
                camera: self.activeCamera,
                orientation: currentOrientation,
                cameraPosition: currentCameraPosition,
                displayZoomFactor: currentZoom,
                photoResolution: self.selectedPhotoResolution
            )
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let image = self.stableProcessingImage(
                from: rawImage,
                orientation: currentOrientation,
                cameraPosition: currentCameraPosition
            ) else { return }

            let frame = CapturedFrame(
                image: image,
                timestamp: CACurrentMediaTime() - self.burstStartedAt,
                frameIndex: self.nextFrameIndex,
                orientation: currentOrientation,
                cameraPosition: currentCameraPosition,
                zoomFactor: currentZoom,
                captureMetadata: captureMetadata
            )
            self.nextFrameIndex += 1
            self.appendBurstFrame(frame)
        }
    }
}
