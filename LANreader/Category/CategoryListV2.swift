import ComposableArchitecture
import Logging
import SwiftUI
import NotificationBannerSwift

@Reducer public struct CategoryFeature {
    private let logger = Logger(label: "CategoryFeature")

    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []

        var editMode: EditMode = .inactive
        var showLoading = false
        var errorMessage = ""
    }

    public enum Action: BindableAction {
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case loadCategory(Bool)
        case populateCategory([CategoryItem])
        case setErrorMessage(String)
        case showAddCategory
        case showEditCategory(CategoryItem)
    }

    @Dependency(\.lanraragiService) var service

    public var body: some ReducerOf<Self> {
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
                state.$categoryItems.withLock {
                    $0 = IdentifiedArray(uniqueElements: items)
                }
                state.showLoading = false
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            case .showAddCategory:
                state.destination = .add(NewCategoryFeature.State())
                return .none
            case let .showEditCategory(item):
                state.destination = .edit(
                    EditCategoryFeature.State(
                        id: item.id,
                        name: item.name,
                        filter: item.search,
                        dynamic: !item.search.isEmpty,
                        pinned: item.pinned
                    )
                )
                return .none
            case .binding:
                return .none
            case .destination(.presented(.add(.addCategorySuccess))):
                state.destination = nil
                return .run { send in
                    await send(.loadCategory(true))
                }
            case .destination(.presented(.edit(.editCategorySuccess))):
                state.destination = nil
                return .run { send in
                    await send(.loadCategory(true))
                }
            case .destination(.presented(.edit(.deleteCategorySuccess))):
                state.destination = nil
                return .run { send in
                    await send(.loadCategory(true))
                }
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    @Reducer(state: .equatable)
    public enum Destination {
        case add(NewCategoryFeature)
        case edit(EditCategoryFeature)
    }
}

struct CategoryListV2: View {
    @Bindable var store: StoreOf<CategoryFeature>
    let onTapCategory: (StoreOf<CategoryArchiveListFeature>) -> Void

    var body: some View {
        if store.showLoading {
            HStack {
                Spacer()
                ProgressView("loading")
                Spacer()
            }
        }
        List {
            ForEach(store.categoryItems) { item in
                categoryItem(store: store, item: item)
            }
        }
//        .toolbar {
//            ToolbarItemGroup(placement: .topBarTrailing) {
//                Image(systemName: "plus.circle")
//                    .onTapGesture {
//                        store.send(.showAddCategory)
//                    }
//                    .foregroundStyle(Color.accentColor)
//                    .popover(
//                        item: $store.scope(state: \.destination?.add, action: \.destination.add)
//                    ) { store in
//                        NewCategory(store: store)
//                    }
//                    .opacity(store.editMode == .active ? 1 : 0)
//                EditButton()
//            }
//        }
//        .sheet(item: $store.scope(state: \.destination?.edit, action: \.destination.edit), content: { store in
//            EditCategory(store: store)
//        })
//        .toolbar(store.editMode == .active ? .hidden : .visible, for: .tabBar)
//        .environment(\.editMode, $store.editMode)
//        .navigationTitle("category")
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar(store.tabBarHidden ? .hidden : .visible, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.categoryItems.isEmpty {
                store.send(.loadCategory(true))
            }
        }
        .refreshable {
            await store.send(.loadCategory(false)).finish()
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
        .onChange(of: store.lanraragiUrl) {
            if !store.lanraragiUrl.isEmpty {
                store.send(.loadCategory(true))
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func categoryItem(store: StoreOf<CategoryFeature>, item: CategoryItem) -> some View {
        HStack {
            Text(item.name)
                .font(.title)
            Spacer()
            Image(systemName: store.editMode == .active ? "square.and.pencil" : "chevron.right")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if store.editMode == .active {
                store.send(.showEditCategory(item))
            } else {
                let categoryArchiveListStore = Store(
                    initialState: CategoryArchiveListFeature.State.init(
                        id: item.id,
                        name: item.name,
                        archiveList: ArchiveListFeature.State(
                            filter: SearchFilter(category: item.id, filter: nil),
                            currentTab: .category
                        )
                    )
                ) {
                    CategoryArchiveListFeature()
                }
                onTapCategory(categoryArchiveListStore)
            }
        }
    }
}
