import SwiftUI
import ComposableArchitecture
import Logging

@Reducer public struct EditCategoryFeature {
    private let logger = Logger(label: "EditCategoryFeature")

    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        var id: String
        var name: String
        var filter: String
        let dynamic: Bool
        let pinned: String
        var saving = false
        var errorMessage = ""
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case editCategoryTapped
        case editCategorySuccess
        case deleteCategoryTapped
        case deleteCategorySuccess
        case editCategoryCancel
        case setErrorMessage(String)

        public enum Alert {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.dismiss) var dismiss

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .editCategoryTapped:
                state.saving = true
                return .run { [state] send in
                    let item = CategoryItem(
                        id: state.id,
                        name: state.name,
                        archives: [],
                        search: state.filter,
                        pinned: state.pinned
                    )
                    let response = try await service.updateCategory(item: item).value
                    if response.success == 1 {
                        await send(.editCategorySuccess)
                    } else {
                        await send(.setErrorMessage(String(localized: "category.edit.failed")))
                    }
                } catch: { error, send in
                    logger.error("failed to edit category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .editCategorySuccess:
                state.saving = false
                return .none
            case .deleteCategoryTapped:
                state.alert = AlertState {
                    TextState("category.delete.confirm")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case .alert(.presented(.confirmDelete)):
                state.saving = true
                return .run { [id = state.id] send in
                    let response = try await service.deleteCategory(id: id).value
                    if response.success == 1 {
                        await send(.deleteCategorySuccess)
                    } else {
                        await send(.setErrorMessage(String(localized: "category.delete.failed")))
                    }
                } catch: { error, send in
                    logger.error("failed to delete category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .deleteCategorySuccess:
                state.saving = false
                return .none
            case .editCategoryCancel:
                return .run { _ in
                    await self.dismiss()
                }
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

}

struct EditCategory: View {
    @Bindable var store: StoreOf<EditCategoryFeature>

    var body: some View {
        Form {
            Section {
                TextField("category.name", text: $store.name)
                if store.dynamic {
                    TextField("category.search", text: $store.filter)
                }
            }
            Section {
                Button {
                    store.send(.editCategoryTapped)
                } label: {
                    Text("save")
                }
                .disabled(store.name.isEmpty || (store.dynamic && store.filter.isEmpty) || store.saving)
                Button(role: .destructive) {
                    store.send(.deleteCategoryTapped)
                } label: {
                    Text("delete")
                }
                .alert(
                    $store.scope(state: \.alert, action: \.alert)
                )
                .disabled(store.saving)
            }
            Section {
                Button(role: .cancel) {
                    store.send(.editCategoryCancel)
                } label: {
                    Text("cancel")
                }
                .disabled(store.saving)
            }
        }
    }
}
