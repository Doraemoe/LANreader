//Created 1/9/20

import SwiftUI

struct ViewSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Toggle(isOn: Binding(
                get: { self.store.state.setting.archiveListRandom },
                set: {
                    self.store.dispatch(.setting(action: .saveArchiveListRandomToUserDefaults(archiveListRandom: $0)))
            })) {
                Text("settings.archive.list.random")
            }
            .padding()
            Toggle(isOn: Binding(
                get: { self.store.state.setting.useListView },
                set: {
                    self.store.dispatch(.setting(action: .saveUseListViewToUserDefaults(useListView: $0)))
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
