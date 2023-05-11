import SwiftUI

struct ServerSettings: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    var body: some View {
        List {
            NavigationLink(destination: LANraragiConfigView(notLoggedIn: Binding.constant(false))) {
                Text("settings.host.config")
            }
                    .padding()
            Toggle(isOn: self.$alwaysLoadFromServer) {
                Text("settings.host.alwaysLoad")
            }
                    .padding()
            NavigationLink(destination: UploadView()) {
                Text("settings.host.upload")
            }
                    .padding()
        }
    }
}
