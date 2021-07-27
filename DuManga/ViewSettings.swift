// Created 1/9/20

import SwiftUI

struct ViewSettings: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false

    var body: some View {
        List {
            Picker("settings.archive.list.order", selection: self.$archiveListOrder) {
                Group {
                    Text("settings.archive.list.order.name").tag(ArchiveListOrder.name.rawValue)
                    Text("settings.archive.list.order.dateAdded").tag(ArchiveListOrder.dateAdded.rawValue)
                    Text("settings.archive.list.order.random").tag(ArchiveListOrder.random.rawValue)
                }
            }
            .padding()
            Toggle(isOn: self.$useListView) {
                Text("settings.archive.list.view")
            }
            .padding()
            Toggle(isOn: self.$blurInterfaceWhenInactive, label: {
                Text("settings.view.blur.inactive")
            })
            .padding()
        }
    }
}

struct ViewSettings_Previews: PreviewProvider {
    static var previews: some View {
        ViewSettings()
    }
}
