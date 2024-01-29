//  Created 23/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct LANraragiConfigFeature {
    private let logger = Logger(label: "LANraragiConfigFeature")

    @ObservableState
    struct State: Equatable {
        var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
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
    @Dependency(\.userDefaultService) var userDefault
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .verifyServer:
                state.isVerifying = true
                return .run { [state] send in
                    let serverInfo = try await lanraragiService.verifyClient(
                        url: state.url, apiKey: state.apiKey
                    ).value
                    if serverInfo.serverTracksProgress == "1" {
                        userDefault.setServerProgress(isServerProgress: true)
                    } else {
                        userDefault.setServerProgress(isServerProgress: false)
                    }
                    userDefault.saveLanrargiServer(url: state.url, apiKey: state.apiKey)
                    await send(.saveComplate)
                } catch: { error, send in
                    logger.error("failed to verify lanraragi server. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
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

    @Bindable var store: StoreOf<LANraragiConfigFeature>

    var body: some View {
        Form {
            Section(footer: Text("lanraragi.config.url.explain")) {
                TextField("lanraragi.config.url", text: $store.url)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused, equals: .url)
                SecureField("lanraragi.config.apiKey", text: $store.apiKey)
                    .focused($focused, equals: .apiKey)
            }
            Section {
                Button(action: {
                    store.send(.verifyServer)
                }, label: {
                    Text("lanraragi.config.submit")
                        .font(.headline)
                })
                .disabled(store.isVerifying)
            }
        }
        .onSubmit {
            if focused == .url {
                focused = .apiKey
            } else {
                store.send(.verifyServer)
            }
        }
        .toolbar(.hidden, for: .tabBar)
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
}
