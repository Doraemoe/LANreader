import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import LocalAuthentication

@Reducer public struct LockScreenFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
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
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(spacing: 24) {
                    stateIcon(store: store)

                    Text(title(for: store.lockState))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    passcodePanel(store: store)
                }
                .frame(maxWidth: 420)

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusPasscodeField()
        }
        .onChange(of: store.disableBiometricsAuth, initial: true) {
            if store.lockState != .normal || store.disableBiometricsAuth {
                focusPasscodeField()
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

    private func title(for state: LockScreenFeature.LockScreenState) -> String {
        NSLocalizedString("lock.label.\(state.rawValue)", comment: "")
    }

    private func focusPasscodeField() {
        focusedField = false
        Task { @MainActor in
            await Task.yield()
            focusedField = true
        }
    }

    private func stateIcon(store: StoreOf<LockScreenFeature>) -> some View {
        let tint = tintColor(for: store.lockState)

        return ZStack {
            Circle()
                .fill(tint.opacity(0.14))

            Circle()
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)

            Image(systemName: iconName(for: store.lockState))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 86, height: 86)
        .shadow(color: tint.opacity(0.16), radius: 18, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    private func passcodePanel(store: StoreOf<LockScreenFeature>) -> some View {
        VStack(spacing: 18) {
            ZStack {
                pinDots(store: store)

                backgroundField(store: store)
                    .focused($focusedField)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }

            showPinStack(store: store)
        }
        .padding(22)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private func pinDots(store: StoreOf<LockScreenFeature>) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 8
            let availableWidth = max(0, proxy.size.width - spacing * 5)
            let cellWidth = min(42, availableWidth / 6)

            HStack(spacing: spacing) {
                ForEach(0..<6) { index in
                    pinCell(store: store, at: index, width: cellWidth)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
    }

    private func pinCell(store: StoreOf<LockScreenFeature>, at index: Int, width: CGFloat) -> some View {
        let hasDigit = index < store.pin.count
        let tint = tintColor(for: store.lockState)

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hasDigit ? tint.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(hasDigit ? tint.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
                }

            if hasDigit && store.showPin {
                Text(store.pin.digits[index].singleDigitNumberString)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
            } else if hasDigit {
                Circle()
                    .fill(tint)
                    .frame(width: 11, height: 11)
            }
        }
        .frame(width: width, height: 50)
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
        .frame(height: 42)
    }

    private func showPinButton(store: StoreOf<LockScreenFeature>) -> some View {
        let tint = tintColor(for: store.lockState)

        return Button(action: {
            store.send(.setShowPin(nil))
        }, label: {
            store.showPin ?
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(tint) :
            Image(systemName: "eye.fill")
                .foregroundStyle(tint)
        })
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 42, height: 42)
        .background(
            tint.opacity(0.12),
            in: Circle()
        )
        .overlay {
            Circle()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
        .buttonStyle(.plain)
    }

    private func iconName(for state: LockScreenFeature.LockScreenState) -> String {
        switch state {
        case .new:
            return "key.fill"
        case .verify:
            return "checkmark.shield.fill"
        case .normal:
            return "lock.fill"
        case .remove:
            return "lock.open.fill"
        }
    }

    private func tintColor(for state: LockScreenFeature.LockScreenState) -> Color {
        switch state {
        case .new:
            return .green
        case .verify:
            return .indigo
        case .normal:
            return .blue
        case .remove:
            return .red
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
    var singleDigitNumberString: String {
        guard self < 10 else { return "0" }
        return String(self)
    }
}
