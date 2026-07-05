import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift
import GRDB
import GRDBQuery

@Reducer public struct ArchiveDetailsFeature: Sendable {
    private let logger = Logger(label: "ArchiveDetailsFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        @Shared var archive: ArchiveItem

        var editMode: EditMode = .inactive
        var title = ""
        var editableTags = ""
        var readOnlyTags = ""
        var tankoubonMetadata: TankoubonDetailsMetadata?
        var errorMessage = ""
        var successMessage = ""
        var loading = false
        let cached: Bool
        var showAlert: Bool = false

        init(
            archive: Shared<ArchiveItem>,
            cached: Bool = false,
            tankoubonMetadata: TankoubonDetailsMetadata? = nil
        ) {
            self._archive = archive
            self.cached = cached
            self.tankoubonMetadata = tankoubonMetadata
        }

        var isTankoubon: Bool {
            archive.id.hasPrefix("TANK_")
        }
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case loadLocalFields
        case updateArchiveMetadata
        case loadCategory
        case populateCategory([CategoryItem])
        case addArchiveToCategory(String)
        case removeArchiveFromCategory(String)
        case updateLocalCategoryItems(String, String, Bool)
        case updateLocalTankoubonMetadata(String, String)
        case setErrorMessage(String)
        case setSuccessMessage(String)
        case confirmDelete

        case deleteButtonTapped
        case deleteSuccess
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .updateArchiveMetadata:
                return .run { [state] send in
                    if let tankoubonMetadata = state.tankoubonMetadata {
                        _ = try await service.updateTankoubon(
                            id: tankoubonMetadata.id,
                            name: state.title,
                            tags: state.editableTags
                        ).value
                        await send(.updateLocalTankoubonMetadata(state.title, state.editableTags))
                    } else {
                        var archive = state.archive
                        archive.name = state.title
                        archive.tags = state.editableTags
                        _ = try await service.updateArchive(archive: archive).value
                        state.$archive.withLock { $0.name = state.title }
                        state.$archive.withLock { $0.tags = state.editableTags }
                    }
                    await send(.setSuccessMessage(
                        String(localized: "archive.metadata.update.success"))
                    )
                } catch: { [id = state.archive.id] error, send in
                    logger.error("failed to update archive. id=\(id) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .loadLocalFields:
                state.title = state.tankoubonMetadata?.name ?? state.archive.name
                state.editableTags = state.tankoubonMetadata?.tags ?? state.archive.tags
                state.readOnlyTags = state.tankoubonMetadata?.includedArchiveTags ?? ""
                return .none
            case .deleteButtonTapped:
                state.showAlert = true
                return .none
            case .confirmDelete:
                state.loading = true
                return .run { [id = state.archive.id] send in
                    let response = if id.hasPrefix("TANK_") {
                        try await service.deleteTankoubon(id: id).value
                    } else {
                        try await service.deleteArchive(id: id).value
                    }
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
                    }.sorted { first, second in
                        if first.pinned != "1" && second.pinned == "1" {
                            return false
                        } else {
                            return true
                        }
                    }
                    await send(.populateCategory(items))
                } catch: { error, send in
                    logger.error("failed to load category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .populateCategory(items):
                state.$categoryItems.withLock { $0 = IdentifiedArray(uniqueElements: items) }
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
                    state.$categoryItems.withLock {
                        $0[id: categoryId]?.archives.append(archiveId)
                    }
                } else {
                    state.$categoryItems.withLock {
                        $0[id: categoryId]?.archives.removeAll { id in
                            id == archiveId
                        }
                    }
                }
                return .none
            case let .updateLocalTankoubonMetadata(title, tags):
                state.tankoubonMetadata?.name = title
                state.tankoubonMetadata?.tags = tags
                state.$archive.withLock { $0.name = title }
                if let tankoubonMetadata = state.tankoubonMetadata {
                    state.$archive.withLock { $0.tags = tankoubonMetadata.combinedTags }
                }
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                state.loading = false
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .deleteSuccess:
                state.$archiveItems.withLock {
                    _ = $0.remove(id: state.archive.id)
                }
                return .none
            case .binding:
                return .none
            }
        }
    }
}

struct ArchiveDetailsV2: View {
    @Query<ThumbnailRequest> var thumbnailObj: ArchiveThumbnail?

    @Environment(\.openURL) var openURL

    @Bindable var store: StoreOf<ArchiveDetailsFeature>
    let onDelete: () -> Void
    let onTagNavigation: (StoreOf<SearchFeature>) -> Void

    init(
        store: StoreOf<ArchiveDetailsFeature>,
        onDelete: @escaping () -> Void,
        onTagNavigation: @escaping (StoreOf<SearchFeature>) -> Void
    ) {
        self.store = store
        self.onDelete = onDelete
        self.onTagNavigation = onTagNavigation
        self._thumbnailObj = Query(ThumbnailRequest(id: store.archive.id))
    }

    var body: some View {
        let deleteConfirmationTitle: LocalizedStringKey = store.isTankoubon
            ? "archive.delete.tankoubon.confirm"
            : "archive.delete.confirm"

        ScrollView {
            VStack(spacing: 22) {
                headerView(store: store)
                tagsView(store: store)
                deleteButton(store: store)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
                    Label("archive.category.manage", systemImage: "folder.badge.gear")
                        .labelStyle(.iconOnly)
                }
                .disabled(store.loading)
                EditButton()
                    .disabled(store.loading)
            }
        }
        .environment(\.editMode, $store.editMode)
        .alert(deleteConfirmationTitle, isPresented: $store.showAlert) {
            Button("cancel", role: .cancel) { }
            Button("delete", role: .destructive) {
                Task {
                    await store.send(.confirmDelete).finish()
                }
                onDelete()
            }
        } message: {
            if store.isTankoubon {
                Text("archive.delete.tankoubon.confirm.message")
            }
        }
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

    private func headerView(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnailView()

            titleView(store: store)
                .padding(.top, 4)
                .layoutPriority(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    @ViewBuilder
    private func titleView(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        if store.editMode == .active {
            VStack(alignment: .leading, spacing: 10) {
                Text("archive.details.title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                TextField("archive.details.title", text: $store.title, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.title3.weight(.semibold))
                    .lineLimit(2...8)
                    .padding(14)
                    .background(
                        Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("archive.details.title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(store.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tagsView(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        let editableGroups = ArchiveDetailsTagParser.tagGroups(from: store.editableTags)
        let readOnlyGroups = ArchiveDetailsTagParser.tagGroups(from: store.readOnlyTags)
        let tagCount = (editableGroups + readOnlyGroups).reduce(0) { count, group in
            count + group.tags.count
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("archive.details.tags", systemImage: "tag")
                    .font(.headline)

                Spacer()

                if tagCount > 0 && store.editMode != .active {
                    Text("\(tagCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            if store.tankoubonMetadata != nil {
                tankTagsView(store: store, editableGroups: editableGroups, readOnlyGroups: readOnlyGroups)
            } else {
                archiveTagsView(store: store, groups: editableGroups)
            }
        }
    }

    @ViewBuilder
    private func archiveTagsView(
        store: StoreOf<ArchiveDetailsFeature>,
        groups: [ArchiveTagGroup]
    ) -> some View {
        if store.editMode == .active {
            editableTagsField(store: store)
        } else if groups.isEmpty {
            emptyTagsView()
        } else {
            ForEach(groups) { group in
                tagGroupView(group)
            }
        }
    }

    @ViewBuilder
    private func tankTagsView(
        store: StoreOf<ArchiveDetailsFeature>,
        editableGroups: [ArchiveTagGroup],
        readOnlyGroups: [ArchiveTagGroup]
    ) -> some View {
        tagSectionHeader("archive.details.tags.tankMetadata")

        if store.editMode == .active {
            editableTagsField(store: store)
        } else if editableGroups.isEmpty {
            emptyTagsView()
        } else {
            ForEach(editableGroups) { group in
                tagGroupView(group)
            }
        }

        if !readOnlyGroups.isEmpty {
            tagSectionHeader("archive.details.tags.included", readOnly: true)
            ForEach(readOnlyGroups) { group in
                tagGroupView(group, navigationEnabled: store.editMode != .active)
            }
        }
    }

    private func editableTagsField(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        TextField("archive.details.tags", text: $store.editableTags, axis: .vertical)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .lineLimit(5...14)
            .padding(14)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func emptyTagsView() -> some View {
        Label("archive.tags.empty", systemImage: "tag")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func tagSectionHeader(_ titleKey: LocalizedStringKey, readOnly: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if readOnly {
                Label("archive.details.tags.readOnly", systemImage: "lock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func thumbnailView() -> some View {
        Group {
            if let thumbnailData = thumbnailObj?.thumbnail, let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                Image("noThumb")
                    .resizable()
            }
        }
        .scaledToFit()
        .padding(8)
        .frame(width: 132, height: 178)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func deleteButton(store: StoreOf<ArchiveDetailsFeature>) -> some View {
        if store.editMode != .active && !store.cached {
            Button(
                role: .destructive,
                action: { store.send(.deleteButtonTapped) },
                label: {
                    let titleKey: LocalizedStringKey = store.isTankoubon
                        ? "archive.delete.tankoubon"
                        : "archive.delete"

                    Label(titleKey, systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Color.red, in: Capsule())
                        .contentShape(Capsule())
                }
            )
            .buttonStyle(.plain)
            .disabled(store.loading)
            .opacity(store.loading ? 0.55 : 1)
        }
    }

    private func tagGroupView(_ group: ArchiveTagGroup, navigationEnabled: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            WrappingHStack(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(group.tags) { tag in
                    tagButton(tag, navigationEnabled: navigationEnabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func tagButton(_ tag: ArchiveDetailsTag, navigationEnabled: Bool = true) -> some View {
        let tint = tagTint(for: tag.namespaceKey)

        return Button {
            guard navigationEnabled else { return }
            if tag.namespaceKey == ArchiveDetailsTagParser.sourceTag, let url = sourceURL(for: tag) {
                openURL(url)
            } else {
                navigateToTag(tag.raw)
            }
        } label: {
            HStack(spacing: 6) {
                if let iconName = tagIconName(for: tag.namespaceKey) {
                    Image(systemName: iconName)
                        .font(.caption2.weight(.bold))
                }

                Text(tag.displayText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: 280, alignment: .leading)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!navigationEnabled)
        .accessibilityLabel(Text(verbatim: tag.accessibilityLabel))
    }

    private func tagTint(for namespaceKey: String) -> Color {
        switch namespaceKey {
        case ArchiveDetailsTagParser.artistTag:
            return .orange
        case ArchiveDetailsTagParser.sourceTag:
            return .teal
        case ArchiveDetailsTagParser.dateTag:
            return .indigo
        case ArchiveDetailsTagParser.otherTag:
            return .secondary
        default:
            return .blue
        }
    }

    private func tagIconName(for namespaceKey: String) -> String? {
        switch namespaceKey {
        case ArchiveDetailsTagParser.sourceTag:
            return "link"
        case ArchiveDetailsTagParser.dateTag:
            return "calendar"
        default:
            return nil
        }
    }

    private func sourceURL(for tag: ArchiveDetailsTag) -> URL? {
        let value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        let lowercasedValue = value.lowercased()
        let urlString = if lowercasedValue.hasPrefix("http://") || lowercasedValue.hasPrefix("https://") {
            value
        } else {
            "https://\(value)"
        }
        return URL(string: urlString)
    }

    private func navigateToTag(_ tag: String) {
        let normalizedTag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        let searchStore = Store(initialState: SearchFeature.State.init(
            keyword: normalizedTag,
            archiveList: ArchiveListFeature.State(
                filter: SearchFilter(category: nil, filter: normalizedTag),
                loadOnAppear: true,
                currentTab: .search
            )
        )) {
            SearchFeature()
        }
        onTagNavigation(searchStore)
    }
}
