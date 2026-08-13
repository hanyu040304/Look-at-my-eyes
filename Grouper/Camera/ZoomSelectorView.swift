import SwiftUI

struct ZoomSelectorView: View {
    let options: [ZoomOption]
    let selected: ZoomOption
    var rotationAngle: Angle = .zero
    var isEnabled = true
    let onSelect: (ZoomOption) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 5) {
            optionButtons
        }
        .padding(5)
        .background(.black.opacity(0.32), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.46)
        .allowsHitTesting(isEnabled)
        .animation(.easeInOut(duration: 0.22), value: selected.id)
    }

    @ViewBuilder
    private var optionButtons: some View {
        ForEach(options) { option in
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelect(option)
            } label: {
                ZStack {
                    if selected.isSelected(comparedTo: option) {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 34, height: 34)
                            .matchedGeometryEffect(id: "zoom-selection", in: selectionNamespace)
                    }

                    Text(option.label)
                        .font(.system(size: 14, weight: selected.isSelected(comparedTo: option) ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(selected.isSelected(comparedTo: option) ? .black : .white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: 34, height: 34)
                }
                .rotationEffect(rotationAngle)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rotationAngle)
                .frame(width: 52, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("焦段 \(option.label)")
        }
    }
}
