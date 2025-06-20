import SwiftUI
import ComposableArchitecture

struct AdvancedSettings: View {
    @Environment(NavigationHelper.self) private var navigation

    var body: some View {
        Button {
            let store = Store(initialState: TranslationConfigFeature.State()) {
                TranslationConfigFeature()
            }
            navigation.push(UITranslationConfigController(store: store, navigation: navigation))
        } label: {
            HStack {
                Text("settings.advanced.translation")
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
