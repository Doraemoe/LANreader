import ComposableArchitecture
import SwiftUI

struct ServerSettings: View {
    let store: StoreOf<SettingsFeature>
    
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false
    
    var body: some View {
        List {
            Button("settings.host.config") {
                self.store.send(.goToLANraragiSettings)
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
