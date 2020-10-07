//Created 29/8/20

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("settings.read")) {
                ReadSettings()
            }
            Section(header: Text("settings.host")) {
                NavigationLink(destination: LANraragiConfigView()) {
                    Text("settings.host.config")
                    .padding()
                }
            }
            Section(header: Text("settings.view")) {
                ViewSettings()
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
