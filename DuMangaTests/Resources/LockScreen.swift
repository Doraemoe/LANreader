//
//  LockScreen.swift
//  DuManga
//

import SwiftUI
import NotificationBannerSwift
import LocalAuthentication

struct LockScreen: View {
    @Environment(\.scenePhase) var scenePhase

    @State var lockScreenModel = LockScreenModel()

    let initialState: LockScreenState
    let storedPasscode: String
    var handler: (String, LockScreenState, (Bool) -> Void) -> Void

    var body: some View {
        VStack(spacing: 40) {
            Text(NSLocalizedString("lock.label.\(lockScreenModel.state.rawValue)",
                                   comment: "Force use NSLocalizedString")).font(.title)
            ZStack {
                pinDots
                backgroundField
            }
            showPinStack
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active
                && lockScreenModel.state == .normal
                && !lockScreenModel.isAuthenticating
                && !lockScreenModel.disableBiometricsAuth {
                lockScreenModel.isAuthenticating = true
                authenticate()
                lockScreenModel.isAuthenticating = false
            }
        }
        .onAppear(perform: {
            lockScreenModel.state = initialState
            if scenePhase == .active
                && lockScreenModel.state == .normal
                && !lockScreenModel.isAuthenticating
                && !lockScreenModel.disableBiometricsAuth {
                lockScreenModel.isAuthenticating = true
                authenticate()
                lockScreenModel.isAuthenticating = false
            }
        })
        .onDisappear(perform: {
            lockScreenModel.unload()
        })
    }

    private var pinDots: some View {
        HStack {
            Spacer()
            ForEach(0..<6) { index in
                Image(systemName: self.getImageName(at: index))
                    .font(.system(size: 30, weight: .thin, design: .default))
                Spacer()
            }
        }
    }

    private var backgroundField: some View {
        TextField("", text: $lockScreenModel.pin, onCommit: submitPin)
            .accentColor(.clear)
            .foregroundColor(.clear)
            .keyboardType(.numberPad)
            .disabled(lockScreenModel.isDisabled)
            .onChange(of: lockScreenModel.pin) { oldPin, newPin in
                if newPin.last?.isWholeNumber == false {
                    lockScreenModel.pin = oldPin
                } else {
                    self.submitPin()
                }
            }
    }

    private var showPinStack: some View {
        HStack {
            Spacer()
            if !lockScreenModel.pin.isEmpty {
                showPinButton
            }
        }
        .frame(height: 20)
        .padding([.trailing])
    }

    private var showPinButton: some View {
        Button(action: {
            lockScreenModel.showPin.toggle()
        }, label: {
            lockScreenModel.showPin ?
            Image(systemName: "eye.slash.fill").foregroundColor(.primary) :
            Image(systemName: "eye.fill").foregroundColor(.primary)
        })
    }

    private func submitPin() {
        guard !lockScreenModel.pin.isEmpty else {
            lockScreenModel.showPin = false
            return
        }

        if lockScreenModel.pin.count == 6 {
            lockScreenModel.isDisabled = true
            handler(lockScreenModel.pin, lockScreenModel.state) { isSuccess in
                if isSuccess && lockScreenModel.state == .new {
                    lockScreenModel.switchToVerify()
                } else if !isSuccess {
                    if lockScreenModel.state == .verify {
                        lockScreenModel.revertBackToNew()
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                        subtitle: NSLocalizedString("error.passcode.verify",
                                                                                    comment: "passcode verify error"),
                                                        style: .danger)
                        banner.show()
                    } else {
                        lockScreenModel.failed()
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                        subtitle: NSLocalizedString("error.passcode.mismatch",
                                                                                    comment: "passcode remove error"),
                                                        style: .danger)
                        banner.show()
                    }
                }
            }
        }

        // this code is never reached under  normal circumstances. If the user pastes a text with count higher than the
        // max digits, we remove the additional characters and make a recursive call.
        if lockScreenModel.pin.count > 6 {
            lockScreenModel.pin = String(lockScreenModel.pin.prefix(6))
            submitPin()
        }
    }

    private func getImageName(at index: Int) -> String {
        if index >= lockScreenModel.pin.count {
            return "circle"
        }

        if lockScreenModel.showPin {
            return lockScreenModel.pin.digits[index].numberString + ".circle"
        }

        return "circle.fill"
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = NSLocalizedString("lock.biometric.message", comment: "unlock")

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                if success {
                    handler(storedPasscode, lockScreenModel.state) { _ in
                    }
                } else {
                    // there was a problem
                    lockScreenModel.disableBiometricsAuth = true
                }
            }
        } else {
            // no biometrics
        }
    }
}

extension String {
    var digits: [Int] {
        var result = [Int]()
        for char in self {
            if let number = Int(String(char)) {
                result.append(number)
            }
        }
        return result
    }
}

extension Int {
    var numberString: String {
        guard self < 10 else { return "0" }
        return String(self)
    }
}
