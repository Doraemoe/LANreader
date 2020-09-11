//Created 29/8/20

import SwiftUI

struct ReadSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let pageControlSelectionView = Group {
            Text("settings.nextPage").tag(PageControl.next)
            Text("settings.previousPage").tag(PageControl.previous)
            Text("settings.navigation").tag(PageControl.navigation)
        }
        return List {
            Picker("settings.read.tap.left", selection: Binding(
                    get: { self.store.state.setting.tapLeft },
                    set: {
                        self.store.dispatch(.setting(action: .saveTapLeftControlToUserDefaults(control: $0)))
                    }
            )) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.tap.middle", selection: Binding(
                    get: { self.store.state.setting.tapMiddle },
                    set: {
                        self.store.dispatch(.setting(action: .saveTapMiddleControlToUserDefaults(control: $0)))
                    })) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.tap.right", selection: Binding(
                    get: { self.store.state.setting.tapRight },
                    set: {
                        self.store.dispatch(.setting(action: .saveTapRightControlToUserDefaults(control: $0)))
                    })) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.swipe.left", selection: Binding(
                    get: { self.store.state.setting.swipeLeft },
                    set: {
                        self.store.dispatch(.setting(action: .saveSwipeLeftControlToUserDefaults(control: $0)))
                    })) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.swipe.right", selection: Binding(
                    get: { self.store.state.setting.swipeRight },
                    set: {
                        self.store.dispatch(.setting(action: .saveSwipeRightControlToUserDefaults(control: $0)))
                    })) {
                pageControlSelectionView
            }
                    .padding()
            Toggle(isOn: Binding(
                    get: { self.store.state.setting.splitPage },
                    set: {
                        self.store.dispatch(.setting(action: .saveSplitPageToUserDefaults(split: $0)))
                    })) {
                Text("settings.read.split.page")
            }
                    .padding()
            Toggle(isOn: Binding(
                    get: { self.store.state.setting.splitPagePriorityLeft },
                    set: {
                        self.store.dispatch(.setting(action: .saveSplitPagePriorityLeftToUserDefaults(priorityLeft: $0)))
                    })) {
                Text("settings.read.split.page.priority.left")
            }
                    .padding()
        }
    }
}

struct ReadSettings_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Form {
                Section {
                    ReadSettings()
                }
            }
        }
                .navigationViewStyle(StackNavigationViewStyle())
    }
}
