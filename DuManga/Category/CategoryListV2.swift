import ComposableArchitecture
import Logging
import SwiftUI
import NotificationBannerSwift

@Reducer struct CategoryFeature {
    private let logger = Logger(label: "CategoryFeature")

    struct State: Equatable {
        var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var showLoading = false
        var errorMessage = ""
    }

    enum Action: Equatable {
        case loadCategory(Bool)
        case populateCategory([CategoryItem])
        case setErrorMessage(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .loadCategory(loading):
                state.showLoading = loading
                return .run { send in
                    do {
                        let categories = try await service.retrieveCategories().value
                        let items = categories.map { item in
                            item.toCategoryItem()
                        }
                        await send(.populateCategory(items))
                    } catch {
                        logger.error("failed to load category. \(error)")
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }
            case let .populateCategory(items):
                state.categoryItems = IdentifiedArray(uniqueElements: items)
                state.showLoading = false
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            }
        }
    }
}

struct CategoryListV2: View {
    let store: StoreOf<CategoryFeature>

    var body: some View {
            WithViewStore(self.store, observe: { $0 }) { viewStore in
                List {
                    ForEach(viewStore.categoryItems) { item in
                        NavigationLink(
                            state: AppFeature.Path.State.categoryArchiveList(
                                CategoryArchiveListFeature.State.init(
                                    id: item.id,
                                    name: item.name,
                                    archiveList: ArchiveListFeature.State(
                                        filter: SearchFilter(category: item.id, filter: nil)
                                    )
                                )
                            )
                        ) {
                            Text(item.name)
                                .font(.title)
                        }
                    }
                    if viewStore.showLoading {
                        HStack {
                            Spacer()
                            ProgressView("loading")
                            Spacer()
                        }
                    }
                }
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
                            title: NSLocalizedString("error", comment: "error"),
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
