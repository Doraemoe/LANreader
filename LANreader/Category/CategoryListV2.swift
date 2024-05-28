import ComposableArchitecture
import Logging
import SwiftUI
import NotificationBannerSwift

@Reducer struct CategoryFeature {
    private let logger = Logger(label: "CategoryFeature")

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []

        var editMode: EditMode = .inactive
        var showLoading = false
        var errorMessage = ""
    }

    enum Action: BindableAction {
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
        .ifLet(\.$destination, action: \.destination)
    }

    @Reducer(state: .equatable)
    enum Destination {
        case add(NewCategoryFeature)
    }
}

struct CategoryListV2: View {
    @Bindable var store: StoreOf<CategoryFeature>

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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Image(systemName: "plus.circle")
                    .onTapGesture {
                        store.send(.showAddCategory)
                    }
                    .foregroundStyle(Color.accentColor)
                    .popover(
                        item: $store.scope(state: \.destination?.add, action: \.destination.add)
                    ) { store in
                        NewCategory(store: store)
                    }
                    .opacity(store.editMode == .active ? 1 : 0)
                EditButton()
            }
        }
        .toolbar(store.editMode == .active ? .hidden : .visible, for: .tabBar)
        .environment(\.editMode, $store.editMode)
        .navigationTitle("category")
        .navigationBarTitleDisplayMode(.inline)
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
        .background {
            NavigationLink(
                "", state: AppFeature.Path.State.categoryArchiveList(
                    CategoryArchiveListFeature.State.init(
                        id: item.id,
                        name: item.name,
                        archiveList: ArchiveListFeature.State(
                            filter: SearchFilter(category: item.id, filter: nil),
                            currentTab: .category
                        )
                    )
                )
            )
            .opacity(0)
        }
    }
}
