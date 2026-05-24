import ComposableArchitecture
import Logging
import SwiftUI
import NotificationBannerSwift

@Reducer public struct CategoryFeature: Sendable {
    private let logger = Logger(label: "CategoryFeature")

    @ObservableState
    public struct State: Equatable {
        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []

        var showLoading = false
        var errorMessage = ""
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)

        case loadCategory(Bool)
        case populateCategory([CategoryItem])
        case setErrorMessage(String)
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
                    let items = categories
                        .map { item in
                            item.toCategoryItem()
                        }
                        .enumerated()
                        .sorted { first, second in
                            if first.element.pinned == second.element.pinned {
                                return first.offset < second.offset
                            }
                            return first.element.pinned == "1"
                        }
                        .map { $0.element }
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
            case .binding:
                return .none
            }
        }
    }
}

struct CategoryListV2: View {
    @Bindable var store: StoreOf<CategoryFeature>
    let onTapCategory: (StoreOf<CategoryArchiveListFeature>) -> Void
    @State private var searchText = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background

                categoryList

                if store.showLoading {
                    LoadingView(geometry: geometry)
                        .transition(.opacity)
                }
            }
        }
        .task {
            if store.categoryItems.isEmpty {
                store.send(.loadCategory(true))
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
        .onChange(of: store.lanraragiUrl) {
            if !store.lanraragiUrl.isEmpty {
                store.send(.loadCategory(true))
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var background: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !store.categoryItems.isEmpty {
                    searchField
                }

                if visibleItems.isEmpty && !store.showLoading {
                    emptyState
                        .padding(.top, 84)
                } else {
                    ForEach(visibleItems) { item in
                        categoryButton(item: item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .refreshable {
            await store.send(.loadCategory(false)).finish()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("search", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Label("delete", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("category.empty", systemImage: "folder")
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var visibleItems: [CategoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return Array(store.categoryItems)
        }
        return store.categoryItems.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || item.search.localizedCaseInsensitiveContains(query)
        }
    }

    private func categoryButton(item: CategoryItem) -> some View {
        Button {
            onTapCategory(makeCategoryStore(for: item))
        } label: {
            CategoryRowView(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: categoryAccessibilityLabel(for: item)))
        .accessibilityHint(Text("details"))
    }

    private func makeCategoryStore(for item: CategoryItem) -> StoreOf<CategoryArchiveListFeature> {
        Store(
            initialState: CategoryArchiveListFeature.State(
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
    }

    private func categoryAccessibilityLabel(for item: CategoryItem) -> String {
        var components = [item.name]

        if item.pinned == "1" {
            components.append(String(localized: "category.accessibility.pinned"))
        }

        let searchKeyword = normalizedSearchKeyword(for: item)
        if searchKeyword.isEmpty {
            let format = String(localized: "category.accessibility.archiveCount %lld")
            components.append(String.localizedStringWithFormat(format, item.archives.count))
        } else {
            let format = String(localized: "category.accessibility.dynamicSearch %@")
            components.append(String.localizedStringWithFormat(format, searchKeyword))
        }

        return components.joined(separator: ", ")
    }

    private func normalizedSearchKeyword(for item: CategoryItem) -> String {
        item.search
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct CategoryRowView: View {
    let item: CategoryItem

    private var isPinned: Bool {
        item.pinned == "1"
    }

    private var isDynamic: Bool {
        !searchKeyword.isEmpty
    }

    private var searchKeyword: String {
        item.search
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                titleRow

                HStack(spacing: 7) {
                    if isDynamic {
                        metadataChip(systemImage: "magnifyingglass", title: Text(verbatim: searchKeyword))
                    } else {
                        countChip
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color(uiColor: .systemOrange), in: Circle())
            }
        }
    }

    private var countChip: some View {
        Label {
            Text("\(item.archives.count)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "rectangle.stack.fill")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    private func metadataChip(systemImage: String, title: Text) -> some View {
        Label {
            title
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}
