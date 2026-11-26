import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ReaderStampPositioningTests: LANreaderTestCase {
    func testStampPositionParsesNormalizedCoordinates() throws {
        let position = try XCTUnwrap(ArchiveStampPosition(rawValue: " 12.5,100 "))
        XCTAssertEqual(position.horizontalPercentage, 12.5)
        XCTAssertEqual(position.verticalPercentage, 100)
        XCTAssertNotNil(ArchiveStampPosition(rawValue: "0,0"))
        XCTAssertNil(ArchiveStampPosition(rawValue: "-1,50"))
        XCTAssertNil(ArchiveStampPosition(rawValue: "50,101"))
        XCTAssertNil(ArchiveStampPosition(rawValue: "not-a-position"))
    }

    func testStampPositioningMapsStampsOntoSplitPageHalves() {
        let leftPosition = ArchiveStampPosition(rawValue: "25,30")!
        let rightPosition = ArchiveStampPosition(rawValue: "75,30")!

        XCTAssertEqual(
            StampOverlayPositioning.displayedPosition(leftPosition, pageMode: .left),
            ArchiveStampPosition(rawValue: "50,30")
        )
        XCTAssertNil(StampOverlayPositioning.displayedPosition(rightPosition, pageMode: .left))
        XCTAssertEqual(
            StampOverlayPositioning.displayedPosition(rightPosition, pageMode: .right),
            ArchiveStampPosition(rawValue: "50,30")
        )
        XCTAssertNil(StampOverlayPositioning.displayedPosition(leftPosition, pageMode: .right))
    }

    func testStampPositioningMapsLongPressToSourceCoordinates() {
        let imageSize = CGSize(width: 1_000, height: 500)
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let point = CGPoint(x: 100, y: 150)

        XCTAssertEqual(
            StampOverlayPositioning.sourcePosition(
                at: point,
                pageMode: .normal,
                imageSize: imageSize,
                in: bounds
            ),
            ArchiveStampPosition(rawValue: "25,25")
        )
        XCTAssertNil(
            StampOverlayPositioning.sourcePosition(
                at: CGPoint(x: 100, y: 50),
                pageMode: .normal,
                imageSize: imageSize,
                in: bounds
            )
        )
    }

    func testStampPositioningMapsSplitLongPressToSourceCoordinates() {
        let imageSize = CGSize(width: 1_000, height: 500)
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let point = CGPoint(x: 100, y: 150)

        XCTAssertEqual(
            StampOverlayPositioning.sourcePosition(
                at: point,
                pageMode: .left,
                imageSize: imageSize,
                in: bounds
            ),
            ArchiveStampPosition(rawValue: "12.5,25")
        )
        XCTAssertEqual(
            StampOverlayPositioning.sourcePosition(
                at: point,
                pageMode: .right,
                imageSize: imageSize,
                in: bounds
            ),
            ArchiveStampPosition(rawValue: "62.5,25")
        )
    }
}

final class ReaderStampTests: LANreaderTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    @MainActor
    func testCachedPageDoesNotLoadStampsFromServer() async {
        let store = TestStore(
            initialState: PageFeature.State(
                archiveId: "archive",
                pageId: "1",
                pageNumber: 1,
                cached: true
            )
        ) {
            PageFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.loadStamps)
    }

    @MainActor
    func testPageLoadsStampsUsingSourceArchiveAndPage() async throws {
        try await configureTestServer()
        let stamp = ArchiveStamp(id: "stamp", position: "12,34", content: "Comment")
        stubArchiveStamps(archiveId: "source", page: 4)
        let store = TestStore(
            initialState: PageFeature.State(
                archiveId: "tank",
                pageId: "page",
                pageNumber: 8,
                sourceArchiveId: "source",
                sourcePageNumber: 4
            )
        ) {
            PageFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.loadStamps) {
            $0.stampsLoading = true
        }
        await store.receive(.stampsLoaded([stamp])) {
            $0.stamps = [stamp]
            $0.stampsLoading = false
            $0.stampsLoaded = true
        }
    }

    @MainActor
    func testPageRetriesStampsAfterTransientFailure() async throws {
        try await configureTestServer()
        stubArchiveStampsFailure(archiveId: "archive", page: 1, statusCode: 500)
        let store = TestStore(
            initialState: PageFeature.State(
                archiveId: "archive",
                pageId: "1",
                pageNumber: 1
            )
        ) {
            PageFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.loadStamps) {
            $0.stampsLoading = true
        }
        await store.receive(.stampsLoadFailed(endpointUnavailable: false)) {
            $0.stampsLoading = false
        }

        stubArchiveStamps(archiveId: "archive", page: 1)
        await store.send(.loadStamps) {
            $0.stampsLoading = true
        }
        await store.receive(.stampsLoaded([
            ArchiveStamp(id: "stamp", position: "12,34", content: "Comment")
        ])) {
            $0.stamps = [ArchiveStamp(id: "stamp", position: "12,34", content: "Comment")]
            $0.stampsLoading = false
            $0.stampsLoaded = true
        }
    }

    @MainActor
    func testPageDoesNotRetryUnavailableStampsEndpoint() async throws {
        try await configureTestServer()
        stubArchiveStampsFailure(archiveId: "archive", page: 1, statusCode: 404)
        let store = TestStore(
            initialState: PageFeature.State(
                archiveId: "archive",
                pageId: "1",
                pageNumber: 1
            )
        ) {
            PageFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.loadStamps) {
            $0.stampsLoading = true
        }
        await store.receive(.stampsLoadFailed(endpointUnavailable: true)) {
            $0.stampsLoading = false
            $0.stampsLoaded = true
        }
        await store.send(.loadStamps)
    }

    @MainActor
    func testCreateStampUsesSourcePageAndEmitsCreatedDelegate() async throws {
        try await configureTestServer()
        let position = ArchiveStampPosition(rawValue: "25,30")!
        let stamp = ArchiveStamp(id: "created-stamp", position: position.rawValue, content: "New comment")
        stubAddArchiveStamp(archiveId: "source", page: 4, content: "New comment", position: "25.0,30.0")
        stubArchiveStamps(archiveId: "source", page: 4, stamps: [stamp])

        let page = makeStampPage(id: "page-left", sourceArchiveId: "source", sourcePageNumber: 4)
        let target = StampCreationTarget(sourceArchiveId: "source", sourcePageNumber: 4, position: position)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.creationRequested(pageId: page.id, position: position)) {
            $0.creationTarget = target
        }
        await store.send(.commentChanged("  New comment\n")) {
            $0.comment = "  New comment\n"
        }
        await store.send(.confirmCreation) {
            $0.creationTarget = nil
            $0.comment = ""
            $0.requestInFlight = true
        }
        await store.receive(.created(target: target, stamp: stamp, refreshedStamps: [stamp])) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.created(target: target, stamp: stamp, refreshedStamps: [stamp])))
    }

    @MainActor
    func testCreatedStampEmitsNilRefreshedStampsWhenRefreshFails() async throws {
        try await configureTestServer()
        let position = ArchiveStampPosition(rawValue: "25,30")!
        let stamp = ArchiveStamp(id: "created-stamp", position: position.rawValue, content: "New comment")
        stubAddArchiveStamp(archiveId: "archive", page: 1, content: "New comment", position: "25.0,30.0")
        stubArchiveStampsFailure(archiveId: "archive", page: 1, statusCode: 500)

        let page = makeStampPage()
        let target = StampCreationTarget(sourceArchiveId: "archive", sourcePageNumber: 1, position: position)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.creationRequested(pageId: page.id, position: position)) {
            $0.creationTarget = target
        }
        await store.send(.commentChanged("New comment")) {
            $0.comment = "New comment"
        }
        await store.send(.confirmCreation) {
            $0.creationTarget = nil
            $0.comment = ""
            $0.requestInFlight = true
        }
        await store.receive(.created(target: target, stamp: stamp, refreshedStamps: nil)) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.created(target: target, stamp: stamp, refreshedStamps: nil)))
    }

    @MainActor
    func testEditStampUpdatesExistingStampAndEmitsUpdatedDelegate() async throws {
        try await configureTestServer()
        let stamp = ArchiveStamp(id: "stamp", position: "25,30", content: "Original text")
        stubUpdateArchiveStamp(stampId: "stamp", content: "Updated text")
        let page = makeStampPage(stampIds: ["stamp"])
        let target = StampEditingTarget(stampId: "stamp", sourceArchiveId: "archive", sourcePageNumber: 1)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.editingRequested(pageId: page.id, stamp: stamp)) {
            $0.editingTarget = target
            $0.editText = "Original text"
        }
        await store.send(.editTextChanged("  Updated text\n")) {
            $0.editText = "  Updated text\n"
        }
        await store.send(.confirmEditing) {
            $0.editingTarget = nil
            $0.editText = ""
            $0.requestInFlight = true
        }
        await store.receive(.updated(target: target, content: "Updated text")) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.updated(target: target, content: "Updated text")))
    }

    @MainActor
    func testDeleteStampRemovesExistingStampAndEmitsDeletedDelegate() async throws {
        try await configureTestServer()
        let stamp = ArchiveStamp(id: "stamp", position: "25,30", content: "Delete me")
        stubDeleteArchiveStamp(stampId: "stamp")
        let page = makeStampPage(stampIds: ["stamp"])
        let target = StampEditingTarget(stampId: "stamp", sourceArchiveId: "archive", sourcePageNumber: 1)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.editingRequested(pageId: page.id, stamp: stamp)) {
            $0.editingTarget = target
            $0.editText = "Delete me"
        }
        await store.send(.confirmDeletion) {
            $0.editingTarget = nil
            $0.editText = ""
            $0.requestInFlight = true
        }
        await store.receive(.deleted(target: target)) {
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.deleted(target: target)))
    }

    @MainActor
    func testCreateStampFailureRestoresDraft() async throws {
        try await configureTestServer()
        let position = ArchiveStampPosition(rawValue: "25,30")!
        stubAddArchiveStamp(
            archiveId: "archive",
            page: 1,
            content: "Keep this text",
            position: position.rawValue,
            success: 0
        )
        let page = makeStampPage()
        let target = StampCreationTarget(sourceArchiveId: "archive", sourcePageNumber: 1, position: position)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.creationRequested(pageId: page.id, position: position)) {
            $0.creationTarget = target
        }
        await store.send(.commentChanged("  Keep this text\n")) {
            $0.comment = "  Keep this text\n"
        }
        await store.send(.confirmCreation) {
            $0.creationTarget = nil
            $0.comment = ""
            $0.requestInFlight = true
        }
        await store.receive(.creationFailed(target: target, content: "  Keep this text\n")) {
            $0.creationTarget = target
            $0.comment = "  Keep this text\n"
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.add.failed"))))
    }

    @MainActor
    func testEditStampFailureRestoresDraft() async throws {
        try await configureTestServer()
        let stamp = ArchiveStamp(id: "stamp", position: "25,30", content: "Original text")
        stubUpdateArchiveStamp(stampId: "stamp", content: "Keep edit", success: 0)
        let page = makeStampPage(stampIds: ["stamp"])
        let target = StampEditingTarget(stampId: "stamp", sourceArchiveId: "archive", sourcePageNumber: 1)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.editingRequested(pageId: page.id, stamp: stamp)) {
            $0.editingTarget = target
            $0.editText = "Original text"
        }
        await store.send(.editTextChanged("  Keep edit\n")) {
            $0.editText = "  Keep edit\n"
        }
        await store.send(.confirmEditing) {
            $0.editingTarget = nil
            $0.editText = ""
            $0.requestInFlight = true
        }
        await store.receive(.updateFailed(target: target, content: "  Keep edit\n")) {
            $0.editingTarget = target
            $0.editText = "  Keep edit\n"
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.update.failed"))))
    }

    @MainActor
    func testDeleteStampFailureRestoresEditor() async throws {
        try await configureTestServer()
        let stamp = ArchiveStamp(id: "stamp", position: "25,30", content: "Keep stamp")
        stubDeleteArchiveStamp(stampId: "stamp", success: 0)
        let page = makeStampPage(stampIds: ["stamp"])
        let target = StampEditingTarget(stampId: "stamp", sourceArchiveId: "archive", sourcePageNumber: 1)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(pages: [page]))

        await store.send(.editingRequested(pageId: page.id, stamp: stamp)) {
            $0.editingTarget = target
            $0.editText = "Keep stamp"
        }
        await store.send(.confirmDeletion) {
            $0.editingTarget = nil
            $0.editText = ""
            $0.requestInFlight = true
        }
        await store.receive(.deleteFailed(target: target, content: "Keep stamp")) {
            $0.editingTarget = target
            $0.editText = "Keep stamp"
            $0.requestInFlight = false
        }
        await store.receive(.delegate(.errorOccurred(String(localized: "archive.reader.stamp.delete.failed"))))
    }

    @MainActor
    func testCachedReaderDoesNotOfferStampCreation() async {
        let page = makeStampPage(cached: true)
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(cached: true, pages: [page]))

        await store.send(.creationRequested(
            pageId: page.id,
            position: ArchiveStampPosition(rawValue: "50,50")!
        ))
    }

    @MainActor
    func testCachedReaderDoesNotOfferStampEditing() async {
        let stamp = ArchiveStamp(id: "stamp", position: "50,50", content: "Offline")
        let page = makeStampPage(cached: true, stampIds: ["stamp"])
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(cached: true, pages: [page]))

        await store.send(.editingRequested(pageId: page.id, stamp: stamp))
    }

    @MainActor
    func testUnsupportedServerResetsDraftAndEmitsDelegate() async {
        var stored = ReaderStampState()
        stored.comment = "draft"
        stored.editText = "edit"
        let store = makeStampTestStore(initialState: ReaderStampFeature.State(stored: stored))

        await store.send(.supportResolved(false)) {
            $0.supported = false
            $0.comment = ""
            $0.editText = ""
        }
        await store.receive(.delegate(.unsupportedServerResolved))
    }
}

private func makeStampPage(
    id: String = "1",
    sourceArchiveId: String = "archive",
    sourcePageNumber: Int = 1,
    cached: Bool = false,
    imageLoaded: Bool = true,
    stampIds: Set<String> = []
) -> ReaderStampPage {
    ReaderStampPage(
        id: id,
        sourceArchiveId: sourceArchiveId,
        sourcePageNumber: sourcePageNumber,
        cached: cached,
        imageLoaded: imageLoaded,
        stampIds: stampIds
    )
}

@MainActor
private func makeStampTestStore(
    initialState: @autoclosure () -> ReaderStampFeature.State
) -> TestStoreOf<ReaderStampFeature> {
    let store = TestStore(initialState: initialState()) {
        ReaderStampFeature()
    }
    store.timeout = .seconds(5)
    return store
}

private func stubArchiveStamps(
    archiveId: String,
    page: Int,
    stamps: [ArchiveStamp] = [
        ArchiveStamp(id: "stamp", position: "12,34", content: "Comment")
    ]
) {
    let response = [
        "result": stamps.map { stamp in
            [
                "id": stamp.id as Any,
                "position": stamp.position,
                "content": stamp.content
            ]
        }
    ]
    let responseData = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()

    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/stamps/\(page)")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: responseData,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubArchiveStampsFailure(archiveId: String, page: Int, statusCode: Int32) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/stamps/\(page)")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("{\"error\":\"stamps unavailable\"}".utf8),
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubAddArchiveStamp(
    archiveId: String,
    page: Int,
    content: String,
    position: String,
    success: Int = 1
) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/stamps/\(page)")
            && containsQueryParams([
                "content": content,
                "position": position
            ])
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "operation": "add_stamp",
              "stamp_id": "created-stamp",
              "success": \(success)
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubUpdateArchiveStamp(stampId: String, content: String, success: Int = 1) {
    stub(condition: isHost("localhost")
            && isPath("/api/stamps/\(stampId)")
            && containsQueryParams(["content": content])
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "operation": "update_stamp",
              "success": \(success)
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubDeleteArchiveStamp(stampId: String, success: Int = 1) {
    stub(condition: isHost("localhost")
            && isPath("/api/stamps/\(stampId)")
            && isMethodDELETE()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "operation": "delete_stamp",
              "success": \(success)
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}
