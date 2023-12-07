import ComposableArchitecture
import Logging
import SwiftUI
import NotificationBannerSwift

@Reducer struct CategoryFeature {
    private let logger = Logger(label: "CategoryFeature")

    struct State: Equatable {
        @PresentationState var destination: Destination.State?

        @BindingState var editMode: EditMode = .inactive
        var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var showLoading = false
        var errorMessage = ""
    }

    enum Action: Equatable, BindableAction {
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case loadCategory(Bool)
        case populateCategory([CategoryItem])
        case setErrorMessage(String)
        case showAddCategory
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .loadCategory(loading):
                state.showLoading = loading
                return .run { send in
                    let categories = try await service.retrieveCategories().value
                    let items = categories.map { item in
                        item.toCategoryItem()
                    }
                    await send(.populateCategory(items))
                } catch: { error, send in
                    logger.error("failed to load category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .populateCategory(items):
                state.categoryItems = IdentifiedArray(uniqueElements: items)
                state.showLoading = false
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            case .showAddCategory:
                state.destination = .add(NewCategoryFeature.State())
                return .none
            case .binding:
                return .none
            case .destination(.presented(.add(.addCategorySuccess))):
                state.destination = nil
                return .run { send in
                    await send(.loadCategory(true))
                }
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination()
        }
    }

    @Reducer public struct Destination {
        public enum State: Equatable {
            case add(NewCategoryFeature.State)
        }

        public enum Action: Equatable {
            case add(NewCategoryFeature.Action)
        }

        public var body: some Reducer<State, Action> {
            Scope(state: \.add, action: \.add) {
                NewCategoryFeature()
            }
        }
    }
}

struct CategoryListV2: View {
    let store: StoreOf<CategoryFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            if viewStore.showLoading {
                HStack {
                    Spacer()
                    ProgressView("loading")
                    Spacer()
                }
            }
            List {
                ForEach(viewStore.categoryItems) { item in
                    categoryItem(viewStore: viewStore, item: item)
                }
            }
//            .toolbar {
//                ToolbarItemGroup(placement: .topBarTrailing) {
//                    if viewStore.editMode == .active {
//                        Button("", systemImage: "plus.circle") {
//                            viewStore.send(.showAddCategory)
//                        }
//                        .popover(store: store.scope(state: \.$destination.add, action: \.destination.add)) { store in
//                            NewCategory(store: store)
//                        }
//                    }
//                    EditButton()
//                }
//            }
//            .toolbar(viewStore.editMode == .active ? .hidden : .visible, for: .tabBar)
            .environment(\.editMode, viewStore.$editMode)
            .navigationTitle("category")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewStore.categoryItems.isEmpty {
                    viewStore.send(.loadCategory(true))
                }
            }
            .refreshable {
                viewStore.send(.loadCategory(false))
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
            .animation(nil, value: viewStore.editMode)
        }
    }

    private func categoryItem(viewStore: ViewStoreOf<CategoryFeature>, item: CategoryItem) -> some View {
        HStack {
            Text(item.name)
                .font(.title)
            Spacer()
            Image(systemName: viewStore.editMode == .active ? "square.and.pencil" : "chevron.right")
        }
        .background {
            NavigationLink(
                "", state: AppFeature.Path.State.categoryArchiveList(
                    CategoryArchiveListFeature.State.init(
                        id: item.id,
                        name: item.name,
                        archiveList: ArchiveListFeature.State(
                            filter: SearchFilter(category: item.id, filter: nil)
                        )
                    )
                )
            )
        }
    }
}
