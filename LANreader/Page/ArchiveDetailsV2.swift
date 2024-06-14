import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveDetailsFeature {
    private let logger = Logger(label: "ArchiveDetailsFeature")

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        @Shared var archive: ArchiveItem

        var thumbnailPath: URL?
        var editMode: EditMode = .inactive
        var title = ""
        var tags = ""
        var errorMessage = ""
        var successMessage = ""
        var loading = false
        let cached: Bool

        init(archive: Shared<ArchiveItem>, cached: Bool = false) {
            self._archive = archive
            self.thumbnailPath = LANraragiService.thumbnailPath?
                .appendingPathComponent(archive.id, conformingTo: .image)
            self.cached = cached
        }
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case loadLocalFields
        case updateArchiveMetadata
        case loadCategory
        case populateCategory([CategoryItem])
        case addArchiveToCategory(String)
        case removeArchiveFromCategory(String)
        case updateLocalCategoryItems(String, String, Bool)
        case setErrorMessage(String)
        case setSuccessMessage(String)

        case deleteButtonTapped
        case deleteSuccess
        enum Alert {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .updateArchiveMetadata:
                return .run { [state] send in
                    var archive = state.archive
                    archive.name = state.title
                    archive.tags = state.tags
                    _ = try await service.updateArchive(archive: archive).value
                    state.archive.name = state.title
                    state.archive.tags = state.tags
                    await send(.setSuccessMessage(
                        String(localized: "archive.metadata.update.success"))
                    )
                } catch: { [id = state.archive.id] error, send in
                    logger.error("failed to update archive. id=\(id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .loadLocalFields:
                state.title = state.archive.name
                state.tags = state.archive.tags
                return .none
            case .deleteButtonTapped:
                state.alert = AlertState {
                    TextState("archive.delete.confirm")
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
                state.loading = true
                return .run { [id = state.archive.id] send in
                    let response = try await service.deleteArchive(id: id).value
                    if response.success == 1 {
                        await send(.deleteSuccess)
                    } else {
                        await send(.setErrorMessage(String(localized: "error.archive.delete")))
                    }
                } catch: { [id = state.archive.id] error, send in
                    logger.error("failed to delete archive, id=\(id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
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
            case let .addArchiveToCategory(categoryId):
                return .run { [state] send in
                    let categoryArchives = state.$categoryItems.withLock { $0[id: categoryId]?.archives }
                    if categoryArchives?.contains(state.archive.id) == false {
                        let response = try await service.addArchiveToCategory(
                            categoryId: categoryId, archiveId: state.archive.id
                        ).value
                        if response.success == 1 {
                            await send(.setSuccessMessage(
                                String(localized: "archive.category.add.success"))
                            )
                            await send(.updateLocalCategoryItems(state.archive.id, categoryId, true))
                        } else {
                            await send(.setErrorMessage(
                                String(localized: "archive.category.add.error"))
                            )
                        }
                    }
                } catch: { [id = state.archive.id] error, send in
                    logger.error(
                        "failed to add archive to category. categoryId=\(categoryId), archiveId=\(id) \(error)"
                    )
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .removeArchiveFromCategory(categoryId):
                return .run { [state] send in
                    let categoryArchives = state.$categoryItems.withLock { $0[id: categoryId]?.archives }
                    if categoryArchives?.contains(state.archive.id) == true {
                        let response = try await service.removeArchiveFromCategory(
                            categoryId: categoryId, archiveId: state.archive.id
                        ).value
                        if response.success == 1 {
                            await send(.setSuccessMessage(
                                String(localized: "archive.category.remove.success"))
                            )
                            await send(.updateLocalCategoryItems(state.archive.id, categoryId, false))
                        } else {
                            await send(.setErrorMessage(
                                String(localized: "archive.category.remove.error"))
                            )
                        }
                    }
                } catch: { [id = state.archive.id] error, send in
                    logger.error(
                        "failed to remove archive from category. categoryId=\(categoryId), archiveId=\(id) \(error)"
                    )
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .updateLocalCategoryItems(archiveId, categoryId, isAdd):
                if isAdd {
                    state.categoryItems[id: categoryId]?.archives.append(archiveId)
                } else {
                    state.categoryItems[id: categoryId]?.archives.removeAll { id in
                        id == archiveId
                    }
                }
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                state.loading = false
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .alert:
                return .none
            case .deleteSuccess:
                state.archiveItems.remove(id: state.archive.id)
                return .none
            case .binding:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

struct ArchiveDetailsV2: View {
    private static let sourceTag = "source"
    private static let dateTag = "date_added"

    @Bindable var store: StoreOf<ArchiveDetailsFeature>

    var body: some View {
        ScrollView {
            titleView(store: store)
            AsyncImage(url: store.thumbnailPath) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .frame(width: 200, height: 250)
            } placeholder: {
                Image(systemName: "photo")
                    .foregroundStyle(Color.primary)
                    .frame(width: 200, height: 250)
            }
            tagsView(store: store)
            Button(
                role: .destructive,
                action: { store.send(.deleteButtonTapped) },
                label: {
                    Text("archive.delete")
                }
            )
            .padding()
            .background(.red)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .disabled(store.loading)
            .opacity(store.editMode != .active && !store.cached ? 1 : 0)
        }
        .onAppear {
            store.send(.loadLocalFields)
        }
        .toolbar {
            store.cached ? nil :
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if !store.categoryItems.isEmpty {
                        let staticCategory = store.categoryItems.filter { item in
                            item.search.isEmpty
                        }
                        Text("archive.category.manage")
                        ForEach(staticCategory) { item in
                            Button {
                                if item.archives.contains(store.archive.id) {
                                    store.send(.removeArchiveFromCategory(item.id))
                                } else {
                                    store.send(.addArchiveToCategory(item.id))
                                }
                            } label: {
                                if item.archives.contains(store.archive.id) {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    } else {
                        ProgressView("loading")
                            .onAppear {
                                store.send(.loadCategory)
                            }
                    }
                } label: {
                    Image(systemName: "folder.badge.gear")
                }
                .disabled(store.loading)
                EditButton()
                    .disabled(store.loading)
            }
        }
        .environment(\.editMode, $store.editMode)
        .alert(
            $store.scope(state: \.alert, action: \.alert)
        )
        .onChange(of: store.editMode) { oldMode, newMode in
            if oldMode == .active && newMode == .inactive {
                store.send(.updateArchiveMetadata)
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

    @MainActor
    private func titleView(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        ZStack {
            if store.editMode == .active {
                TextField("", text: $store.title, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding()
            } else {
                Text(store.title)
                    .textFieldStyle(.roundedBorder)
                    .textSelection(.enabled)
                    .padding()
            }
        }
    }

    @MainActor
    private func tagsView(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        ZStack {
            if store.editMode == .active {
                TextField("", text: $store.tags, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding()
            } else {
                WrappingHStack(
                    models: store.tags.split(separator: ","),
                    viewGenerator: { tag in
                        parseTag(tag: String(tag))
                            .padding()
                            .controlSize(.mini)
                            .foregroundStyle(.white)
                            .background(.blue)
                            .clipShape(Capsule())
                    })
                .padding()
            }
        }
    }

    private func parseTag(tag: String) -> some View {
        let tagPair = tag.split(separator: ":", maxSplits: 1)

        let tagName = tagPair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let tagValue = tagPair.count == 2 ? tagPair[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if tagName == ArchiveDetailsV2.sourceTag {
            let urlString = tagValue.hasPrefix("http") ? tagValue : "https://\(tagValue)"
            return AnyView(
                Link(destination: URL(string: urlString)!) {
                    Text(tag)
                        .lineLimit(1)
                }
            )
        }
        let processedTag: String
        if tagName == ArchiveDetailsV2.dateTag {
            let date = Date(timeIntervalSince1970: TimeInterval(tagValue) ?? 0)
            processedTag = "\(ArchiveDetailsV2.dateTag): \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            processedTag = tag
        }
        let normalizedTag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        return AnyView(
            NavigationLink(
                state: AppFeature.Path.State.search(
                    SearchFeature.State.init(
                        keyword: normalizedTag, archiveList: ArchiveListFeature.State(
                            filter: SearchFilter(category: nil, filter: normalizedTag),
                            loadOnAppear: true,
                            currentTab: .search
                        )
                    )
                )
            ) {
                Text(processedTag)
                    .lineLimit(1)
            }
        )
    }
}
