import ComposableArchitecture
import OrderedCollections
import SwiftUI
import Combine
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveListFeature {
    private let logger = Logger(label: "ArchiveListFeature")

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.hideRead)) var hideRead = false
        @Shared(.appStorage(SettingsKey.searchSort)) var searchSort = SearchSort.dateAdded.rawValue
        @Shared(.appStorage(SettingsKey.searchSortOrder)) var searchSortOrder = SearchSortOrder.asc.rawValue
        @Shared(.appStorage(SettingsKey.lastTagRefresh)) var lastTagRefresh = 0.0

        var selectMode: EditMode = .inactive
        var selected: Set<String> = .init()
        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var showLoading: Bool = false
        var total: Int = 0
        var errorMessage = ""
        var successMessage = ""
        var currentTab: TabName

        var archivesToDisplay: IdentifiedArrayOf<GridFeature.State> = []
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
        case refreshThumbnail(String)
        case appendArchives(String)
        case removeArchive(String)
        case setErrorMessage(String)
        case setSuccessMessage(String)
        case cancelSearch
        case addSelect(String)
        case removeSelect(String)
        case refreshDisplayArchives

        case setSearchSortOrder(String)
        case setSearchSort(String)
        case toggleHideRead

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

    enum CancelId { case search }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setFilter(filter):
                state.filter = filter
                return .none
            case .resetArchives:
                state.archivesToDisplay = .init()
                state.archives = .init()
                return .none
            case let .load(showLoading):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                if showLoading {
                    state.showLoading = showLoading
                }
                let sortby = state.searchSort
                let order = state.searchSortOrder
                self.populateTags(state: &state)
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: "0", order: order, append: false
                )
            case let .appendArchives(start):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = true
                let sortby = state.searchSort
                let order = state.searchSortOrder
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: start, order: order, append: true
                )
            case let .removeArchive(id):
                state.archivesToDisplay.remove(id: id)
                state.archives.remove(id: id)
                state.archiveItems.remove(id: id)
                return .none
            case let .populateArchives(archives, total, append):
                archives.forEach { item in
                    state.archiveItems.updateOrAppend(item)
                }
                let gridFeatureState = archives.compactMap { item in
                    Shared(state.$archiveItems[id: item.id])
                }.map {
                    GridFeature.State(archive: $0)
                }
                if !append {
                    state.archives = .init()
                    state.archivesToDisplay = .init()
                    state.total = 0
                }
                state.archives.append(contentsOf: gridFeatureState)

                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }

                state.total = total
                state.loading = false
                state.showLoading = false
                return .none
            case let .refreshThumbnail(archiveId):
                if state.archivesToDisplay.contains(where: { $0.id == archiveId }) {
                    return .send(.grid(.element(id: archiveId, action: .load(true))))
                } else {
                    return .none
                }
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
            case .refreshDisplayArchives:
                let before = state.archives.count
                let filteredGridFeatureState = state.archives.filter { gridState in
                    state.archiveItems[id: gridState.archive.id] != nil
                }
                let after = filteredGridFeatureState.count
                let diff = before - after
                state.total -= diff

                state.archives = filteredGridFeatureState

                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }

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
                    state.archivesToDisplay.remove(id: id)
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
            case let .setSearchSortOrder(order):
                state.searchSortOrder = order
                return .none
            case let .setSearchSort(sort):
                state.searchSort = sort
                return .none
            case .toggleHideRead:
                state.hideRead.toggle()
                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }
                return .none
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
                    state.archivesToDisplay.remove(id: id)
                    state.archives.remove(id: id)
                    state.archiveItems.remove(id: id)
                }
                state.loading = false
                return .none
            case .loadCategory:
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
                return .none
            case let .addArchivesToCategory(categoryId):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()
                    let currentCategory = await state.$categoryItems.withLock { $0[id: categoryId]! }

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
                state.categoryItems[id: categoryId]?.archives.append(contentsOf: archiveIds)
                archiveIds.forEach { id in
                    state.selected.remove(id)
                }
                state.loading = false
                return .none
            }
        }
        .forEach(\.archivesToDisplay, action: \.grid) {
            GridFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    func populateTags(state: inout State) {
        let currentTime = Date().timeIntervalSince1970
        let lastUpdateTime = state.lastTagRefresh
        let excludeTags = ["date_added", "source"]
        // refresh only after 1 day
        if currentTime - lastUpdateTime > 86400 {
            state.lastTagRefresh = Date().timeIntervalSince1970
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
                    UserDefaults.standard.set(lastUpdateTime, forKey: SettingsKey.lastTagRefresh)
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
    @Bindable var store: StoreOf<ArchiveListFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(
                    store.scope(state: \.archivesToDisplay, action: \.grid),
                    id: \.state.id
                ) { gridStore in
                    grid(store: store, gridStore: gridStore)
                }
            }
            .padding(.horizontal)
            if store.showLoading {
                ProgressView("loading")
            }
        }
        .toolbar(store.selectMode == .active ? .visible : .hidden, for: .bottomBar)
        .toolbar {
            bottomToolbar()
        }
        .toolbar {
            topBarTrailing()
        }
        .task {
            if store.lanraragiUrl.isEmpty == false &&
                store.archives.isEmpty && store.loadOnAppear {
                store.send(.load(true))
            } else if !store.archivesToDisplay.isEmpty {
                store.send(.refreshDisplayArchives)
            }
        }
        .refreshable {
            if store.currentTab != .search || store.filter.filter?.isEmpty == false {
                await store.send(.load(false)).finish()
            }
        }
        .onChange(of: self.store.searchSort) {
            store.send(.cancelSearch)
            store.send(.resetArchives)
            store.send(.load(true))
        }
        .onChange(of: self.store.searchSortOrder) {
            store.send(.cancelSearch)
            store.send(.resetArchives)
            store.send(.load(true))
        }
        .onChange(of: store.filter) {
            store.send(.cancelSearch)
            store.send(.resetArchives)
            store.send(.load(true))
        }
        .onChange(of: store.lanraragiUrl) {
            if store.lanraragiUrl.isEmpty == false {
                store.send(.cancelSearch)
                store.send(.resetArchives)
                store.send(.load(true))
            }
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
        .onChange(of: store.successMessage) {
            if !store.successMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "success"),
                    subtitle: store.successMessage,
                    style: .success
                )
                banner.show()
                store.send(.setSuccessMessage(""))
            }
        }
    }

    private func contextMenu(gridStore: StoreOf<GridFeature>) -> some View {
        Group {
            NavigationLink(
                state: AppFeature.Path.State.reader(
                    ArchiveReaderFeature.State.init(
                        archive: gridStore.$archive,
                        fromStart: true
                    )
                )
            ) {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                gridStore.send(.load(true))
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }

    private func topBarTrailing() -> ToolbarItemGroup<some View> {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                ForEach(SearchSort.allCases) { sort in
                    let label = "settings.archive.list.order.\(sort)"
                    Button {
                        if store.searchSort == sort.rawValue ||
                            (store.searchSort == store.searchSortCustom && sort == SearchSort.custom) {
                            if store.searchSortOrder == "asc" {
                                store.send(.setSearchSortOrder("desc"))
                            } else {
                                store.send(.setSearchSortOrder("asc"))
                            }
                        } else {
                            if sort == SearchSort.custom {
                                store.send(.setSearchSort(store.searchSortCustom))
                            } else {
                                store.send(.setSearchSort(sort.rawValue))
                            }

                        }
                    } label: {
                        if store.searchSort == sort.rawValue ||
                            (store.searchSort == store.searchSortCustom && sort == SearchSort.custom) {
                            Label(
                                title: { Text(LocalizedStringKey(label)) },
                                icon: {
                                    store.searchSortOrder == "asc" ?
                                    Image(systemName: "arrow.up") :
                                    Image(systemName: "arrow.down")
                                }
                            )
                        } else {
                            Text(LocalizedStringKey(label))
                        }
                    }
                }
                Divider()
                Button {
                    store.send(.toggleHideRead)
                } label: {
                    if store.hideRead {
                        Label("settings.view.hideRead", systemImage: "checkmark")
                    } else {
                        Text("settings.view.hideRead")
                    }

                }

            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
        }
    }

    // swiftlint:disable function_body_length
    private func bottomToolbar() -> ToolbarItemGroup<some View> {
        ToolbarItemGroup(placement: .bottomBar) {
            if store.filter.category == nil {
                Menu {
                    if !store.categoryItems.isEmpty {
                        let staticCategory = store.categoryItems.filter { item in
                            item.search.isEmpty
                        }
                        Text("archive.selected.category.add")
                        ForEach(staticCategory) { item in
                            Button {
                                store.send(.addArchivesToCategory(item.id))
                            } label: {
                                Text(item.name)
                            }
                        }
                    } else {
                        ProgressView("loading")
                            .onAppear {
                                if store.lanraragiUrl.isEmpty == false {
                                    store.send(.loadCategory)
                                }
                            }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(store.selected.isEmpty)
            } else {
                Button(role: .destructive) {
                    store.send(.removeFromCategoryButtonTapped)
                } label: {
                    Image(systemName: "folder.badge.minus")
                }
                .disabled(store.selected.isEmpty)
                .alert(
                    $store.scope(state: \.alert, action: \.alert)
                )
            }
            Spacer()

            Text(
                String.localizedStringWithFormat(
                    String(localized: "archive.selected"),
                    store.selected.count
                )
            )

            Spacer()

            Button(role: .destructive) {
                store.send(.deleteButtonTapped)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selected.isEmpty)
            .alert(
                $store.scope(state: \.alert, action: \.alert)
            )
        }
    }
    // swiftlint:enable function_body_length

    private func grid(
        store: StoreOf<ArchiveListFeature>,
        gridStore: StoreOf<GridFeature>
    ) -> some View {
        ZStack {
            if store.selectMode == .active {
                ArchiveGridV2(store: gridStore)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.selected.contains(gridStore.archive.id) {
                            store.send(.removeSelect(gridStore.archive.id))
                        } else {
                            store.send(.addSelect(gridStore.archive.id))
                        }
                    }
                    .overlay(alignment: .bottomTrailing, content: {
                        if store.selected.contains(gridStore.archive.id) {
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
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    })
            } else {
                NavigationLink(
                    state: AppFeature.Path.State.reader(
                        ArchiveReaderFeature.State.init(
                            archive: gridStore.$archive
                        )
                    )
                ) {
                    ArchiveGridV2(store: gridStore)
                        .onAppear {
                            if gridStore.archive.id == store.archivesToDisplay.last?.archive.id &&
                                store.archives.count < store.total {
                                store.send(.appendArchives(String(store.archives.count)))
                            }
                        }
                        .contextMenu {
                            contextMenu(gridStore: gridStore)
                        }
                }
            }
        }
    }
}
