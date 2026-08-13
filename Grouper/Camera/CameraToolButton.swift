import SwiftUI

struct CameraToolButton: View {
    let systemName: String
    var title: String? = nil
    var isSelected = false
    var isEnabled = true
    var badge: Int? = nil
    var size: CGFloat = 44
    var rotationAngle: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: size / 2, style: .continuous)
                    .fill(.black.opacity(isSelected ? 0.46 : 0.32))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: size / 2, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size / 2, style: .continuous)
                            .stroke(.white.opacity(isSelected ? 0.28 : 0.14), lineWidth: 1)
                    )

                VStack(spacing: 2) {
                    Image(systemName: systemName)
                        .font(.system(size: title == nil ? size * 0.36 : size * 0.31, weight: .semibold))
                        .frame(height: title == nil ? size * 0.48 : size * 0.32)

                    if let title {
                        Text(title)
                            .font(.system(size: size * 0.15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                }
                .foregroundStyle(isSelected ? .yellow : .white)
                .frame(width: size * 0.82, height: size * 0.82)
                .rotationEffect(rotationAngle)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rotationAngle)

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.yellow, in: Capsule())
                        .frame(width: size, height: size, alignment: .topTrailing)
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.42)
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

struct CameraGlassCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.30), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }
}
