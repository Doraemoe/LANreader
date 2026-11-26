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
        let context = ReaderChapterContext(
            archiveId: tankId,
            pages: [ReaderChapterPage(pageNumber: 8, sourceArchiveId: "source", sourcePageNumber: 4)]
        )
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.creationRequested) {
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
        let context = ReaderChapterContext(
            archiveId: "archive",
            pages: makeChapterPages(count: 4),
            currentPageIndex: 2
        )
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 3,
            sourceArchiveId: "archive",
            sourcePageNumber: 3
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.creationRequested) {
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
        let chapter = ArchiveChapter(name: "Original", page: 8)
        stubAddArchiveChapter(archiveId: "source", page: 4, title: "Updated")
        let context = ReaderChapterContext(
            archiveId: tankId,
            pages: [ReaderChapterPage(pageNumber: 8, sourceArchiveId: "source", sourcePageNumber: 4)],
            chapters: [chapter],
            automaticChapterPages: []
        )
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.editingRequested(chapter.page)) {
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
        let chapter = ArchiveChapter(name: "Original", page: 4)
        stubAddArchiveChapter(archiveId: "archive", page: 4, title: "Updated", success: 0)
        let context = ReaderChapterContext(
            archiveId: "archive",
            pages: [ReaderChapterPage(pageNumber: 4, sourceArchiveId: "archive", sourcePageNumber: 4)],
            chapters: [chapter]
        )
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 4,
            sourceArchiveId: "archive",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.editingRequested(chapter.page)) {
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
        let chapter = ArchiveChapter(name: "Delete me", page: 8)
        stubDeleteArchiveChapter(archiveId: "source", page: 4)
        let context = ReaderChapterContext(
            archiveId: tankId,
            pages: [ReaderChapterPage(pageNumber: 8, sourceArchiveId: "source", sourcePageNumber: 4)],
            chapters: [chapter],
            automaticChapterPages: []
        )
        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 8,
            sourceArchiveId: "source",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.editingRequested(chapter.page)) {
            $0.editingTarget = target
            $0.title = chapter.name
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
        let chapter = ArchiveChapter(name: "Keep me", page: 4)
        stubDeleteArchiveChapter(archiveId: "archive", page: 4, success: 0)
        let context = ReaderChapterContext(
            archiveId: "archive",
            pages: [ReaderChapterPage(pageNumber: 4, sourceArchiveId: "archive", sourcePageNumber: 4)],
            chapters: [chapter]
        )
        let target = ChapterMutationTarget(
            readerArchiveId: "archive",
            readerPageNumber: 4,
            sourceArchiveId: "archive",
            sourcePageNumber: 4
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.editingRequested(chapter.page)) {
            $0.editingTarget = target
            $0.title = chapter.name
        }
        await store.send(.confirmDeletion) {
            $0.editingTarget = nil
            $0.title = ""
            $0.requestInFlight = true
        }
        await store.receive(.deleteFailed(target: target, title: chapter.name)) {
            $0.requestInFlight = false
            $0.editingTarget = target
            $0.title = chapter.name
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.chapter.delete.failed"))))
    }

    @MainActor
    func testAutomaticTankoubonChapterCannotBeEdited() async {
        let tankId = "TANK_test"
        let manualFirstPage = ArchiveChapter(name: "Manual", page: 1)
        let automaticFirstPage = ArchiveChapter(name: "Source 2", page: 3)
        let context = ReaderChapterContext(
            archiveId: tankId,
            pages: [
                ReaderChapterPage(pageNumber: 1, sourceArchiveId: "source-1", sourcePageNumber: 1),
                ReaderChapterPage(pageNumber: 3, sourceArchiveId: "source-2", sourcePageNumber: 1)
            ],
            chapters: [manualFirstPage, automaticFirstPage],
            automaticChapterPages: [3]
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        XCTAssertEqual(store.state.editableChapterPages, [1])
        await store.send(.editingRequested(automaticFirstPage.page))

        let target = ChapterMutationTarget(
            readerArchiveId: tankId,
            readerPageNumber: 1,
            sourceArchiveId: "source-1",
            sourcePageNumber: 1
        )
        await store.send(.editingRequested(manualFirstPage.page)) {
            $0.editingTarget = target
            $0.title = "Manual"
        }
    }

    @MainActor
    func testUnsupportedServerKeepsChaptersReadOnlyWhileAllowingSelection() async {
        let chapter = ArchiveChapter(name: "Opening", page: 1)
        let context = ReaderChapterContext(
            archiveId: "archive",
            pages: makeChapterPages(count: 2),
            chapters: [chapter]
        )
        var stored = ReaderChapterState()
        stored.mutationsSupported = false
        let store = makeChapterTestStore(
            initialState: ReaderChapterFeature.State(context: context, stored: stored)
        )

        XCTAssertFalse(store.state.canAddChapter)
        XCTAssertTrue(store.state.editableChapterPages.isEmpty)

        await store.send(.creationRequested)
        await store.send(.editingRequested(chapter.page))
        await store.send(.selected(chapter.page))
        await store.receive(.delegate(.jumpRequested(0)))
    }

    @MainActor
    func testChapterSelectionMapsReaderPageNumberAcrossSplitPages() async {
        let pages = [
            ReaderChapterPage(pageNumber: 1, sourceArchiveId: "archive", sourcePageNumber: 1),
            ReaderChapterPage(pageNumber: 2, sourceArchiveId: "archive", sourcePageNumber: 2),
            ReaderChapterPage(pageNumber: 2, sourceArchiveId: "archive", sourcePageNumber: 2),
            ReaderChapterPage(pageNumber: 3, sourceArchiveId: "archive", sourcePageNumber: 3)
        ]
        let context = ReaderChapterContext(
            archiveId: "archive",
            pages: pages,
            chapters: [ArchiveChapter(name: "Third", page: 3)]
        )
        let store = makeChapterTestStore(initialState: ReaderChapterFeature.State(context: context))

        await store.send(.selected(3))
        await store.receive(.delegate(.jumpRequested(3)))
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

private func makeChapterPages(
    count: Int,
    archiveId: String = "archive"
) -> [ReaderChapterPage] {
    (1...count).map {
        ReaderChapterPage(pageNumber: $0, sourceArchiveId: archiveId, sourcePageNumber: $0)
    }
}

@MainActor
private func makeChapterTestStore(
    initialState: @autoclosure () -> ReaderChapterFeature.State
) -> TestStoreOf<ReaderChapterFeature> {
    let store = TestStore(initialState: initialState()) {
        ReaderChapterFeature()
    }
    store.timeout = .seconds(5)
    return store
}

private func stubAddArchiveChapter(archiveId: String, page: Int, title: String, success: Int = 1) {
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
