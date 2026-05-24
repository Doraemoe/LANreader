import SwiftUI

struct LoadingView: View {

    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .frame(width: 54, height: 54)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.86), in: Circle())

                Text("loading")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(width: panelWidth)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 14)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityElement(children: .combine)
    }

    private var panelWidth: CGFloat {
        let availableWidth = max(geometry.size.width - 32, 0)
        let preferredWidth = min(max(geometry.size.width * 0.52, 220), 340)
        return min(preferredWidth, availableWidth)
    }
}
