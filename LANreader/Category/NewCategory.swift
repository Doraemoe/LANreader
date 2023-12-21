import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct NewCategoryFeature {
    private let logger = Logger(label: "NewCategoryFeature")

    struct State: Equatable {
        @BindingState var name = ""
        @BindingState var dynamic = false
        @BindingState var filter = ""
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
    let store: StoreOf<NewCategoryFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            Group {
                TextField("category.new.name", text: viewStore.$name)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                if viewStore.dynamic {
                    TextField("category.new.predicate", text: viewStore.$filter)
                        .textFieldStyle(.roundedBorder)
                        .padding()
                }
                Toggle(isOn: viewStore.$dynamic) {
                    Text("category.new.isDynamic")
                }
                .padding()
                Button {
                    viewStore.send(.addCategoryTapped)
                } label: {
                    Text("category.new.add")
                }
                .padding()
                .disabled(viewStore.name.isEmpty || (viewStore.dynamic && viewStore.filter.isEmpty))
            }
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: String(localized: "error"),
                        subtitle: viewStore.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    viewStore.send(.setErrorMessage(""))
                }
            }
        }
    }
}
