//  Created 23/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

struct LANraragiConfigFeature: Reducer {
    private let logger = Logger(label: "LANraragiConfigFeature")
    
    struct State: Equatable {
        @BindingState var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        @BindingState var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
        var isVerifying = false
        var errorMessage = ""
    }
    
    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case verifyServer(String, String)
        case saveComplate
        case setErrorMessage(String)
        case reset
    }
    
    @Dependency(\.lanraragiService) var lanraragiService
    @Dependency(\.dismiss) var dismiss
    
    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action{
            case let .verifyServer(url, apiKey):
                state.isVerifying = true
                return .run { send in
                    do {
                        _ = try await lanraragiService.verifyClient(url: url, apiKey: apiKey).value
                        await send(.saveComplate)
                    } catch {
                        logger.error("failed to verify lanraragi server. \(error)")
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }
            case .saveComplate:
                UserDefaults.standard.set(state.url, forKey: SettingsKey.lanraragiUrl)
                UserDefaults.standard.set(state.apiKey, forKey: SettingsKey.lanraragiApiKey)
                state.isVerifying = false
                return .run { _ in
                    await self.dismiss()
                }
            case let .setErrorMessage(errorMessage):
                state.errorMessage = errorMessage
                state.isVerifying = false
                return .none
                
            case .reset:
                state.errorMessage = ""
                return .none
            case .binding:
                return .none
            }
        }
    }
}

struct LANraragiConfigView: View {
    
    @FocusState private var focused: Bool
    
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
                        .focused($focused)
                    SecureField("lanraragi.config.apiKey", text: viewStore.$apiKey)
                        .focused($focused)
                }
                Section {
                    Button(action: {
                        viewStore.send(.verifyServer(viewStore.url, viewStore.apiKey))
                    }, label: {
                        Text("lanraragi.config.submit")
                            .font(.headline)
                    })
                    .disabled(viewStore.isVerifying)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                    subtitle: viewStore.errorMessage,
                                                    style: .danger)
                    banner.show()
                    viewStore.send(.reset)
                }
            }
        }
    }
}
