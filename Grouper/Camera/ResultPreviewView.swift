import SwiftUI

struct ResultPreviewView: View {
    let result: ProcessingResult
    let burstFrameCount: Int
    let onSave: () -> Void
    let onSaveBoth: () -> Void
    let onShowMe: () -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: PreviewMode = .optimized

    private enum PreviewMode: String, CaseIterable {
        case original = "原图"
        case optimized = "优化后"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imagePreview
                comparisonControl
                infoPanel
                actionBar
            }
            .background(.black)
            .navigationTitle("结果预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("相机") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentImage: UIImage {
        selectedMode == .optimized ? result.optimizedOutput : result.directOutput
    }

    private var imagePreview: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Image(uiImage: currentImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var comparisonControl: some View {
        HStack(spacing: 6) {
            ForEach(PreviewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedMode == mode ? .black : .white.opacity(0.72))
                        .frame(width: 82, height: 34)
                        .background(selectedMode == mode ? .yellow : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.white.opacity(0.10), in: Capsule())
        .padding(.top, 12)
    }

    private var infoPanel: some View {
        HStack(spacing: 10) {
            metric(title: "识别人数", value: "\(result.totalPersons)")
            metric(title: "修复闭眼", value: "\(result.fixedCount)")
            metric(title: "处理耗时", value: String(format: "%.1fs", result.processingTime))
            metric(title: "连拍帧", value: "\(burstFrameCount)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("保存结果") {
                onSave()
            }
            .buttonStyle(ResultActionButtonStyle(kind: .prominent))

            Button("保存两张") {
                onSaveBoth()
            }
            .buttonStyle(ResultActionButtonStyle(kind: .normal))

            Button("Show Me") {
                onShowMe()
            }
            .buttonStyle(ResultActionButtonStyle(kind: .normal))

            Button("重拍") {
                onRetake()
                dismiss()
            }
            .buttonStyle(ResultActionButtonStyle(kind: .normal))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

private struct ResultActionButtonStyle: ButtonStyle {
    enum Kind {
        case normal
        case prominent
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(kind == .prominent ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(kind == .prominent ? .yellow : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
