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
        Group {
            TextField("category.new.name", text: $store.name)
                .textFieldStyle(.roundedBorder)
                .padding()
            if store.dynamic {
                TextField("category.new.predicate", text: $store.filter)
                    .textFieldStyle(.roundedBorder)
                    .padding()
            }
            Toggle(isOn: $store.dynamic) {
                Text("category.new.isDynamic")
            }
            .padding()
            Button {
                store.send(.addCategoryTapped)
            } label: {
                Text("category.new.add")
            }
            .padding()
            .disabled(store.name.isEmpty || (store.dynamic && store.filter.isEmpty))
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
}
