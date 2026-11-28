import ComposableArchitecture
import Foundation
import Logging

public struct ChapterMutationTarget: Equatable, Sendable {
    let readerArchiveId: String
    let readerPageNumber: Int
    let sourceArchiveId: String
    let sourcePageNumber: Int
}

public struct ReaderChapterPage: Equatable, Sendable {
    public let pageNumber: Int
    public let sourceArchiveId: String
    public let sourcePageNumber: Int

    public init(pageNumber: Int, sourceArchiveId: String, sourcePageNumber: Int) {
        self.pageNumber = pageNumber
        self.sourceArchiveId = sourceArchiveId
        self.sourcePageNumber = sourcePageNumber
    }

    init(page: PageFeature.State) {
        self.pageNumber = page.pageNumber
        self.sourceArchiveId = page.sourceArchiveId
        self.sourcePageNumber = page.sourcePageNumber
    }
}

public struct ReaderChapterContext: Equatable, Sendable {
    var archiveId = ""
    var cached = false
    var pages: [ReaderChapterPage] = []
    var currentPageIndex = 0
    var chapters: [ArchiveChapter] = []
    var automaticChapterPages: Set<Int>?
}

public struct ReaderChapterState: Equatable, Sendable {
    var creationTarget: ChapterMutationTarget?
    var editingTarget: ChapterMutationTarget?
    var title = ""
    var requestInFlight = false
    var mutationsSupported: Bool?

    public init() {}

    mutating func resetTransientState() {
        creationTarget = nil
        editingTarget = nil
        title = ""
        requestInFlight = false
    }
}

@Reducer public struct ReaderChapterFeature: Sendable {
    private let logger = Logger(label: "ReaderChapterFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        var archiveId = ""
        var cached = false
        var pages: [ReaderChapterPage] = []
        var currentPageIndex = 0
        var chapters: [ArchiveChapter] = []
        var automaticChapterPages: Set<Int>?
        var stored = ReaderChapterState()

        init(
            context: ReaderChapterContext = ReaderChapterContext(),
            stored: ReaderChapterState = ReaderChapterState()
        ) {
            self.archiveId = context.archiveId
            self.cached = context.cached
            self.pages = context.pages
            self.currentPageIndex = context.currentPageIndex
            self.chapters = context.chapters
            self.automaticChapterPages = context.automaticChapterPages
            self.stored = stored
        }

        var currentPage: ReaderChapterPage? {
            guard !pages.isEmpty else { return nil }
            return pages[ReaderPositioning.clampedPageIndex(currentPageIndex, pageCount: pages.count)]
        }

        var canAddChapter: Bool {
            !cached && stored.mutationsSupported != false && currentPage != nil
        }

        var editableChapterPages: Set<Int> {
            ReaderChapterFeature.editableChapterPages(
                archiveId: archiveId,
                cached: cached,
                mutationsSupported: stored.mutationsSupported,
                chapters: chapters,
                automaticChapterPages: automaticChapterPages
            )
        }
    }

    public enum Action: Equatable {
        case mutationSupportResolved(Bool?)
        case creationRequested
        case editingRequested(Int)
        case titleChanged(String)
        case cancelMutation
        case confirmMutation
        case confirmDeletion
        case saved(target: ChapterMutationTarget, title: String)
        case saveFailed(target: ChapterMutationTarget, title: String, isEditing: Bool)
        case deleted(target: ChapterMutationTarget)
        case deleteFailed(target: ChapterMutationTarget, title: String)
        case selected(Int)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case jumpRequested(Int)
            case saved(target: ChapterMutationTarget, title: String)
            case deleted(target: ChapterMutationTarget)
            case errorOccurred(String)
        }
    }

    @Dependency(\.lanraragiService) var service

    public enum CancelId: Sendable {
        case mutation
    }

    public static func cancelEffects<ParentAction>() -> Effect<ParentAction> {
        .cancel(id: CancelId.mutation)
    }

    static func editableChapterPages(
        archiveId: String,
        cached: Bool,
        mutationsSupported: Bool?,
        chapters: [ArchiveChapter],
        automaticChapterPages: Set<Int>?
    ) -> Set<Int> {
        guard !cached, mutationsSupported != false else { return [] }
        let chapterPages = Set(chapters.map(\.page))
        guard archiveId.isTankoubonArchiveId else { return chapterPages }
        guard let automaticChapterPages else { return [] }
        return chapterPages.subtracting(automaticChapterPages)
    }

    static func chaptersBySaving(
        _ title: String,
        at page: Int,
        in chapters: [ArchiveChapter]
    ) -> [ArchiveChapter] {
        var updated = chapters
        updated.removeAll { $0.page == page }
        updated.append(ArchiveChapter(name: title, page: page))
        updated.sort { $0.page < $1.page }
        return updated
    }

    static func applyChapterDeletion(
        at page: Int,
        chapters: [ArchiveChapter],
        defaultChapters: [ArchiveChapter]
    ) -> (chapters: [ArchiveChapter], restoredDefaultPage: Int?) {
        var updated = chapters
        updated.removeAll { $0.page == page }
        var restoredDefaultPage: Int?
        if let defaultChapter = defaultChapters.first(where: { $0.page == page }) {
            updated.append(defaultChapter)
            updated.sort { $0.page < $1.page }
            restoredDefaultPage = defaultChapter.page
        }
        return (updated, restoredDefaultPage)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(state: &state, action: action)
        }
    }
}

private extension ReaderChapterFeature {
    func reduce(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .mutationSupportResolved(isSupported):
            state.stored.mutationsSupported = isSupported
            guard isSupported == false else { return .none }
            state.stored.resetTransientState()
            return Self.cancelEffects()
        case .creationRequested:
            return handleCreationRequested(state: &state)
        case let .editingRequested(pageNumber):
            return handleEditingRequested(pageNumber: pageNumber, state: &state)
        case let .titleChanged(title):
            state.stored.title = title
            return .none
        case .cancelMutation:
            state.stored.creationTarget = nil
            state.stored.editingTarget = nil
            state.stored.title = ""
            return .none
        case .confirmMutation:
            return handleConfirmMutation(state: &state)
        case .confirmDeletion:
            return handleConfirmDeletion(state: &state)
        case let .saved(target, title):
            state.stored.requestInFlight = false
            return .send(.delegate(.saved(target: target, title: title)))
        case let .saveFailed(target, title, isEditing):
            return handleSaveFailed(target: target, title: title, isEditing: isEditing, state: &state)
        case let .deleted(target):
            state.stored.requestInFlight = false
            return .send(.delegate(.deleted(target: target)))
        case let .deleteFailed(target, title):
            state.stored.requestInFlight = false
            state.stored.editingTarget = target
            state.stored.title = title
            return .send(.delegate(.errorOccurred(String(localized: "archive.reader.chapter.delete.failed"))))
        case let .selected(pageNumber):
            guard let pageIndex = state.pages.firstIndex(where: { $0.pageNumber == pageNumber }) else {
                return .none
            }
            return .send(.delegate(.jumpRequested(pageIndex)))
        case .delegate:
            return .none
        }
    }

    func handleSaveFailed(
        target: ChapterMutationTarget,
        title: String,
        isEditing: Bool,
        state: inout State
    ) -> Effect<Action> {
        state.stored.requestInFlight = false
        if isEditing {
            state.stored.editingTarget = target
        } else {
            state.stored.creationTarget = target
        }
        state.stored.title = title
        let key = isEditing ? "archive.reader.chapter.edit.failed" : "archive.reader.chapter.add.failed"
        return .send(.delegate(.errorOccurred(String(localized: String.LocalizationValue(key)))))
    }

    func handleCreationRequested(state: inout State) -> Effect<Action> {
        guard state.canAddChapter,
              !state.stored.requestInFlight,
              state.stored.editingTarget == nil,
              let page = state.currentPage else {
            return .none
        }
        state.stored.creationTarget = ChapterMutationTarget(
            readerArchiveId: state.archiveId,
            readerPageNumber: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        state.stored.title = ""
        return .none
    }

    func handleEditingRequested(pageNumber: Int, state: inout State) -> Effect<Action> {
        guard state.editableChapterPages.contains(pageNumber),
              !state.stored.requestInFlight,
              state.stored.creationTarget == nil,
              let chapter = state.chapters.first(where: { $0.page == pageNumber }),
              let page = state.pages.first(where: { $0.pageNumber == pageNumber }) else {
            return .none
        }
        state.stored.editingTarget = ChapterMutationTarget(
            readerArchiveId: state.archiveId,
            readerPageNumber: pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        state.stored.title = chapter.name
        return .none
    }

    func handleConfirmMutation(state: inout State) -> Effect<Action> {
        let isEditing = state.stored.editingTarget != nil
        guard let target = state.stored.editingTarget ?? state.stored.creationTarget else { return .none }
        let draft = state.stored.title
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .none }
        state.stored.creationTarget = nil
        state.stored.editingTarget = nil
        state.stored.title = ""
        state.stored.requestInFlight = true
        return .run { send in
            await performChapterSave(target: target, draft: draft, title: title, isEditing: isEditing, send: send)
        }
        .cancellable(id: CancelId.mutation, cancelInFlight: true)
    }

    func performChapterSave(
        target: ChapterMutationTarget,
        draft: String,
        title: String,
        isEditing: Bool,
        send: Send<Action>
    ) async {
        do {
            let response = try await service.addArchiveChapter(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber,
                title: title
            ).value
            guard response.success == 1 else {
                await send(.saveFailed(target: target, title: draft, isEditing: isEditing))
                return
            }
            await send(.saved(target: target, title: title))
        } catch {
            let source = "\(target.sourceArchiveId):\(target.sourcePageNumber)"
            logger.warning("failed to save chapter. source=\(source) \(error.localizedDescription)")
            await send(.saveFailed(target: target, title: draft, isEditing: isEditing))
        }
    }

    func handleConfirmDeletion(state: inout State) -> Effect<Action> {
        guard let target = state.stored.editingTarget else { return .none }
        let title = state.stored.title
        state.stored.editingTarget = nil
        state.stored.title = ""
        state.stored.requestInFlight = true
        return .run { send in
            await performChapterDeletion(target: target, title: title, send: send)
        }
        .cancellable(id: CancelId.mutation, cancelInFlight: true)
    }

    func performChapterDeletion(
        target: ChapterMutationTarget,
        title: String,
        send: Send<Action>
    ) async {
        do {
            let response = try await service.deleteArchiveChapter(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber
            ).value
            guard response.success == 1 else {
                await send(.deleteFailed(target: target, title: title))
                return
            }
            await send(.deleted(target: target))
        } catch {
            let source = "\(target.sourceArchiveId):\(target.sourcePageNumber)"
            logger.warning("failed to delete chapter. source=\(source) \(error.localizedDescription)")
            await send(.deleteFailed(target: target, title: title))
        }
    }
}
