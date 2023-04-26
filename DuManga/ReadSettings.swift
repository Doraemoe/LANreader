// Created 29/8/20

import SwiftUI

struct ReadSettings: View {
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.swipeLeftKey) var swipeLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.swipeRightKey) var swipeRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.verticalReader) var verticalReader: Bool = false

    var body: some View {
        let pageControlSelectionView = Group {
            Text("settings.nextPage").tag(PageControl.next.rawValue)
            Text("settings.previousPage").tag(PageControl.previous.rawValue)
            Text("settings.navigation").tag(PageControl.navigation.rawValue)
        }
        return List {
            Picker("settings.read.tap.left", selection: self.$tapLeft) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.tap.middle", selection: self.$tapMiddle) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.tap.right", selection: self.$tapRight) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.swipe.left", selection: self.$swipeLeft) {
                pageControlSelectionView
            }
                    .padding()
            Picker("settings.read.swipe.right", selection: self.$swipeRight) {
                pageControlSelectionView
            }
                    .padding()
            Toggle(isOn: self.$verticalReader) {
                Text("settings.read.vertical")
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
