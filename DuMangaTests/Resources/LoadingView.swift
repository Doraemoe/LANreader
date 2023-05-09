import SwiftUI

struct LoadingView: View {

    let geometry: GeometryProxy

    var body: some View {
        VStack {
            ProgressView("loading")
        }
                .frame(width: geometry.size.width / 3,
                        height: geometry.size.height / 5)
                .background(Color.secondary)
                .foregroundColor(Color.primary)
                .cornerRadius(20)
    }
}
