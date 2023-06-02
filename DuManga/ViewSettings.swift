// Created 1/9/20

import SwiftUI

struct ViewSettings: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false
    @AppStorage(SettingsKey.enablePasscode) var enablePasscode: Bool = false
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    @State var showPasscodeView: Bool = false
    @State var passcodeToVerify = ""

    var body: some View {
        List {
            Toggle(isOn: self.$useListView) {
                Text("settings.archive.list.view")
            }
            .padding()
            Toggle(isOn: self.$blurInterfaceWhenInactive, label: {
                Text("settings.view.blur.inactive")
            })
            .padding()
            Toggle(isOn: self.$enablePasscode, label: {
                Text("settings.view.passcode")
            })
            .padding()
        }
        .onAppear {
            if enablePasscode && storedPasscode.isEmpty {
                enablePasscode = false
            } else if !enablePasscode && !storedPasscode.isEmpty {
                enablePasscode = true
            }
        }
        .onChange(of: enablePasscode) { [enablePasscode] _ in
            if enablePasscode && storedPasscode.isEmpty {
                //
            } else if !enablePasscode && !storedPasscode.isEmpty {
                //
            } else {
                showPasscodeView = true
            }
        }
        .fullScreenCover(isPresented: $showPasscodeView) {
            LockScreen(
                initialState: storedPasscode.isEmpty ? LockScreenState.new : LockScreenState.remove,
                storedPasscode: storedPasscode
            ) { passcode, state, act in
                if state == .new {
                    passcodeToVerify = passcode
                    act(true)
                } else if state == .verify {
                    if passcode == passcodeToVerify {
                        storedPasscode = passcode
                        act(true)
                        passcodeToVerify = ""
                        showPasscodeView = false
                    } else {
                        passcodeToVerify = ""
                        act(false)
                    }
                } else if state == .remove {
                    if passcode == storedPasscode {
                        storedPasscode = ""
                        act(true)
                        showPasscodeView = false
                    } else {
                        act(false)
                    }
                }
            }
        }
    }
}
