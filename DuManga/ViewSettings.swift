//Created 1/9/20

import SwiftUI

struct ViewSettings: View {
    @AppStorage(SettingsKey.archiveListRandom) var archiveListRandom: Bool = false
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false

    var body: some View {
        List {
            Toggle(isOn: self.$archiveListRandom) {
                Text("settings.archive.list.random")
            }
            .padding()
            Toggle(isOn: self.$useListView) {
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
