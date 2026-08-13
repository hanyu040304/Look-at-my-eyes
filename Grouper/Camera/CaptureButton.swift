import SwiftUI

struct CaptureButton: View {
    let state: CaptureState
    var diameter: CGFloat = 74
    var rotationAngle: Angle = .zero
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            guard !state.isBusy else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 5)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(isPressed ? 1.06 : 1)

                Circle()
                    .fill(.white)
                    .frame(width: innerDiameter, height: innerDiameter)
                    .scaleEffect(isPressed ? 0.92 : 1)

                stateIcon
                    .rotationEffect(rotationAngle)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rotationAngle)
            }
            .frame(width: diameter + 8, height: diameter + 8)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !state.isBusy else { return }
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        isPressed = false
                    }
                }
        )
        .animation(.easeInOut(duration: 0.18), value: state)
    }

    private var innerDiameter: CGFloat {
        switch state {
        case .capturing, .processing:
            return diameter - 20
        case .completed:
            return diameter - 16
        case .idle, .failed:
            return diameter - 12
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .capturing:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.black.opacity(0.82))
                .frame(width: 18, height: 18)
        case .processing:
            ProgressView()
                .tint(.black)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.black)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }
}
