import SwiftUI

struct ServerSettings: View {

    var body: some View {
        List {
            NavigationLink("settings.host.config", state: SettingsFeature.Path.State.lanraragiSettings(.init()) )
                .padding()
            NavigationLink("settings.host.upload", state: SettingsFeature.Path.State.upload(.init()))
                .padding()
        }
    }
}
