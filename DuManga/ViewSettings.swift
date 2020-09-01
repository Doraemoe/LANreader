//Created 1/9/20

import SwiftUI

struct ViewSettings: View {
    var body: some View {
        List {
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: SettingsKey.archiveListRandom) },
                set: {
                    UserDefaults.standard.set($0, forKey: SettingsKey.archiveListRandom)
            })) {
                Text("settings.archive.list.random")
            }
            .padding()
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: SettingsKey.useListView) },
                set: {
                    UserDefaults.standard.set($0, forKey: SettingsKey.useListView)
            })) {
                Text("settings.archive.list.view")
            }
            .padding()
        }
    }
}

struct ViewSettings_Previews: PreviewProvider {
    static var previews: some View {
        ViewSettings()
    }
}
