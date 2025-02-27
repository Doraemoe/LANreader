import SwiftUI
import ComposableArchitecture

struct ServerSettings: View {
    @Environment(NavigationHelper.self) private var navigation

    var body: some View {
        Button {
            let store = Store(initialState: LANraragiConfigFeature.State()) {
                LANraragiConfigFeature()
            }
            navigation.push(UILANraragiConfigViewController(store: store, navigation: navigation))
        } label: {
            HStack {
                Text("settings.host.config")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()

        Button {
            let store = Store(initialState: UploadFeature.State()) {
                UploadFeature()
            }
            navigation.push(UIUploadViewController(store: store))
        } label: {
            HStack {
                Text("settings.host.upload")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
    }
}
