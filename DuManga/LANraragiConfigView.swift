//  Created 23/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct LANraragiConfigFeature {
    private let logger = Logger(label: "LANraragiConfigFeature")

    struct State: Equatable {
        @BindingState var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        @BindingState var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
        var isVerifying = false
        var errorMessage = ""
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case verifyServer
        case saveComplate
        case setErrorMessage(String)
    }

    @Dependency(\.lanraragiService) var lanraragiService
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .verifyServer:
                state.isVerifying = true
                return .run { [state] send in
                    do {
                        _ = try await lanraragiService.verifyClient(url: state.url, apiKey: state.apiKey).value
                        UserDefaults.standard.set(state.apiKey, forKey: SettingsKey.lanraragiApiKey)
                        UserDefaults.standard.set(state.url, forKey: SettingsKey.lanraragiUrl)
                        await send(.saveComplate)
                    } catch {
                        logger.error("failed to verify lanraragi server. \(error)")
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }
            case .saveComplate:
                state.isVerifying = false
                return .run { _ in
                    await self.dismiss()
                }
            case let .setErrorMessage(errorMessage):
                state.errorMessage = errorMessage
                state.isVerifying = false
                return .none
            case .binding:
                return .none
            }
        }
    }
}

struct LANraragiConfigView: View {

    enum FocusedField {
        case url, apiKey
    }

    @FocusState private var focused: FocusedField?

    let store: StoreOf<LANraragiConfigFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            Form {
                Section(footer: Text("lanraragi.config.url.explain")) {
                    TextField("lanraragi.config.url", text: viewStore.$url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .url)
                    SecureField("lanraragi.config.apiKey", text: viewStore.$apiKey)
                        .focused($focused, equals: .apiKey)
                }
                Section {
                    Button(action: {
                        viewStore.send(.verifyServer)
                    }, label: {
                        Text("lanraragi.config.submit")
                            .font(.headline)
                    })
                    .disabled(viewStore.isVerifying)
                }
            }
            .onSubmit {
                if focused == .url {
                    focused = .apiKey
                } else {
                    viewStore.send(.verifyServer)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                    subtitle: viewStore.errorMessage,
                                                    style: .danger)
                    banner.show()
                    viewStore.send(.setErrorMessage(""))
                }
            }
        }
    }
}
