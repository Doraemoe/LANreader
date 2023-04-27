// Created 29/8/20

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("settings.read")) {
                ReadSettings()
            }
            Section(header: Text("settings.host")) {
                ServerSettings()
            }
            Section(header: Text("settings.view")) {
                ViewSettings()
            }
            Section(header: Text("settings.database")) {
                DatabaseSettings()
            }
            Section(header: Text("settings.debug")) {
                NavigationLink(
                    destination: LogView(),
                    label: {
                        Text("settings.debug.log")
                    }).padding()
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
