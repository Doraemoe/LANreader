import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
import UIKit
@testable import LANreader

final class ArchiveDetailsTagParserTests: LANreaderTestCase {
    func testTagGroupsUseRequestedNamespaceOrder() {
        let groups = ArchiveDetailsTagParser.tagGroups(
            from: "series:z,source:example.com,character:alice,date_added:1700000000,misc,artist:bob,group:a"
        )

        XCTAssertEqual(
            groups.map(\.id),
            ["artist", "character", "group", "other", "series", "source", "date_added"]
        )
    }

    func testTagGroupsTrimTagsAndDisplayNamespaceValues() {
        let groups = ArchiveDetailsTagParser.tagGroups(
            from: " artist: Bob , plain tag , artist:Alice , source: example.com "
        )

        let artistTags = groups.first { $0.id == "artist" }?.tags
        XCTAssertEqual(artistTags?.map(\.displayText), ["Alice", "Bob"])
        XCTAssertEqual(artistTags?.map(\.raw), ["artist:Alice", "artist: Bob"])

        let otherTags = groups.first { $0.id == "other" }?.tags
        XCTAssertEqual(otherTags?.map(\.displayText), ["plain tag"])
        XCTAssertEqual(otherTags?.map(\.raw), ["plain tag"])

        let sourceTags = groups.first { $0.id == "source" }?.tags
        XCTAssertEqual(sourceTags?.map(\.displayText), ["example.com"])
        XCTAssertEqual(sourceTags?.map(\.raw), ["source: example.com"])
    }

    func testTokensSplitOnCommasAndNewlinesAndDropBlanks() {
        XCTAssertEqual(
            ArchiveDetailsTagParser.tokens(from: " artist: Bob ,,\n plain tag \n source:example.com,"),
            ["artist: Bob", "plain tag", "source:example.com"]
        )
        XCTAssertEqual(ArchiveDetailsTagParser.tokens(from: " , \n "), [])
    }

    func testNamespaceKeyMatchesGroupNamespace() {
        XCTAssertEqual(ArchiveDetailsTagParser.namespaceKey(for: " Artist: Bob "), "artist")
        XCTAssertEqual(ArchiveDetailsTagParser.namespaceKey(for: "plain tag"), "other")
        XCTAssertEqual(ArchiveDetailsTagParser.namespaceKey(for: ":no namespace"), "other")
    }

    @MainActor
    func testArchiveDetailsLoadLocalFieldsUsesTankoubonMetadataTags() async {
        let archive = Shared(value: makeDetailsArchive(
            id: "TANK_1783084742",
            name: "Merged search title",
            tags: "artist:merged"
        ))
        let metadata = TankoubonDetailsMetadata(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank",
            includedArchiveTags: "artist:first,series:one"
        )
        let state = ArchiveDetailsFeature.State(
            archive: archive,
            tankoubonMetadata: metadata
        )
        XCTAssertEqual(state.title, "Tank title")
        XCTAssertEqual(state.editableTags, "artist:tank")
        XCTAssertEqual(state.readOnlyTags, "artist:first,series:one")

        let store = TestStore(initialState: state) {
            ArchiveDetailsFeature()
        }
        await store.send(.loadLocalFields)
    }

    @MainActor
    func testArchiveDetailsLoadLocalFieldsRefreshesWhenInactiveAndSkipsActiveEdit() async {
        let archive = Shared(value: makeDetailsArchive(
            id: "arc1",
            name: "Original",
            tags: "artist:old"
        ))
        let store = TestStore(
            initialState: ArchiveDetailsFeature.State(archive: archive)
        ) {
            ArchiveDetailsFeature()
        }

        archive.withLock {
            $0.name = "Updated"
            $0.tags = "artist:new"
        }
        XCTAssertTrue(store.state.needsLocalFieldsRefresh)

        await store.send(.binding(.set(\.editMode, .active))) {
            $0.editMode = .active
        }
        await store.send(.binding(.set(\.title, "Draft"))) {
            $0.title = "Draft"
        }
        await store.send(.loadLocalFields)

        await store.send(.binding(.set(\.editMode, .inactive))) {
            $0.editMode = .inactive
        }
        await store.send(.loadLocalFields) {
            $0.title = "Updated"
            $0.editableTags = "artist:new"
        }
        XCTAssertFalse(store.state.needsLocalFieldsRefresh)
    }

    @MainActor
    func testArchiveDetailsUpdatingLocalTankoubonMetadataKeepsIncludedTagsReadOnly() async {
        let archive = Shared(value: makeDetailsArchive(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank,artist:first"
        ))
        let metadata = TankoubonDetailsMetadata(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank",
            includedArchiveTags: "artist:first,series:one"
        )
        let store = TestStore(
            initialState: ArchiveDetailsFeature.State(
                archive: archive,
                tankoubonMetadata: metadata
            )
        ) {
            ArchiveDetailsFeature()
        }

        await store.send(.updateLocalTankoubonMetadata("New title", "artist:new,series:one")) {
            $0.tankoubonMetadata?.name = "New title"
            $0.tankoubonMetadata?.tags = "artist:new,series:one"
            $0.$archive.withLock {
                $0.name = "New title"
                $0.tags = "artist:new,series:one,artist:first"
            }
        }
    }

    @MainActor
    func testCachedArchiveDetailsRemovesLocalCache() async throws {
        let id = "cachedArchiveDetails"
        let database = try AppDatabase(DatabaseQueue())
        var cache = ArchiveCache(
            id: id,
            title: "Cached archive",
            tags: "",
            thumbnail: nil,
            cached: true,
            totalPages: 1,
            toc: nil,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )
        try database.saveCache(&cache)

        let cacheFolder = LANraragiService.cachePath!
            .appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(
            atPath: cacheFolder.appendingPathComponent("1.jpg").path,
            contents: Data()
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }

        let state = ArchiveDetailsFeature.State(
            archive: Shared(value: cache.toArchiveItem()),
            cached: true
        )
        XCTAssertEqual(state.deleteTarget, .cache)

        let store = TestStore(initialState: state) {
            ArchiveDetailsFeature()
        } withDependencies: {
            $0.appDatabase = database
        }

        await store.send(.confirmDelete) {
            $0.loading = true
        }
        await store.receive(.deleteSuccess) {
            $0.loading = false
        }

        XCTAssertNil(try database.readCache(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFolder.path))
    }
}

private func makeDetailsArchive(
    id: String = "archive",
    name: String = "Archive",
    tags: String = ""
) -> ArchiveItem {
    ArchiveItem(
        id: id,
        name: name,
        extension: "zip",
        tags: tags,
        isNew: false,
        progress: 0,
        pagecount: 10,
        dateAdded: nil
    )
}

final class ArchiveFlowConsistencyTests: LANreaderTestCase {
    @MainActor
    func testUpdatingTankoubonMetadataSyncsReaderAndReopenedDetails() async throws {
        try await configureTestServer()
        stubTankoubonMetadataUpdate(id: "TANK_42", name: "Updated Tank", tags: "artist:new,series:one")

        let tankoubon = makeDetailsArchive(id: "TANK_42", name: "Old Tank", tags: "artist:old,artist:included")
        let chapter = ArchiveChapter(name: "Ch 1", page: 1)
        var initialState = LibraryFeature.State()
        var readerState = ArchiveReaderFeature.State(
            currentArchiveId: tankoubon.id,
            allArchives: [Shared(value: tankoubon)]
        )
        var metadata = TankoubonDetailsMetadata(
            id: tankoubon.id, name: "Old Tank", tags: "artist:old", includedArchiveTags: "artist:included"
        )
        metadata.toc = [chapter]
        readerState.currentTankoubonDetails = metadata
        initialState.path.append(.reader(readerState))

        let store = try makeFlowLibraryTestStore(initialState: initialState)
        let readerID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(id: detailsID, action: .details(.binding(.set(\.title, "Updated Tank"))))))
        await store.send(.path(.element(
            id: detailsID,
            action: .details(.binding(.set(\.editableTags, "artist:new,series:one")))
        )))
        await store.send(.path(.element(id: detailsID, action: .details(.updateArchiveMetadata))))
        await store.receive(\.path[id: detailsID].details.setSuccessMessage, timeout: .seconds(5))

        await store.send(.path(.popFrom(id: detailsID)))
        guard case let .reader(syncedReader) = store.state.path[id: readerID] else {
            return XCTFail("Expected reader state")
        }
        XCTAssertEqual(syncedReader.currentTankoubonDetails?.name, "Updated Tank")
        XCTAssertEqual(syncedReader.currentTankoubonDetails?.tags, "artist:new,series:one")
        XCTAssertEqual(syncedReader.currentTankoubonDetails?.toc, [chapter])
        XCTAssertEqual(syncedReader.allArchives[id: tankoubon.id]?.wrappedValue.name, "Updated Tank")

        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let reopenedDetailsID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .details(reopenedDetails) = store.state.path[id: reopenedDetailsID] else {
            return XCTFail("Expected reopened details state")
        }
        XCTAssertEqual(reopenedDetails.title, "Updated Tank")
        XCTAssertEqual(reopenedDetails.editableTags, "artist:new,series:one")
        XCTAssertEqual(reopenedDetails.readOnlyTags, "artist:included")
    }

    @MainActor
    func testNestedTankoubonEditMarksOriginalDetailsForRefreshOnPopBack() async throws {
        let tankoubon = makeDetailsArchive(id: "TANK_42", name: "Old Tank", tags: "artist:old,artist:included")
        let metadata = TankoubonDetailsMetadata(
            id: tankoubon.id, name: "Old Tank", tags: "artist:old", includedArchiveTags: "artist:included"
        )
        var initialState = LibraryFeature.State()
        var outerReader = ArchiveReaderFeature.State(
            currentArchiveId: tankoubon.id, allArchives: [Shared(value: tankoubon)]
        )
        outerReader.currentTankoubonDetails = metadata
        initialState.path.append(.reader(outerReader))

        let store = try makeFlowLibraryTestStore(initialState: initialState)
        let outerReaderID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.element(id: outerReaderID, action: .reader(.openDetailsTapped))))
        let outerDetailsID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: outerDetailsID, action: .details(.tagTapped("artist:old")))))
        let searchID = try XCTUnwrap(store.state.path.ids.last)

        var innerReader = ArchiveReaderFeature.State(
            currentArchiveId: tankoubon.id, allArchives: [Shared(value: tankoubon)]
        )
        innerReader.currentTankoubonDetails = metadata
        var stateWithNested = store.state
        stateWithNested.path.append(.reader(innerReader))
        let nestedStore = try makeFlowLibraryTestStore(initialState: stateWithNested)
        let innerReaderID = try XCTUnwrap(nestedStore.state.path.ids.last)
        await nestedStore.send(.path(.element(id: innerReaderID, action: .reader(.openDetailsTapped))))
        let innerDetailsID = try XCTUnwrap(nestedStore.state.path.ids.last)

        await nestedStore.send(.path(.element(
            id: innerDetailsID,
            action: .details(.updateLocalTankoubonMetadata("Updated Tank", "artist:new"))
        )))
        await nestedStore.send(.path(.popFrom(id: searchID)))

        guard case let .details(staleOuterDetails) = nestedStore.state.path[id: outerDetailsID] else {
            return XCTFail("Expected outer details state")
        }
        XCTAssertTrue(staleOuterDetails.needsLocalFieldsRefresh)
        await nestedStore.send(.path(.element(id: outerDetailsID, action: .details(.loadLocalFields))))
        guard case let .details(refreshedOuterDetails) = nestedStore.state.path[id: outerDetailsID] else {
            return XCTFail("Expected refreshed outer details state")
        }
        XCTAssertEqual(refreshedOuterDetails.title, "Updated Tank")
        XCTAssertEqual(refreshedOuterDetails.editableTags, "artist:new")
        XCTAssertEqual(refreshedOuterDetails.readOnlyTags, "artist:included")
        XCTAssertFalse(refreshedOuterDetails.needsLocalFieldsRefresh)
    }

    @MainActor
    func testNestedDeleteOfSameArchiveRemovesEarlierStaleEntriesInNavigationController() async throws {
        try await configureTestServer()
        let archive = makeDetailsArchive(id: "dupArc", name: "Duplicate", tags: "artist:dup")
        stubFlowBackgroundRequests(archive: archive)
        let database = try makeFlowThumbnailDatabase(archiveIds: [archive.id])
        defer { clearFlowSharedArchives() }

        try await withDependencies {
            $0.appDatabase = database
        } operation: {
            let store = Store(initialState: LibraryFeature.State()) { LibraryFeature() }
            let nav = makeLibraryNavigationController(store: store)
            nav.loadViewIfNeeded()
            nav.topViewController?.loadViewIfNeeded()

            _ = store.send(.archiveList(.populateArchives([archive], 1, false)))
            sendFlowActionWithoutAnimation(store, .archiveList(.openReader(archiveId: archive.id, fromStart: false)))
            await waitForFlowNavigation { nav.viewControllers.count == 2 }
            let outerReaderID = try XCTUnwrap(store.path.ids.last)

            sendFlowActionWithoutAnimation(
                store, .path(.element(id: outerReaderID, action: .reader(.openDetailsTapped)))
            )
            await waitForFlowNavigation { nav.viewControllers.count == 3 }
            let outerDetailsID = try XCTUnwrap(store.path.ids.last)

            sendFlowActionWithoutAnimation(
                store, .path(.element(id: outerDetailsID, action: .details(.tagTapped("artist:dup"))))
            )
            await waitForFlowNavigation { nav.viewControllers.count == 4 }
            let tagSearchID = try XCTUnwrap(store.path.ids.last)
            let searchController = try XCTUnwrap(nav.topViewController as? UISearchViewV2Controller)

            _ = store.send(.path(.element(
                id: tagSearchID, action: .search(.archiveList(.populateArchives([archive], 1, false)))
            )))
            sendFlowActionWithoutAnimation(store, .path(.element(
                id: tagSearchID, action: .search(.archiveList(.openReader(archiveId: archive.id, fromStart: false)))
            )))
            await waitForFlowNavigation { nav.viewControllers.count == 5 }
            let innerReaderID = try XCTUnwrap(store.path.ids.last)

            sendFlowActionWithoutAnimation(
                store, .path(.element(id: innerReaderID, action: .reader(.openDetailsTapped)))
            )
            await waitForFlowNavigation { nav.viewControllers.count == 6 }
            let innerDetailsID = try XCTUnwrap(store.path.ids.last)

            sendFlowActionWithoutAnimation(store, .path(.element(id: innerDetailsID, action: .details(.deleteSuccess))))
            await waitForFlowNavigation { nav.viewControllers.count == 2 }

            XCTAssertEqual(Array(store.path.ids), [tagSearchID])
            XCTAssertTrue(nav.topViewController === searchController)
        }
    }

    @MainActor
    func testNestedDeleteOfOtherArchiveRemovesItFromEarlierReaderAllArchives() async throws {
        let first = makeDetailsArchive(id: "arc1", name: "First", tags: "artist:dup")
        let second = makeDetailsArchive(id: "arc2", name: "Second", tags: "artist:dup")
        let store = try makeFlowLibraryTestStore(initialState: LibraryFeature.State())
        defer { clearFlowSharedArchives() }

        await store.send(.archiveList(.populateArchives([first, second], 2, false)))
        await store.send(.archiveList(.openReader(archiveId: first.id, fromStart: false)))
        let outerReaderID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: outerReaderID, action: .reader(.openDetailsTapped))))
        let outerDetailsID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: outerDetailsID, action: .details(.tagTapped("artist:dup")))))
        let searchID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(
            id: searchID, action: .search(.archiveList(.populateArchives([first, second], 2, false)))
        )))
        await store.send(.path(.element(
            id: searchID, action: .search(.archiveList(.openReader(archiveId: second.id, fromStart: false)))
        )))
        let innerReaderID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: innerReaderID, action: .reader(.openDetailsTapped))))
        let innerDetailsID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(id: innerDetailsID, action: .details(.deleteSuccess))))
        XCTAssertEqual(Array(store.state.path.ids), [outerReaderID, outerDetailsID, searchID])
        guard case let .reader(outerReader) = store.state.path[id: outerReaderID] else {
            return XCTFail("Expected outer reader state")
        }
        XCTAssertEqual(outerReader.allArchives.ids, [first.id])
    }

    @MainActor
    func testCacheChangesSyncOnlineReaderFlagAndCleanStaleCachedEntries() async throws {
        let archive = makeDetailsArchive(id: "arc1", name: "First", tags: "artist:dup")
        var state = LibraryFeature.State()
        state.path.append(.cache(CacheFeature.State()))
        state.path.append(.reader(ArchiveReaderFeature.State(
            currentArchiveId: archive.id, allArchives: [Shared(value: archive)], cached: true
        )))
        state.path.append(.details(ArchiveDetailsFeature.State(archive: Shared(value: archive), cached: true)))
        state.path.append(.search(SearchFeature.State(keyword: "artist:dup")))
        state.path.append(.reader(ArchiveReaderFeature.State(
            currentArchiveId: archive.id, allArchives: [Shared(value: archive)], cached: false
        )))
        state.path.append(.details(ArchiveDetailsFeature.State(archive: Shared(value: archive), cached: false)))
        state.path.append(.search(SearchFeature.State(keyword: "artist:dup")))
        state.path.append(.reader(ArchiveReaderFeature.State(
            currentArchiveId: archive.id, allArchives: [Shared(value: archive)], cached: false
        )))

        let store = try makeFlowLibraryTestStore(initialState: state)
        let ids = Array(store.state.path.ids)
        let cacheID = ids[0]
        let firstSearchID = ids[3]
        let firstOnlineReaderID = ids[4]
        let firstOnlineDetailsID = ids[5]
        let secondSearchID = ids[6]
        let secondOnlineReaderID = ids[7]

        await store.send(.path(.element(id: secondOnlineReaderID, action: .reader(.finishDownloadPages))))
        if case let .reader(firstOnline) = store.state.path[id: firstOnlineReaderID] {
            XCTAssertTrue(firstOnline.inCache)
        } else {
            XCTFail("Expected first online reader")
        }

        await store.send(.path(.element(id: secondOnlineReaderID, action: .reader(.removeCacheSuccess))))
        XCTAssertEqual(
            Array(store.state.path.ids),
            [cacheID, firstSearchID, firstOnlineReaderID, firstOnlineDetailsID, secondSearchID, secondOnlineReaderID]
        )
        if case let .reader(firstOnline) = store.state.path[id: firstOnlineReaderID] {
            XCTAssertFalse(firstOnline.inCache)
        } else {
            XCTFail("Expected first online reader to remain open with updated cache flag")
        }
    }
}

@MainActor
private func makeFlowLibraryTestStore(initialState: LibraryFeature.State) throws -> TestStoreOf<LibraryFeature> {
    let database = try AppDatabase(DatabaseQueue())
    let store = TestStore(initialState: initialState) {
        LibraryFeature()
    } withDependencies: {
        $0.appDatabase = database
    }
    store.exhaustivity = .off
    return store
}

@MainActor
private func makeFlowThumbnailDatabase(archiveIds: [String]) throws -> AppDatabase {
    let database = try AppDatabase(DatabaseQueue())
    let thumbnailData = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
    for id in archiveIds {
        var thumbnail = ArchiveThumbnail(id: id, thumbnail: thumbnailData, lastUpdate: Date())
        try database.saveArchiveThumbnail(&thumbnail)
    }
    return database
}

private func clearFlowSharedArchives() {
    @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
    $archiveItems.withLock { $0 = [] }
}

private func stubTankoubonMetadataUpdate(id: String, name: String, tags: String) {
    let matchesBody: HTTPStubsTestBlock = { request in
        guard let body = request.ohhttpStubs_httpBody,
              let actual = try? JSONSerialization.jsonObject(with: body) as? NSDictionary else {
            return false
        }
        return actual.isEqual(to: ["metadata": ["name": name, "tags": tags]])
    }
    stub(
        condition: isHost("localhost")
            && isPath("/api/tankoubons/\(id)")
            && isMethodPUT()
            && hasHeaderNamed("Content-Type", value: "application/json")
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")
            && matchesBody
    ) { @Sendable _ in
        HTTPStubsResponse(
            jsonObject: ["success": 1],
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

@MainActor
private func sendFlowActionWithoutAnimation(
    _ store: StoreOf<LibraryFeature>,
    _ action: LibraryFeature.Action
) {
    withUITransaction(\.uiKit.disablesAnimations, true) {
        _ = store.send(action)
    }
}

@MainActor
private func waitForFlowNavigation(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func stubFlowBackgroundRequests(archive: ArchiveItem) {
    let headers = ["Content-Type": "application/json"]
    let archiveId = archive.id
    let archiveName = archive.name
    let archiveTags = archive.tags
    let archiveExt = archive.extension
    stub(condition: isHost("localhost") && isPath("/api/archives/\(archiveId)/files") && isMethodGET()) { @Sendable _ in
        HTTPStubsResponse(jsonObject: ["pages": []], statusCode: 200, headers: headers)
    }
    stub(condition: isHost("localhost") && isPath("/api/categories") && isMethodGET()) { @Sendable _ in
        HTTPStubsResponse(jsonObject: [], statusCode: 200, headers: headers)
    }
    stub(condition: isHost("localhost") && isPath("/api/database/stats") && isMethodGET()) { @Sendable _ in
        HTTPStubsResponse(jsonObject: [], statusCode: 200, headers: headers)
    }
    stub(condition: isHost("localhost") && isPath("/api/search") && isMethodGET()) { @Sendable _ in
        HTTPStubsResponse(
            jsonObject: [
                "data": [[
                    "arcid": archiveId,
                    "extension": archiveExt,
                    "isnew": "false",
                    "pagecount": 10,
                    "progress": 0,
                    "tags": archiveTags,
                    "title": archiveName
                ]],
                "draw": 0,
                "recordsFiltered": 1,
                "recordsTotal": 1
            ],
            statusCode: 200,
            headers: headers
        )
    }
}
