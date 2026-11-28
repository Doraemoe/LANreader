import ComposableArchitecture
import Foundation
import Logging

public struct ChapterMutationTarget: Equatable, Sendable {
    let readerArchiveId: String
    let readerPageNumber: Int
    let sourceArchiveId: String
    let sourcePageNumber: Int
}

@Reducer public struct ReaderChapterFeature: Sendable {
    private let logger = Logger(label: "ReaderChapterFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
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

    public enum Action: Equatable {
        case mutationSupportResolved(Bool?)
        case creationRequested(target: ChapterMutationTarget, cached: Bool)
        case editingRequested(target: ChapterMutationTarget, title: String, editable: Bool)
        case titleChanged(String)
        case cancelMutation
        case confirmMutation
        case confirmDeletion
        case saved(target: ChapterMutationTarget, title: String)
        case saveFailed(target: ChapterMutationTarget, title: String, isEditing: Bool)
        case deleted(target: ChapterMutationTarget)
        case deleteFailed(target: ChapterMutationTarget, title: String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
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
        case let .creationRequested(target, cached):
            return handleCreationRequested(target: target, cached: cached, state: &state)
        case let .editingRequested(target, title, editable):
            return handleEditingRequested(target: target, title: title, editable: editable, state: &state)
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
        let message = isEditing
            ? String(localized: "archive.reader.chapter.edit.failed")
            : String(localized: "archive.reader.chapter.add.failed")
        return .send(.delegate(.errorOccurred(message)))
    }

    func handleCreationRequested(
        target: ChapterMutationTarget,
        cached: Bool,
        state: inout State
    ) -> Effect<Action> {
        guard !cached,
              state.mutationsSupported != false,
              !state.requestInFlight,
              state.editingTarget == nil else {
            return .none
        }
        state.creationTarget = target
        state.title = ""
        return .none
    }

    func handleEditingRequested(
        target: ChapterMutationTarget,
        title: String,
        editable: Bool,
        state: inout State
    ) -> Effect<Action> {
        guard editable,
              state.mutationsSupported != false,
              !state.requestInFlight,
              state.creationTarget == nil else {
            return .none
        }
        state.editingTarget = target
        state.title = title
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
            if error is CancellationError || Task.isCancelled { return }
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
            if error is CancellationError || Task.isCancelled { return }
            let source = "\(target.sourceArchiveId):\(target.sourcePageNumber)"
            logger.warning("failed to delete chapter. source=\(source) \(error.localizedDescription)")
            await send(.deleteFailed(target: target, title: title))
        }
    }
}
