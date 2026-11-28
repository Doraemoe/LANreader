import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ReaderChapterTests: LANreaderTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    @MainActor
    func testAddChapterUsesCurrentSourcePageAndEmitsSavedDelegate() async throws {
        try await configureTestServer()
        let tankId = "TANK_test"
        stubAddArchiveChapter(archiveId: "source", page: 4, title: "New chapter")
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore()

        await store.send(.creationRequested(target: target)) {
            $0.creationTarget = target
        }
        await store.send(.titleChanged("  New chapter\n")) {
            $0.title = "  New chapter\n"
        }
        await store.send(.confirmMutation) {
            $0.creationTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.saved(target: target, title: "New chapter")) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.saved(target: target, title: "New chapter")))
    }

    @MainActor
    func testFailedChapterAddRestoresTheDraft() async throws {
        try await configureTestServer()
        stubAddArchiveChapter(archiveId: "archive", page: 3, title: "New chapter", success: 0)
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 3,
            sourceArchiveId: "archive",
            sourcePageNumber: 3
        )
        let store = makeChapterTestStore()

        await store.send(.creationRequested(target: target)) {
            $0.creationTarget = target
        }
        await store.send(.titleChanged("New chapter")) {
            $0.title = "New chapter"
        }
        await store.send(.confirmMutation) {
            $0.creationTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.saveFailed(target: target, title: "New chapter", isEditing: false)) {
            $0.requestInFlight = false
            $0.creationTarget = target
            $0.title = "New chapter"
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.chapter.add.failed"))))
    }

    @MainActor
    func testEditChapterUsesOriginalSourcePageAndEmitsSavedDelegate() async throws {
        try await configureTestServer()
        let tankId = "TANK_test"
        stubAddArchiveChapter(archiveId: "source", page: 4, title: "Updated")
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore()

        await store.send(.editingRequested(target: target, title: "Original")) {
            $0.editingTarget = target
            $0.title = "Original"
        }
        await store.send(.titleChanged("  Updated\n")) {
            $0.title = "  Updated\n"
        }
        await store.send(.confirmMutation) {
            $0.editingTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.saved(target: target, title: "Updated")) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.saved(target: target, title: "Updated")))
    }

    @MainActor
    func testEditChapterFailureRestoresDraft() async throws {
        try await configureTestServer()
        stubAddArchiveChapter(archiveId: "archive", page: 4, title: "Updated", success: 0)
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 4,
            sourceArchiveId: "archive",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore()

        await store.send(.editingRequested(target: target, title: "Original")) {
            $0.editingTarget = target
            $0.title = "Original"
        }
        await store.send(.titleChanged("  Updated\n")) {
            $0.title = "  Updated\n"
        }
        await store.send(.confirmMutation) {
            $0.editingTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.saveFailed(target: target, title: "  Updated\n", isEditing: true)) {
            $0.requestInFlight = false
            $0.editingTarget = target
            $0.title = "  Updated\n"
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.chapter.edit.failed"))))
    }

    @MainActor
    func testDeleteChapterUsesOriginalSourcePageAndEmitsDeletedDelegate() async throws {
        try await configureTestServer()
        let tankId = "TANK_test"
        stubDeleteArchiveChapter(archiveId: "source", page: 4)
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore()

        await store.send(.editingRequested(target: target, title: "Delete me")) {
            $0.editingTarget = target
            $0.title = "Delete me"
        }
        await store.send(.confirmDeletion) {
            $0.editingTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.deleted(target: target)) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.deleted(target: target)))
    }

    @MainActor
    func testDeleteChapterFailureRestoresEdit() async throws {
        try await configureTestServer()
        stubDeleteArchiveChapter(archiveId: "archive", page: 4, success: 0)
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 4,
            sourceArchiveId: "archive",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore()

        await store.send(.editingRequested(target: target, title: "Keep me")) {
            $0.editingTarget = target
            $0.title = "Keep me"
        }
        await store.send(.confirmDeletion) {
            $0.editingTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.deleteFailed(target: target, title: "Keep me")) {
            $0.requestInFlight = false
            $0.editingTarget = target
            $0.title = "Keep me"
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.chapter.delete.failed"))))
    }

    @MainActor
    func testAutomaticTankoubonChapterIsExcludedFromEditablePages() async {
        let tankId = "TANK_test"
        let manualFirstPage = ArchiveChapter(name: "Manual", page: 1)
        let automaticFirstPage = ArchiveChapter(name: "Source 2", page: 3)
        let editablePages = ReaderChapterFeature.editableChapterPages(
            archiveId: tankId,
            cached: false,
            mutationsSupported: true,
            chapters: [manualFirstPage, automaticFirstPage],
            automaticChapterPages: [3]
        )
        XCTAssertEqual(editablePages, [1])

        let manualTarget = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 1,
            sourceArchiveId: "source-1",
            sourcePageNumber: 1
        )
        var busyState = ReaderChapterFeature.State()
        busyState.requestInFlight = true
        let busyStore = makeChapterTestStore(initialState: busyState)
        await busyStore.send(.editingRequested(target: manualTarget, title: manualFirstPage.name))

        let store = makeChapterTestStore()
        await store.send(.editingRequested(target: manualTarget, title: manualFirstPage.name)) {
            $0.editingTarget = manualTarget
            $0.title = "Manual"
        }
        await store.send(.creationRequested(target: manualTarget))
    }

    @MainActor
    func testUnsupportedServerRejectsChapterMutations() async {
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 1,
            sourceArchiveId: "archive",
            sourcePageNumber: 1
        )

        var unsupportedState = ReaderChapterFeature.State()
        unsupportedState.mutationsSupported = false
        let unsupportedStore = makeChapterTestStore(initialState: unsupportedState)

        await unsupportedStore.send(.creationRequested(target: target))
        await unsupportedStore.send(.editingRequested(target: target, title: "Opening"))
    }

    @MainActor
    func testCancellingChapterSaveDoesNotEmitFailure() async throws {
        try await configureTestServer()
        stubAddArchiveChapter(archiveId: "archive", page: 3, title: "Chapter", requestDelay: 0.5)
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 3,
            sourceArchiveId: "archive",
            sourcePageNumber: 3
        )
        var initialState = ReaderChapterFeature.State()
        initialState.creationTarget = target
        initialState.title = "Chapter"
        let store = makeChapterTestStore(initialState: initialState)

        await store.send(.confirmMutation) {
            $0.creationTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await Task.yield()
        await store.send(.mutationSupportResolved(false)) {
            $0.mutationsSupported = false
            $0.requestInFlight = false
        }
        await store.finish()
    }

    func testChapterMutationHelpersSaveSortAndRestoreDefaultTankoubonChapter() {
        let saved = ReaderChapterFeature.chaptersBySaving(
            "Updated Ch 1",
            at: 1,
            in: [ArchiveChapter(name: "Ch 3", page: 3), ArchiveChapter(name: "Ch 1", page: 1)]
        )
        XCTAssertEqual(saved, [ArchiveChapter(name: "Updated Ch 1", page: 1), ArchiveChapter(name: "Ch 3", page: 3)])

        let deleted = ReaderChapterFeature.applyChapterDeletion(
            at: 3,
            chapters: saved,
            defaultChapters: [ArchiveChapter(name: "Source 2", page: 3)]
        )
        XCTAssertEqual(
            deleted.chapters,
            [ArchiveChapter(name: "Updated Ch 1", page: 1), ArchiveChapter(name: "Source 2", page: 3)]
        )
        XCTAssertEqual(deleted.restoredDefaultPage, 3)

        XCTAssertTrue(
            ReaderChapterFeature.editableChapterPages(
                archiveId: "TANK_test",
                cached: false,
                mutationsSupported: true,
                chapters: saved,
                automaticChapterPages: nil
            ).isEmpty
        )
    }
}

@MainActor
private func makeChapterTestStore(
    initialState: @autoclosure () -> ReaderChapterFeature.State = ReaderChapterFeature.State()
) -> TestStoreOf<ReaderChapterFeature> {
    let store = TestStore(initialState: initialState()) {
        ReaderChapterFeature()
    }
    store.timeout = .seconds(5)
    return store
}

private func stubAddArchiveChapter(
    archiveId: String,
    page: Int,
    title: String,
    success: Int = 1,
    requestDelay: TimeInterval = 0
) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/toc")
            && containsQueryParams(["page": "\(page)", "title": title])
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("{\"operation\":\"update_toc\",\"success\":\(success)}".utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        .requestTime(requestDelay, responseTime: 0)
    }
}

private func stubDeleteArchiveChapter(archiveId: String, page: Int, success: Int = 1) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/toc")
            && containsQueryParams(["page": "\(page)"])
            && isMethodDELETE()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("{\"operation\":\"remove_toc\",\"success\":\(success)}".utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}
