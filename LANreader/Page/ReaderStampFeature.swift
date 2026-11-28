import ComposableArchitecture
import Foundation
import Logging

public struct StampCreationTarget: Equatable, Sendable {
    let sourceArchiveId: String
    let sourcePageNumber: Int
    let position: ArchiveStampPosition
}

public struct StampEditingTarget: Equatable, Sendable {
    let stampId: String
    let sourceArchiveId: String
    let sourcePageNumber: Int
}

public struct ReaderStampPage: Equatable, Sendable {
    public let sourceArchiveId: String
    public let sourcePageNumber: Int
    public let cached: Bool
    public let imageLoaded: Bool
    public let stampIds: Set<String>
}

extension ReaderStampPage {
    init(page: PageFeature.State, cached: Bool? = nil) {
        self.sourceArchiveId = page.sourceArchiveId
        self.sourcePageNumber = page.sourcePageNumber
        self.cached = cached ?? page.cached
        self.imageLoaded = page.imageLoaded
        self.stampIds = Set(page.stamps.compactMap(\.id))
    }
}

@Reducer public struct ReaderStampFeature: Sendable {
    private let logger = Logger(label: "ReaderStampFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        var creationTarget: StampCreationTarget?
        var comment = ""
        var editingTarget: StampEditingTarget?
        var editText = ""
        var requestInFlight = false
        var supported: Bool?

        public init() {}

        mutating func resetTransientState() {
            creationTarget = nil
            comment = ""
            editingTarget = nil
            editText = ""
            requestInFlight = false
        }
    }

    public enum Action: Equatable {
        case supportResolved(Bool?)
        case creationRequested(page: ReaderStampPage, position: ArchiveStampPosition)
        case commentChanged(String)
        case cancelCreation
        case confirmCreation
        case created(target: StampCreationTarget, stamp: ArchiveStamp, refreshedStamps: [ArchiveStamp]?)
        case creationFailed(target: StampCreationTarget, content: String)
        case editingRequested(page: ReaderStampPage, stamp: ArchiveStamp)
        case editTextChanged(String)
        case cancelEditing
        case confirmEditing
        case confirmDeletion
        case updated(target: StampEditingTarget, content: String)
        case updateFailed(target: StampEditingTarget, content: String)
        case deleted(target: StampEditingTarget)
        case deleteFailed(target: StampEditingTarget, content: String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case unsupportedServerResolved
            case created(target: StampCreationTarget, stamp: ArchiveStamp, refreshedStamps: [ArchiveStamp]?)
            case updated(target: StampEditingTarget, content: String)
            case deleted(target: StampEditingTarget)
            case errorOccurred(String)
        }
    }

    @Dependency(\.lanraragiService) var service

    public enum CancelId: Sendable {
        case creation
        case mutation
    }

    public static func cancelEffects<ParentAction>() -> Effect<ParentAction> {
        .merge(
            .cancel(id: CancelId.creation),
            .cancel(id: CancelId.mutation)
        )
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(state: &state, action: action)
        }
    }
}

private extension ReaderStampFeature {
    func reduce(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .supportResolved(isSupported):
            state.supported = isSupported
            guard isSupported == false else { return .none }
            state.resetTransientState()
            return .merge(
                Self.cancelEffects(),
                .send(.delegate(.unsupportedServerResolved))
            )
        case .creationRequested, .commentChanged, .cancelCreation, .confirmCreation,
             .created, .creationFailed:
            return reduceCreation(state: &state, action: action)
        case .editingRequested, .editTextChanged, .cancelEditing, .confirmEditing,
             .confirmDeletion, .updated, .updateFailed, .deleted, .deleteFailed:
            return reduceEditing(state: &state, action: action)
        case .delegate:
            return .none
        }
    }

    func reduceCreation(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .creationRequested(page, position):
            return handleCreationRequested(page: page, position: position, state: &state)
        case let .commentChanged(comment):
            state.comment = comment
            return .none
        case .cancelCreation:
            state.creationTarget = nil
            state.comment = ""
            return .none
        case .confirmCreation:
            return handleConfirmCreation(state: &state)
        case let .created(target, stamp, refreshedStamps):
            state.requestInFlight = false
            return .send(.delegate(.created(target: target, stamp: stamp, refreshedStamps: refreshedStamps)))
        case let .creationFailed(target, content):
            state.requestInFlight = false
            state.creationTarget = target
            state.comment = content
            return .send(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.add.failed"))))
        default:
            return .none
        }
    }

    func reduceEditing(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .editingRequested(page, stamp):
            return handleEditingRequested(page: page, stamp: stamp, state: &state)
        case let .editTextChanged(content):
            state.editText = content
            return .none
        case .cancelEditing:
            state.editingTarget = nil
            state.editText = ""
            return .none
        case .confirmEditing:
            return handleConfirmEditing(state: &state)
        case .confirmDeletion:
            return handleConfirmDeletion(state: &state)
        case let .updated(target, content):
            state.requestInFlight = false
            return .send(.delegate(.updated(target: target, content: content)))
        case let .updateFailed(target, content):
            state.requestInFlight = false
            state.editingTarget = target
            state.editText = content
            return .send(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.update.failed"))))
        case let .deleted(target):
            state.requestInFlight = false
            return .send(.delegate(.deleted(target: target)))
        case let .deleteFailed(target, content):
            state.requestInFlight = false
            state.editingTarget = target
            state.editText = content
            return .send(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.delete.failed"))))
        default:
            return .none
        }
    }

    func handleCreationRequested(
        page: ReaderStampPage,
        position: ArchiveStampPosition,
        state: inout State
    ) -> Effect<Action> {
        guard state.supported != false,
              !state.requestInFlight,
              state.editingTarget == nil,
              !page.cached,
              page.imageLoaded else {
            return .none
        }
        state.creationTarget = StampCreationTarget(
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber,
            position: position
        )
        state.comment = ""
        return .none
    }

    func handleConfirmCreation(state: inout State) -> Effect<Action> {
        guard let target = state.creationTarget else { return .none }
        let draft = state.comment
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .none }
        state.creationTarget = nil
        state.comment = ""
        state.requestInFlight = true
        return .run { send in
            await performStampCreation(target: target, draft: draft, content: content, send: send)
        }
        .cancellable(id: CancelId.creation, cancelInFlight: true)
    }

    func performStampCreation(
        target: StampCreationTarget,
        draft: String,
        content: String,
        send: Send<Action>
    ) async {
        let logContext = "archive=\(target.sourceArchiveId) page=\(target.sourcePageNumber)"
        do {
            let response = try await service.addStamp(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber,
                content: content,
                position: target.position.rawValue
            ).value
            guard response.success == 1 else {
                logger.warning("server rejected stamp creation. \(logContext)")
                await send(.creationFailed(target: target, content: draft))
                return
            }
            let stamp = ArchiveStamp(id: response.stampId, position: target.position.rawValue, content: content)
            let refreshedStamps = await fetchRefreshedStamps(target: target, logContext: logContext)
            await send(.created(target: target, stamp: stamp, refreshedStamps: refreshedStamps))
        } catch {
            logger.warning("failed to create stamp. \(logContext) \(error.localizedDescription)")
            await send(.creationFailed(target: target, content: draft))
        }
    }

    func fetchRefreshedStamps(target: StampCreationTarget, logContext: String) async -> [ArchiveStamp]? {
        do {
            return try await service.retrieveStamps(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber
            ).value.result
        } catch {
            logger.warning("failed to refresh stamps after creation. \(logContext) \(error.localizedDescription)")
            return nil
        }
    }

    func handleEditingRequested(
        page: ReaderStampPage,
        stamp: ArchiveStamp,
        state: inout State
    ) -> Effect<Action> {
        guard state.supported != false,
              !state.requestInFlight,
              state.creationTarget == nil,
              let stampId = stamp.id,
              !stampId.isEmpty,
              !page.cached,
              page.stampIds.contains(stampId) else {
            return .none
        }
        state.editingTarget = StampEditingTarget(
            stampId: stampId,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        state.editText = stamp.content
        return .none
    }

    func handleConfirmEditing(state: inout State) -> Effect<Action> {
        guard let target = state.editingTarget else { return .none }
        let draft = state.editText
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .none }
        state.editingTarget = nil
        state.editText = ""
        state.requestInFlight = true
        return .run { send in
            do {
                let response = try await service.updateStamp(id: target.stampId, content: content).value
                guard response.success == 1 else {
                    logger.warning("server rejected stamp update. stamp=\(target.stampId)")
                    await send(.updateFailed(target: target, content: draft))
                    return
                }
                await send(.updated(target: target, content: content))
            } catch {
                logger.warning("failed to update stamp. stamp=\(target.stampId) \(error.localizedDescription)")
                await send(.updateFailed(target: target, content: draft))
            }
        }
        .cancellable(id: CancelId.mutation, cancelInFlight: true)
    }

    func handleConfirmDeletion(state: inout State) -> Effect<Action> {
        guard let target = state.editingTarget else { return .none }
        let content = state.editText
        state.editingTarget = nil
        state.editText = ""
        state.requestInFlight = true
        return .run { send in
            do {
                let response = try await service.deleteStamp(id: target.stampId).value
                guard response.success == 1 else {
                    logger.warning("server rejected stamp deletion. stamp=\(target.stampId)")
                    await send(.deleteFailed(target: target, content: content))
                    return
                }
                await send(.deleted(target: target))
            } catch {
                logger.warning("failed to delete stamp. stamp=\(target.stampId) \(error.localizedDescription)")
                await send(.deleteFailed(target: target, content: content))
            }
        }
        .cancellable(id: CancelId.mutation, cancelInFlight: true)
    }
}
