import AVKit
import SwiftUI
import UIKit

struct GroupCameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        GeometryReader { proxy in
            let placement = CaptureDockPlacement()

            ZStack {
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()

                previewShade

                CaptureControlDock(viewModel: viewModel)
                    .padding(placement.insets(for: proxy.safeAreaInsets))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)

                if viewModel.authorizationState == .denied {
                    PermissionOverlay()
                }

                if let message = viewModel.errorMessage {
                    ToastView(message: message)
                        .padding(.bottom, 128)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: viewModel.orientation)
            .animation(.easeInOut(duration: 0.18), value: viewModel.errorMessage)
        }
        .task {
            await viewModel.start()
        }
        .onCameraCaptureEvent(isEnabled: viewModel.authorizationState == .authorized) { event in
            guard event.phase == .ended else { return }
            viewModel.startBurstCapture()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $viewModel.showBurstGallery) {
            BurstFramesGalleryView(
                store: viewModel.burstStore,
                onExportAll: {
                    viewModel.burstStore.exportAll { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let count):
                                viewModel.showToast(count == 0 ? "暂无连拍帧" : "已导出 \(count) 张")
                            case .failure(let error):
                                viewModel.showToast(error.localizedDescription)
                            }
                        }
                    }
                },
                onDelete: {
                    viewModel.clearLatestBurst()
                },
                onUseForProcessing: {
                    viewModel.showToast("已使用最近连拍帧")
                }
            )
        }
        .sheet(isPresented: $viewModel.showResultPreview) {
            if let result = viewModel.latestResult {
                ResultPreviewView(
                    result: result,
                    burstFrameCount: viewModel.burstFrameCount,
                    onSave: { viewModel.saveOptimizedResult() },
                    onSaveBoth: { viewModel.saveDirectAndOptimizedResult() },
                    onShowMe: { viewModel.openBurstGallery() },
                    onRetake: { viewModel.latestResult = nil }
                )
            }
        }
    }

    private var previewShade: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.18),
                .clear,
                .clear,
                .black.opacity(0.52),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct CaptureDockPlacement {
    var alignment: Alignment {
        .bottom
    }

    func insets(for safeArea: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: 0, leading: 18, bottom: max(14, safeArea.bottom + 8), trailing: 18)
    }
}

private struct CaptureControlDock: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 13) {
            ZoomSelectorView(
                options: viewModel.availableZoomOptions,
                selected: viewModel.selectedZoom,
                rotationAngle: viewModel.orientation.rotationAngle,
                isEnabled: viewModel.canChangeCameraSettings
            ) { option in
                viewModel.selectZoom(option)
            }

            HStack(spacing: 28) {
                ShowMeButton(viewModel: viewModel, size: 54)

                CaptureButton(
                    state: viewModel.captureState,
                    diameter: 74,
                    rotationAngle: viewModel.orientation.rotationAngle
                ) {
                    viewModel.startBurstCapture()
                }

                HStack(spacing: 12) {
                    PhotoResolutionButton(viewModel: viewModel, size: 54)

                    CameraToolButton(
                        systemName: "camera.rotate",
                        isEnabled: viewModel.canChangeCameraSettings,
                        size: 54,
                        rotationAngle: viewModel.orientation.rotationAngle
                    ) {
                        viewModel.flipCamera()
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.orientation)
    }
}

private struct PhotoResolutionButton: View {
    @ObservedObject var viewModel: CameraViewModel
    let size: CGFloat

    var body: some View {
        CameraToolButton(
            systemName: "camera.aperture",
            title: viewModel.selectedPhotoResolution.label,
            isEnabled: viewModel.canChangeCameraSettings && !viewModel.availablePhotoResolutionOptions.isEmpty,
            size: size,
            rotationAngle: viewModel.orientation.rotationAngle
        ) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.cyclePhotoResolution()
        }
        .accessibilityLabel("照片规格 \(viewModel.selectedPhotoResolution.label)")
    }
}

private struct ShowMeButton: View {
    @ObservedObject var viewModel: CameraViewModel
    let size: CGFloat

    var body: some View {
        CameraToolButton(
            systemName: "rectangle.stack.fill",
            isEnabled: true,
            badge: viewModel.burstFrameCount > 0 ? viewModel.burstFrameCount : nil,
            size: size,
            rotationAngle: viewModel.orientation.rotationAngle
        ) {
            viewModel.openBurstGallery()
        }
        .opacity(viewModel.burstFrameCount > 0 ? 1 : 0.46)
    }
}

private struct PermissionOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
            Text("需要相机权限")
                .font(.system(size: 18, weight: .semibold))
            Text("用于拍摄多帧合影并在本地完成优化处理")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.yellow, in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(28)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.46), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 24)
    }
}
