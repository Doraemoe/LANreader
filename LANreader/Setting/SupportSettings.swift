import ComposableArchitecture
import SwiftUI

struct SupportSettings: View {
    @Environment(NavigationHelper.self) private var navigation

    var body: some View {
        Button {
            let store = Store(initialState: SupportFeature.State()) {
                SupportFeature()
            }
            navigation.push(UISupportViewController(store: store))
        } label: {
            HStack {
                Text("settings.support.title")
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
