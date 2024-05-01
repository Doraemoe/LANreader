import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveDetailsFeature {
    private let logger = Logger(label: "ArchiveDetailsFeature")

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        var id: String
        var editMode: EditMode = .inactive
        var title = ""
        var tags = ""
        var errorMessage = ""
        var successMessage = ""
        var archiveMetadata: ArchiveMetadata?
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var loading = false
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case loadMetadata
        case updateArchiveMetadata
        case loadCategory
        case populateCategory([CategoryItem])
        case addArchiveToCategory(String)
        case removeArchiveFromCategory(String)
        case updateLocalCategoryItems(String, String, Bool)
        case setArchiveMetadata(ArchiveMetadata)
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
    @Dependency(\.refreshTrigger) var refreshTrigger

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .loadMetadata:
                state.loading = true
                return .run { [state] send in
                    let metadata = try await service.retrieveArchiveMetadata(id: state.id).value
                    let thumbnailData = try database.readArchiveThumbnail(state.id)
                    await send(
                        .setArchiveMetadata(
                            ArchiveMetadata(
                                archive: metadata.toArchiveItem(), archiveThumbnail: thumbnailData
                            )
                        )
                    )
                } catch: { [state] error, send in
                    logger.error("failed to load archive details. id=\(state.id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .updateArchiveMetadata:
                return .run { [state] send in
                    var archive = state.archiveMetadata!.archive
                    archive.name = state.title
                    archive.tags = state.tags
                    _ = try await service.updateArchive(archive: archive).value
                    await send(.setSuccessMessage(
                        String(localized: "archive.metadata.update.success"))
                    )
                } catch: { [id = state.id] error, send in
                    logger.error("failed to update archive. id=\(id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .setArchiveMetadata(metadata):
                state.archiveMetadata = metadata
                state.title = metadata.archive.name
                state.tags = metadata.archive.tags
                state.loading = false
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
                return .run { [id = state.id] send in
                    let response = try await service.deleteArchive(id: id).value
                    if response.success == 1 {
                        refreshTrigger.delete.send(id)
                        await send(.deleteSuccess)
                    } else {
                        await send(.setErrorMessage(String(localized: "error.archive.delete")))
                    }
                } catch: { [id = state.id] error, send in
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
                    if state.categoryItems[id: categoryId]?.archives.contains(state.id) == false {
                        let response = try await service.addArchiveToCategory(
                            categoryId: categoryId, archiveId: state.id
                        ).value
                        if response.success == 1 {
                            await send(.setSuccessMessage(
                                String(localized: "archive.category.add.success"))
                            )
                            await send(.updateLocalCategoryItems(state.id, categoryId, true))
                        } else {
                            await send(.setErrorMessage(
                                String(localized: "archive.category.add.error"))
                            )
                        }
                    }
                } catch: { [id = state.id] error, send in
                    logger.error(
                        "failed to add archive to category. categoryId=\(categoryId), archiveId=\(id) \(error)"
                    )
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .removeArchiveFromCategory(categoryId):
                return .run { [state] send in
                    if state.categoryItems[id: categoryId]?.archives.contains(state.id) == true {
                        let response = try await service.removeArchiveFromCategory(
                            categoryId: categoryId, archiveId: state.id
                        ).value
                        if response.success == 1 {
                            await send(.setSuccessMessage(
                                String(localized: "archive.category.remove.success"))
                            )
                            await send(.updateLocalCategoryItems(state.id, categoryId, false))
                        } else {
                            await send(.setErrorMessage(
                                String(localized: "archive.category.remove.error"))
                            )
                        }
                    }
                } catch: { [id = state.id] error, send in
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
                return .none
            case .binding:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    struct ArchiveMetadata: Equatable {
        let archive: ArchiveItem
        let archiveThumbnail: ArchiveThumbnail?
    }
}

struct ArchiveDetailsV2: View {
    private static let sourceTag = "source"
    private static let dateTag = "date_added"

    @Bindable var store: StoreOf<ArchiveDetailsFeature>

    var body: some View {
        ScrollView {
            if store.archiveMetadata != nil {
                titleView(store: store)
                if let imageData = store.archiveMetadata!.archiveThumbnail?.thumbnail {
                    Image(uiImage: UIImage(data: imageData)!)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .frame(width: 200, height: 250)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.primary)
                }
                tagsView(store: store)
                if store.editMode != .active {
                    Button(
                        role: .destructive,
                        action: { store.send(.deleteButtonTapped) },
                        label: {
                            Text("archive.delete")
                        }
                    )
                    .padding()
                    .background(.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .disabled(store.loading)
                }
            } else {
                ProgressView("loading")
                    .onAppear {
                        store.send(.loadMetadata)
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if !store.categoryItems.isEmpty {
                        let staticCategory = store.categoryItems.filter { item in
                            item.search.isEmpty
                        }
                        Text("archive.category.manage")
                        ForEach(staticCategory) { item in
                            Button {
                                if item.archives.contains(store.id) {
                                    store.send(.removeArchiveFromCategory(item.id))
                                } else {
                                    store.send(.addArchiveToCategory(item.id))
                                }
                            } label: {
                                if item.archives.contains(store.id) {
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
                            .foregroundColor(.white)
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
