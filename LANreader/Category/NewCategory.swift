import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct NewCategoryFeature {
    private let logger = Logger(label: "NewCategoryFeature")

    @ObservableState
    struct State: Equatable {
        var name = ""
        var dynamic = false
        var filter = ""
        var errorMessage = ""
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case addCategoryTapped
        case addCategorySuccess
        case setErrorMessage(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .addCategoryTapped:
                return .run { [state] send in
                    let response = try await service.addCategory(
                        name: state.name, search: state.dynamic ? state.filter : ""
                    ).value
                    if response.success == 1 {
                        await send(.addCategorySuccess)
                    } else {
                        await send(.setErrorMessage(String(localized: "category.new.add.failed")))
                    }
                } catch: { error, send in
                    logger.error("failed to add category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .addCategorySuccess:
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            case .binding:
                return .none
            }
        }
    }
}

struct NewCategory: View {
    @Bindable var store: StoreOf<NewCategoryFeature>

    var body: some View {
        Form {
            Section {
                TextField("category.name", text: $store.name)
                if store.dynamic {
                    TextField("category.search", text: $store.filter)
                }
                Toggle(isOn: $store.dynamic) {
                    Text("category.new.isDynamic")
                }
            }
            Section {
                Button {
                    store.send(.addCategoryTapped)
                } label: {
                    Text("category.new.add")
                }
                .disabled(store.name.isEmpty || (store.dynamic && store.filter.isEmpty))
            }
        }
        // disable refreshable
        // swiftlint:disable force_cast
        .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
        // swiftlint:enable force_cast
        .frame(minWidth: 280, minHeight: store.dynamic ? 280 : 230)
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
