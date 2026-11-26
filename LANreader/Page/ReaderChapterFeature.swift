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
        var creationTarget: ChapterMutationTarget?
        var editingTarget: ChapterMutationTarget?
        var title = ""
        var requestInFlight = false
        var mutationsSupported: Bool?

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
            self.creationTarget = stored.creationTarget
            self.editingTarget = stored.editingTarget
            self.title = stored.title
            self.requestInFlight = stored.requestInFlight
            self.mutationsSupported = stored.mutationsSupported
        }

        var currentPage: ReaderChapterPage? {
            guard !pages.isEmpty else { return nil }
            return pages[ReaderPositioning.clampedPageIndex(currentPageIndex, pageCount: pages.count)]
        }

        var canAddChapter: Bool {
            !cached && mutationsSupported != false && currentPage != nil
        }

        var editableChapterPages: Set<Int> {
            ReaderChapterFeature.editableChapterPages(
                archiveId: archiveId,
                cached: cached,
                mutationsSupported: mutationsSupported,
                chapters: chapters,
                automaticChapterPages: automaticChapterPages
            )
        }

        var stored: ReaderChapterState {
            var snapshot = ReaderChapterState()
            snapshot.creationTarget = creationTarget
            snapshot.editingTarget = editingTarget
            snapshot.title = title
            snapshot.requestInFlight = requestInFlight
            snapshot.mutationsSupported = mutationsSupported
            return snapshot
        }

        mutating func resetTransientState() {
            creationTarget = nil
            editingTarget = nil
            title = ""
            requestInFlight = false
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
            state.mutationsSupported = isSupported
            guard isSupported == false else { return .none }
            state.resetTransientState()
            return Self.cancelEffects()
        case .creationRequested:
            return handleCreationRequested(state: &state)
        case let .editingRequested(pageNumber):
            return handleEditingRequested(pageNumber: pageNumber, state: &state)
        case let .titleChanged(title):
            state.title = title
            return .none
        case .cancelMutation:
            state.creationTarget = nil
            state.editingTarget = nil
            state.title = ""
            return .none
        case .confirmMutation:
            return handleConfirmMutation(state: &state)
        case .confirmDeletion:
            return handleConfirmDeletion(state: &state)
        case let .saved(target, title):
            state.requestInFlight = false
            return .send(.delegate(.saved(target: target, title: title)))
        case let .saveFailed(target, title, isEditing):
            return handleSaveFailed(target: target, title: title, isEditing: isEditing, state: &state)
        case let .deleted(target):
            state.requestInFlight = false
            return .send(.delegate(.deleted(target: target)))
        case let .deleteFailed(target, title):
            state.requestInFlight = false
            state.editingTarget = target
            state.title = title
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
        state.requestInFlight = false
        if isEditing {
            state.editingTarget = target
        } else {
            state.creationTarget = target
        }
        state.title = title
        let key = isEditing ? "archive.reader.chapter.edit.failed" : "archive.reader.chapter.add.failed"
        return .send(.delegate(.errorOccurred(String(localized: String.LocalizationValue(key)))))
    }

    func handleCreationRequested(state: inout State) -> Effect<Action> {
        guard state.canAddChapter,
              !state.requestInFlight,
              state.editingTarget == nil,
              let page = state.currentPage else {
            return .none
        }
        state.creationTarget = ChapterMutationTarget(
            readerArchiveId: state.archiveId,
            readerPageNumber: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        state.title = ""
        return .none
    }

    func handleEditingRequested(pageNumber: Int, state: inout State) -> Effect<Action> {
        guard state.editableChapterPages.contains(pageNumber),
              !state.requestInFlight,
              state.creationTarget == nil,
              let chapter = state.chapters.first(where: { $0.page == pageNumber }),
              let page = state.pages.first(where: { $0.pageNumber == pageNumber }) else {
            return .none
        }
        state.editingTarget = ChapterMutationTarget(
            readerArchiveId: state.archiveId,
            readerPageNumber: pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        state.title = chapter.name
        return .none
    }

    func handleConfirmMutation(state: inout State) -> Effect<Action> {
        let isEditing = state.editingTarget != nil
        guard let target = state.editingTarget ?? state.creationTarget else { return .none }
        let draft = state.title
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .none }
        state.creationTarget = nil
        state.editingTarget = nil
        state.title = ""
        state.requestInFlight = true
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
        guard let target = state.editingTarget else { return .none }
        let title = state.title
        state.editingTarget = nil
        state.title = ""
        state.requestInFlight = true
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
