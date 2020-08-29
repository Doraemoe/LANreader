//Created 29/8/20

import SwiftUI

struct ReadSettings: View {
    var body: some View {
        List {
            Picker("settings.read.tap.left", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: "settings.read.tap.left") as? String ?? "next") ?? .next },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: "settings.read.tap.left")
            }
            )) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.tap.middle", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: "settings.read.tap.middle") as? String ?? "navigation") ?? .navigation },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: "settings.read.tap.middle")
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.tap.right", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: "settings.read.tap.right") as? String ?? "previous") ?? .previous },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: "settings.read.tap.right")
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.swipe.left", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: "settings.read.swipe.left") as? String ?? "next") ?? .previous },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: "settings.read.swipe.left")
            })) {
                Text("settings.nextPage").tag(PageControl.next)
                Text("settings.previousPage").tag(PageControl.previous)
                Text("settings.navigation").tag(PageControl.navigation)
            }
            .padding()
            Picker("settings.read.swipe.right", selection: Binding(
                get: { PageControl(rawValue: UserDefaults.standard.object(forKey: "settings.read.swipe.right") as? String ?? "previous") ?? .previous },
                set: {
                    UserDefaults.standard.set($0.rawValue, forKey: "settings.read.swipe.right")
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
