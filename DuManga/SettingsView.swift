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
                // swiftlint:disable force_cast
                let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                let build = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
                // swiftlint:enable force_cast
                LabeledContent("version", value: "\(version)-\(build)")
                    .padding()
            }

        }
    }
}
