import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import LocalAuthentication

@Reducer public struct LockScreenFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SettingsKey.passcode)) var passcode = ""

        var pin = ""
        var lockState = LockScreenState.normal
        var authenticating = false
        var disableBiometricsAuth = false
        var showPin = false
        var newPin = ""
        var errorMessage = ""
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case setPin(String)
        case setShowPin(Bool?)
        case submitPin
        case authenticate
        case authenticateResult(Bool)
        case setErrorMessage(String)

        case savePasscode(String)
    }

    @Dependency(\.dismiss) var dismiss

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .setPin(pin):
                state.pin = pin
                return .none
            case let .setShowPin(showPin):
                if let showPin = showPin {
                    state.showPin = showPin
                } else {
                    state.showPin.toggle()
                }
                return .none
            case .submitPin:
                guard !state.pin.isEmpty else {
                    state.showPin = false
                    return .none
                }

                if state.pin.count == 6 {
                    state.authenticating = true
                    switch state.lockState {
                    case .new:
                        state.newPin = state.pin
                        state.pin = ""
                        state.lockState = .verify
                    case .verify:
                        if state.pin == state.newPin {
                            return .run { [state] send in
                                await send(.savePasscode(state.pin))
                                await self.dismiss()
                            }
                        } else {
                            state.newPin = ""
                            state.pin = ""
                            state.lockState = .new
                            state.errorMessage = String(localized: "error.passcode.verify")
                        }
                    case .normal:
                        let storedPasscode = state.passcode
                        if storedPasscode == state.pin {
                            return .run { _ in
                                await self.dismiss()
                            }
                        } else {
                            state.pin = ""
                            state.errorMessage = String(localized: "error.passcode.mismatch")
                        }
                    case .remove:
                        let storedPasscode = state.passcode
                        if storedPasscode == state.pin {
                            return .run { send in
                                await send(.savePasscode(""))
                                await self.dismiss()
                            }
                        } else {
                            state.pin = ""
                            state.errorMessage = String(localized: "error.passcode.mismatch")
                        }
                    }
                }
                state.authenticating = false
                // this code is never reached under  normal circumstances. If the user pastes a text with count higher than the
                // max digits, we remove the additional characters and make a recursive call.
                if state.pin.count > 6 {
                    state.pin = String(state.pin.prefix(6))
                    return .send(.submitPin)
                }
                return .none
            case .authenticate:
                state.authenticating = true

                return .run {send in
                    let context = LAContext()
                    var error: NSError?

                    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                        let reason = String(localized: "lock.biometric.message")

                        do {
                            let isSuccess = try await context.evaluatePolicy(
                                .deviceOwnerAuthenticationWithBiometrics,
                                localizedReason: reason
                            )
                            if isSuccess {
                                await send(.authenticateResult(true))
                            } else {
                                await send(.authenticateResult(false))
                            }
                        } catch {
                            await send(.authenticateResult(false))
                        }
                    } else {
                        await send(.authenticateResult(false))
                    }
                }
            case let .authenticateResult(success):
                state.authenticating = false
                if success {
                    return .run { _ in
                        await self.dismiss()
                    }
                } else {
                    state.disableBiometricsAuth = true
                }
                return .none
            case let .savePasscode(passcode):
                state.$passcode.withLock {
                    $0 = passcode
                }
                return .none
            default:
                return .none
            }
        }
    }

    enum LockScreenState: String, CaseIterable {
        case new
        case verify
        case normal
        case remove
    }
}

struct LockScreen: View {
    @Environment(\.scenePhase) var scenePhase
    @FocusState private var focusedField: Bool

    @Bindable var store: StoreOf<LockScreenFeature>

    var body: some View {
        let label = "lock.label.\(store.lockState.rawValue)"
        VStack(spacing: 40) {
            Text(LocalizedStringKey(label))
                .font(.title)
                .font(.title)
            ZStack {
                pinDots(store: store)
                backgroundField(store: store)
                    .focused($focusedField)
            }
            showPinStack(store: store)
        }
        .onChange(of: store.disableBiometricsAuth, initial: true) {
            if store.lockState != .normal || store.disableBiometricsAuth {
                focusedField = true
            }
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active
                && store.lockState == .normal
                && !store.authenticating
                && !store.disableBiometricsAuth {
                store.send(.authenticate)
            }
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                banner.show()
                store.send(.setErrorMessage(""))
            }
        }
    }

    private func pinDots(store: StoreOf<LockScreenFeature>) -> some View {
        HStack {
            Spacer()
            ForEach(0..<6) { index in
                Image(systemName: self.getImageName(store: store, at: index))
                    .font(.system(size: 30, weight: .thin, design: .default))
                Spacer()
            }
        }
    }

    @MainActor
    private func backgroundField(store: StoreOf<LockScreenFeature>) -> some View {
        TextField("", text: $store.pin, onCommit: {
            store.send(.submitPin)
        })
        .tint(.clear)
        .foregroundStyle(.clear)
        .keyboardType(.numberPad)
        .disabled(store.authenticating)
        .onChange(of: store.pin) { oldPin, newPin in
            if newPin.last?.isWholeNumber == false {
                store.send(.setPin(oldPin))
            } else {
                store.send(.submitPin)
            }
        }
    }

    private func showPinStack(store: StoreOf<LockScreenFeature>) -> some View {
        HStack {
            Spacer()
            if !store.pin.isEmpty {
                showPinButton(store: store)
            }
        }
        .frame(height: 20)
        .padding([.trailing])
    }

    private func showPinButton(store: StoreOf<LockScreenFeature>) -> some View {
        Button(action: {
            store.send(.setShowPin(nil))
        }, label: {
            store.showPin ?
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(Color.primary) :
            Image(systemName: "eye.fill")
                .foregroundStyle(Color.primary)
        })
    }

    private func getImageName(store: StoreOf<LockScreenFeature>, at index: Int) -> String {
        if index >= store.pin.count {
            return "circle"
        }

        if store.showPin {
            return store.pin.digits[index].singleDigitNumberString + ".circle"
        }

        return "circle.fill"
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
    var singleDigitNumberString: String {
        guard self < 10 else { return "0" }
        return String(self)
    }
}
