//Created 29/8/20

import SwiftUI

struct ReadSettings: View {
    var body: some View {
        List {
            Picker("settings.read.tap.left", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: SettingsKey.tapLeftKey) as? String ?? PageControl.next.rawValue) ?? .next },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: SettingsKey.tapLeftKey)
            }
            )) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.tap.middle", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: SettingsKey.tapMiddleKey) as? String ?? PageControl.navigation.rawValue) ?? .navigation },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: SettingsKey.tapMiddleKey)
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.tap.right", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: SettingsKey.tapRightKey) as? String ?? PageControl.previous.rawValue) ?? .previous },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: SettingsKey.tapRightKey)
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.swipe.left", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: SettingsKey.swipeLeftKey) as? String ?? PageControl.next.rawValue) ?? .next },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: SettingsKey.swipeLeftKey)
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.swipe.right", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: SettingsKey.swipeRightKey) as? String ?? PageControl.previous.rawValue) ?? .previous },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: SettingsKey.swipeRightKey)
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
        }
    }
    
    func savePageControlSettings(value: PageControl, key: String) {
        UserDefaults.standard.set(value, forKey: key)
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
