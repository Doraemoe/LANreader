import ComposableArchitecture
import SwiftUI

struct ServerSettings: View {

    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    var body: some View {
        List {
            NavigationLink("settings.host.config", state: SettingsFeature.Path.State.lanraragiSettings(.init()) )
                .padding()
            Toggle(isOn: self.$alwaysLoadFromServer) {
                Text("settings.host.alwaysLoad")
            }
            .padding()
            NavigationLink("settings.host.upload", state: SettingsFeature.Path.State.upload(.init()))
                .padding()
        }
    }
}
