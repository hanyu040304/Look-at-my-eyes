import SwiftUI

struct BurstFramesGalleryView: View {
    @ObservedObject var store: BurstFrameStore
    let onExportAll: () -> Void
    let onDelete: () -> Void
    let onUseForProcessing: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                thumbnailTimeline
                actionBar
            }
            .background(.black)
            .navigationTitle("Show Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedFrame: BurstFrame? {
        guard store.frames.indices.contains(selectedIndex) else { return store.frames.first }
        return store.frames[selectedIndex]
    }

    private var firstTimestamp: TimeInterval? {
        store.frames.first?.timestamp
    }

    @ViewBuilder
    private var previewArea: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Color.black

                if let selectedFrame {
                    Image(uiImage: selectedFrame.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    frameInfo(for: selectedFrame)
                        .padding(16)
                } else {
                    Text("暂无连拍帧")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func frameInfo(for frame: BurstFrame) -> some View {
        let elapsed = frame.elapsedTime(from: firstTimestamp)

        return VStack(alignment: .leading, spacing: 4) {
            Text("第 \(selectedIndex + 1) / \(store.frames.count) 帧")
                .font(.system(size: 13, weight: .semibold))
            Text(String(format: "+%.2fs · %.1fx · %@", elapsed, frame.zoomFactor, frame.cameraPosition.title))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var thumbnailTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.frames.enumerated()), id: \.element.id) { index, frame in
                    Button {
                        selectedIndex = index
                    } label: {
                        Image(uiImage: frame.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(index == selectedIndex ? .white : .white.opacity(0.12), lineWidth: index == selectedIndex ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.black.opacity(0.94))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("删除本次连拍") {
                onDelete()
                dismiss()
            }
            .buttonStyle(GalleryActionButtonStyle(role: .destructive))

            Button("导出全部") {
                onExportAll()
            }
            .buttonStyle(GalleryActionButtonStyle(role: .normal))

            Button("用于处理") {
                onUseForProcessing()
                dismiss()
            }
            .buttonStyle(GalleryActionButtonStyle(role: .prominent))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.black)
    }
}

private struct GalleryActionButtonStyle: ButtonStyle {
    enum Role {
        case normal
        case prominent
        case destructive
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }

    private var foregroundColor: Color {
        switch role {
        case .prominent:
            return .black
        case .destructive:
            return .red
        case .normal:
            return .white
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .prominent:
            return .yellow
        case .destructive:
            return .red.opacity(0.14)
        case .normal:
            return .white.opacity(0.12)
        }
    }
}
