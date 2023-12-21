import ComposableArchitecture
import OrderedCollections
import SwiftUI
import Combine
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveListFeature {
    private let logger = Logger(label: "ArchiveListFeature")
    struct State: Equatable {
        @PresentationState var alert: AlertState<Action.Alert>?
        var selectMode: EditMode = .inactive
        var selected: Set<String> = .init()
        var categoryItems: IdentifiedArrayOf<CategoryItem>?
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var showLoading: Bool = false
        var total: Int = 0
        var errorMessage = ""
        var successMessage = ""
        var currentTab: TabName

        var archivesToDisplay: IdentifiedArrayOf<GridFeature.State> {
            if UserDefaults.standard.bool(forKey: SettingsKey.hideRead) {
                let result = archives.filter {
                    $0.archive.pagecount != $0.archive.progress
                }
                return IdentifiedArray(uniqueElements: result)
            } else {
                return archives
            }
        }
    }

    enum Action: Equatable {
        case alert(PresentationAction<Alert>)
        case grid(IdentifiedActionOf<GridFeature>)
        case loadCategory
        case populateCategory([CategoryItem])
        case addArchivesToCategory(String)
        case updateLocalCategory(String, Set<String>)
        case setFilter(SearchFilter)
        case resetArchives
        case load(Bool)
        case populateArchives([ArchiveItem], Int, Bool)
        case subscribeThumbnailTrigger
        case subscribeProgressTrigger
        case subscribeDeleteTrigger
        case refreshThumbnail(String)
        case updateArchiveProgress(String, Int)
        case appendArchives(String)
        case removeArchive(String)
        case setErrorMessage(String)
        case setSuccessMessage(String)
        case cancelSearch
        case addSelect(String)
        case removeSelect(String)

        case deleteButtonTapped
        case deleteSuccess(Set<String>)
        case removeFromCategoryButtonTapped
        case removeFromCategorySuccess(Set<String>)
        enum Alert {
            case confirmDelete
            case confirmRemoveFromCategory
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.refreshTrigger) var refreshTrigger
    @Dependency(\.userDefaultService) var userDefault

    enum CancelId { case search }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .subscribeThumbnailTrigger:
                return .run { send in
                    for await archiveId in refreshTrigger.thumbnail.values {
                        await send(.refreshThumbnail(archiveId))
                    }
                }
            case .subscribeProgressTrigger:
                return .run { send in
                    for await (archiveId, progress) in refreshTrigger.progress.values {
                        await send(.updateArchiveProgress(archiveId, progress))
                    }
                }
            case .subscribeDeleteTrigger:
                return .run { send in
                    for await archiveId in refreshTrigger.delete.values {
                        await send(.removeArchive(archiveId))
                    }
                }
            case let .setFilter(filter):
                state.filter = filter
                return .none
            case .resetArchives:
                state.archives = .init()
                return .none
            case let .load(showLoading):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = showLoading
                let sortby = userDefault.searchSort
                let order = userDefault.searchSortOrder
                self.populateTags()
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: "0", order: order, append: false
                )
            case let .appendArchives(start):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = true
                let sortby = userDefault.searchSort
                let order = userDefault.searchSortOrder
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: start, order: order, append: true
                )
            case let .removeArchive(id):
                state.archives.remove(id: id)
                return .none
            case let .populateArchives(archives, total, append):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                if !append {
                    state.archives = .init()
                    state.total = 0
                }
                state.archives.append(contentsOf: gridFeatureState)
                state.total = total
                state.loading = false
                state.showLoading = false
                return .none
            case let .refreshThumbnail(archiveId):
                if state.archives.contains(where: { $0.id == archiveId }) {
                    return .send(.grid(.element(id: archiveId, action: .load(true))))
                } else {
                    return .none
                }
            case let .updateArchiveProgress(archiveId, progress):
                state.archives[id: archiveId]?.archive.progress = progress
                if progress > 1 && state.archives[id: archiveId]?.archive.isNew == true {
                    state.archives[id: archiveId]?.archive.isNew = false
                }
                return .none
            case let .setErrorMessage(message):
                state.loading = false
                state.showLoading = false
                state.errorMessage = message
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .grid:
                return .none
            case .cancelSearch:
                if state.loading {
                    state.loading = false
                    state.showLoading = false
                    return .cancel(id: CancelId.search)
                }
                return .none
            case let .addSelect(id):
                state.selected.insert(id)
                return .none
            case let .removeSelect(id):
                state.selected.remove(id)
                return .none
            case .alert(.dismiss):
                return .none
            case .alert(.presented(.confirmRemoveFromCategory)):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in state.selected {
                        do {
                            let response = try await service.removeArchiveFromCategory(
                                categoryId: state.filter.category!, archiveId: archiveId
                            ).value
                            if response.success == 1 {
                                successIds.insert(archiveId)
                            } else {
                                errorIds.insert(archiveId)
                            }
                        } catch {
                            logger.error(
                                """
                                failed to remove archive from category.
                                categoryId=\(state.filter.category ?? ""), archiveId=\(archiveId) \(error)
                                """
                            )
                            errorIds.insert(archiveId)
                        }

                    }

                    if !errorIds.isEmpty {
                        await send(.setErrorMessage(
                            String(localized: "archive.selected.category.remove.error")
                        ))
                    } else {
                        await send(.setSuccessMessage(
                            String(localized: "archive.selected.category.remove.success")
                        ))
                    }
                    await send(.removeFromCategorySuccess(successIds))
                }
            case let .removeFromCategorySuccess(archiveIds):
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archives.remove(id: id)
                }
                state.loading = false
                return .none
            case .alert(.presented(.confirmDelete)):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in state.selected {
                        do {
                            let response = try await service.deleteArchive(id: archiveId).value
                            if response.success == 1 {
                                successIds.insert(archiveId)
                            } else {
                                errorIds.insert(archiveId)
                            }
                        } catch {
                            logger.error("failed to delete archive id=\(archiveId) \(error)")
                            errorIds.insert(archiveId)
                        }
                    }

                    if !errorIds.isEmpty {
                        await send(.setErrorMessage(
                            String(localized: "archive.selected.delete.error")
                        ))
                    } else {
                        await send(.setSuccessMessage(
                            String(localized: "archive.selected.delete.success")
                        ))
                    }
                    await send(.deleteSuccess(successIds))
                }
            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("archive.selected.delete")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case .removeFromCategoryButtonTapped:
                state.alert = AlertState {
                    TextState("archive.selected.category.remove")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmRemoveFromCategory) {
                        TextState("remove")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case let .deleteSuccess(archiveIds):
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archives.remove(id: id)
                }
                state.loading = false
                return .none
            case .loadCategory:
                return .run { send in
                    let categories = try await service.retrieveCategories().value
                    let items = categories.map { item in
                        item.toCategoryItem()
                    }.filter { item in
                        item.search.isEmpty
                    }
                    await send(.populateCategory(items))
                } catch: { error, send in
                    logger.error("failed to load category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .populateCategory(items):
                state.categoryItems = IdentifiedArray(uniqueElements: items)
                return .none
            case let .addArchivesToCategory(categoryId):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()
                    let currentCategory = state.categoryItems![id: categoryId]!

                    for archiveId in state.selected {
                        if currentCategory.archives.contains(archiveId) {
                            successIds.insert(archiveId)
                        } else {
                            do {
                                let response = try await service.addArchiveToCategory(
                                    categoryId: categoryId, archiveId: archiveId
                                ).value
                                if response.success == 1 {
                                    successIds.insert(archiveId)
                                } else {
                                    errorIds.insert(archiveId)
                                }
                            } catch {
                                logger.error(
                                    """
                                    failed to add archive to category.
                                    categoryId=\(categoryId), archiveId=\(archiveId) \(error)
                                    """
                                )
                                errorIds.insert(archiveId)
                            }
                        }
                    }
                    if !errorIds.isEmpty {
                        await send(.setErrorMessage(
                            String(localized: "archive.selected.category.add.error")
                        ))
                    } else {
                        await send(.setSuccessMessage(
                            String(localized: "archive.selected.category.add.success")
                        ))
                    }
                    await send(.updateLocalCategory(categoryId, successIds))
                }
            case let .updateLocalCategory(categoryId, archiveIds):
                state.categoryItems![id: categoryId]?.archives.append(contentsOf: archiveIds)
                archiveIds.forEach { id in
                    state.selected.remove(id)
                }
                state.loading = false
                return .none
            }
        }
        .forEach(\.archives, action: \.grid) {
            GridFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    func populateTags() {
        let currentTime = Date().timeIntervalSince1970
        let lastUpdateTime = userDefault.lastTagRefresh
        let excludeTags = ["date_added", "source"]
        // refresh only after 1 day
        if currentTime - lastUpdateTime > 86400 {
            userDefault.setLastTagRefresh()
            Task.detached(priority: .utility) {
                do {
                    let response = try await service.databaseBackup().value
                    _ = try database.deleteAllTag()
                    response.archives.forEach { archive in
                        archive.tags?.split(separator: ",")
                            .map { tag in
                                tag.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .forEach { normalizedTag in
                                let tagKey = String(normalizedTag.split(separator: ":").first ?? "")
                                if !excludeTags.contains(tagKey) {
                                    var tagItem = TagItem(tag: normalizedTag)
                                    try? database.saveTag(tagItem: &tagItem)
                                }
                            }
                    }
                } catch {
                    logger.error("failed to refresh tags. \(error)")
                    userDefault.setLastTagRefresh(timeOverride: lastUpdateTime)
                }
            }
        }
    }

    // swiftlint:disable function_parameter_count
    func search(
        state: inout State, searchFilter: SearchFilter, sortby: String, start: String, order: String, append: Bool
    ) -> Effect<Action> {
        return .run { send in
            do {
                let response = try await service.searchArchive(
                    category: searchFilter.category,
                    filter: searchFilter.filter,
                    start: start,
                    sortby: sortby,
                    order: order
                ).value
                let archives = response.data.map {
                    $0.toArchiveItem()
                }
                await send(.populateArchives(archives, response.recordsFiltered, append))
            } catch {
                logger.error("failed to load archives. \(error)")
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
        .cancellable(id: CancelId.search)
    }
    // swiftlint:enable function_parameter_count

}

struct ArchiveListV2: View {
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false
    @AppStorage(SettingsKey.lanraragiUrl) var lanraragiUrl: String = ""
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue
    @AppStorage(SettingsKey.searchSortOrder) var searchSortOrder: String = SearchSortOrder.asc.rawValue

    let store: StoreOf<ArchiveListFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    struct ArchiveListViewState: Equatable {
        let selectMode: EditMode
        let selected: Set<String>
        let categoryItems: IdentifiedArrayOf<CategoryItem>?
        let filter: SearchFilter
        let isArchiveEmpty: Bool
        let archiveCount: Int
        let lastArchive: GridFeature.State?
        let total: Int
        let showLoading: Bool
        let loadOnAppear: Bool
        let errorMessage: String
        let successMessage: String
        let currentTab: TabName

        init(state: ArchiveListFeature.State) {
            self.selectMode = state.selectMode
            self.selected = state.selected
            self.categoryItems = state.categoryItems
            self.filter = state.filter
            self.isArchiveEmpty = state.archives.isEmpty
            self.archiveCount = state.archives.count
            self.lastArchive = state.archivesToDisplay.last
            self.total = state.total
            self.showLoading = state.showLoading
            self.loadOnAppear = state.loadOnAppear
            self.errorMessage = state.errorMessage
            self.successMessage = state.successMessage
            self.currentTab = state.currentTab
        }
    }

    struct GridViewState: Equatable {
        let archive: ArchiveItem
        init(state: GridFeature.State) {
            self.archive = state.archive
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ArchiveListViewState.init) { viewStore in
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEachStore(
                        self.store.scope(state: \.archivesToDisplay, action: \.grid)
                    ) { gridStore in
                        WithViewStore(gridStore, observe: GridViewState.init) { gridViewStore in
                            grid(viewStore: viewStore, gridStore: gridStore, gridViewStore: gridViewStore)
                        }
                    }
                }
                .padding(.horizontal)
                if viewStore.showLoading {
                    ProgressView("loading")
                }
            }
            .toolbar(viewStore.selectMode == .active ? .visible : .hidden, for: .bottomBar)
            .toolbar {
                bottomToolbar(viewStore: viewStore)
            }
            .onAppear {
                viewStore.send(.subscribeThumbnailTrigger)
                viewStore.send(.subscribeProgressTrigger)
                viewStore.send(.subscribeDeleteTrigger)
                if lanraragiUrl.isEmpty == false &&
                    viewStore.isArchiveEmpty && viewStore.loadOnAppear {
                    viewStore.send(.load(true))
                }
            }
            .refreshable {
                if viewStore.currentTab != .search || viewStore.filter.filter?.isEmpty == false {
                    await viewStore.send(.load(false)).finish()
                }
            }
            .onChange(of: self.searchSort) {
                viewStore.send(.cancelSearch)
                viewStore.send(.resetArchives)
                viewStore.send(.load(true))
            }
            .onChange(of: self.searchSortOrder, {
                viewStore.send(.cancelSearch)
                viewStore.send(.resetArchives)
                viewStore.send(.load(true))
            })
            .onChange(of: viewStore.filter) {
                viewStore.send(.cancelSearch)
                viewStore.send(.resetArchives)
                viewStore.send(.load(true))
            }
            .onChange(of: lanraragiUrl, {
                if lanraragiUrl.isEmpty == false {
                    viewStore.send(.cancelSearch)
                    viewStore.send(.resetArchives)
                    viewStore.send(.load(true))
                }
            })
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
            .onChange(of: viewStore.successMessage) {
                if !viewStore.successMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: String(localized: "success"),
                        subtitle: viewStore.successMessage,
                        style: .success
                    )
                    banner.show()
                    viewStore.send(.setSuccessMessage(""))
                }
            }
        }
    }

    private func contextMenu(gridViewStore: ViewStore<ArchiveListV2.GridViewState, GridFeature.Action>) -> some View {
        Group {
            NavigationLink(
                state: AppFeature.Path.State.reader(
                    ArchiveReaderFeature.State.init(
                        archive: gridViewStore.archive,
                        fromStart: true
                    )
                )
            ) {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                gridViewStore.send(.load(true))
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }

    // swiftlint:disable function_body_length
    private func bottomToolbar(
        viewStore: ViewStore<ArchiveListV2.ArchiveListViewState, ArchiveListFeature.Action>
    ) -> ToolbarItemGroup<some View> {
        ToolbarItemGroup(placement: .bottomBar) {
            if viewStore.filter.category == nil {
                Menu {
                    if viewStore.categoryItems != nil {
                        Text("archive.selected.category.add")
                        ForEach(viewStore.categoryItems!) { item in
                            Button {
                                viewStore.send(.addArchivesToCategory(item.id))
                            } label: {
                                Text(item.name)
                            }
                        }
                    } else {
                        ProgressView("loading")
                            .onAppear {
                                if lanraragiUrl.isEmpty == false {
                                    viewStore.send(.loadCategory)
                                }
                            }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(viewStore.selected.isEmpty)
            } else {
                Button(role: .destructive) {
                    viewStore.send(.removeFromCategoryButtonTapped)
                } label: {
                    Image(systemName: "folder.badge.minus")
                }
                .disabled(viewStore.selected.isEmpty)
                .alert(
                    store: self.store.scope(
                        state: \.$alert,
                        action: \.alert
                    )
                )
            }
            Spacer()

            Text(
                String.localizedStringWithFormat(
                    String(localized: "archive.selected"),
                    viewStore.selected.count
                )
            )

            Spacer()

            Button(role: .destructive) {
                viewStore.send(.deleteButtonTapped)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewStore.selected.isEmpty)
            .alert(
                store: self.store.scope(
                    state: \.$alert,
                    action: \.alert
                )
            )
        }
    }
    // swiftlint:enable function_body_length

    private func grid(
        viewStore: ViewStore<ArchiveListV2.ArchiveListViewState, ArchiveListFeature.Action>,
        gridStore: StoreOf<GridFeature>,
        gridViewStore: ViewStore<ArchiveListV2.GridViewState, GridFeature.Action>
    ) -> some View {
        ZStack {
            if viewStore.selectMode == .active {
                ArchiveGridV2(store: gridStore)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewStore.selected.contains(gridViewStore.archive.id) {
                            viewStore.send(.removeSelect(gridViewStore.archive.id))
                        } else {
                            viewStore.send(.addSelect(gridViewStore.archive.id))
                        }
                    }
                    .overlay(alignment: .bottomTrailing, content: {
                        if viewStore.selected.contains(gridViewStore.archive.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50)
                                .foregroundStyle(.white, .blue)
                                .padding()
                        } else {
                            Image(systemName: "circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    })
            } else {
                NavigationLink(
                    state: AppFeature.Path.State.reader(
                        ArchiveReaderFeature.State.init(
                            archive: gridViewStore.archive
                        )
                    )
                ) {
                    ArchiveGridV2(store: gridStore)
                        .onAppear {
                            if gridViewStore.archive.id == viewStore.lastArchive?.archive.id &&
                                viewStore.archiveCount < viewStore.total {
                                viewStore.send(.appendArchives(String(viewStore.archiveCount)))
                            }
                        }
                        .contextMenu {
                            contextMenu(gridViewStore: gridViewStore)
                        }
                }
            }
        }
    }
}

struct RefreshTrigger {
    var thumbnail = PassthroughSubject<String, Never>()
    var progress = PassthroughSubject<(String, Int), Never>()
    var delete = PassthroughSubject<String, Never>()
}

private enum RefreshTriggerKey: DependencyKey {
    static let liveValue = RefreshTrigger()
    static let testValue = RefreshTrigger()
}

extension DependencyValues {
    var refreshTrigger: RefreshTrigger {
        get { self[RefreshTriggerKey.self] }
        set { self[RefreshTriggerKey.self] = newValue }
    }
}
