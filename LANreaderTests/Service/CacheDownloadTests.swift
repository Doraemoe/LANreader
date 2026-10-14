import XCTest
import SwiftUI
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import os
@testable import LANreader

final class CacheDownloadTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set("apiKey", forKey: SettingsKey.lanraragiApiKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testCacheRetryAfterOfflineStartupUsesModernAPIWithoutRefreshingServerInfo() async throws {
        let id = "cacheOfflineStartup-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        try good.write(to: folder.appendingPathComponent("1.jpg"))
        let offline = OSAllocatedUnfairLock(initialState: true)
        let requests = OSAllocatedUnfairLock(initialState: [String]())
        stub(condition: isHost("localhost")) { @Sendable request in
            let path = request.url!.path
            requests.withLock { $0.append("\(request.httpMethod!) \(path)") }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer YXBpS2V5")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.url!.query)
            if offline.withLock({ $0 }) {
                return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
            }
            switch path {
            case "/api/archives/\(id)/files":
                XCTAssertEqual(request.httpMethod, "GET")
                return HTTPStubsResponse(jsonObject: ["pages": ["./cold-retry/1", "./cold-retry/2"]],
                                         statusCode: 200, headers: ["Content-Type": "application/json"])
            case "/cold-retry/2":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Archive-Id"), id)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Page-Number"), "2")
                return HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
            default:
                return HTTPStubsResponse(data: Data(), statusCode: 404, headers: nil)
            }
        }
        let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        await service.checkServerVersionAtStartup()
        let database = try AppDatabase(DatabaseQueue())
        var cache = cacheTestRecord(id: id)
        try database.saveCache(&cache)
        let clock = TestClock()
        let store = TestStore(initialState: CacheFeature.State()) { CacheFeature() } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.load)
        await store.receive(.cacheDownloadFailed(id))
        offline.withLock { $0 = false }
        let task = await store.send(.retryCache(id))
        await store.receive(.retryCacheFinished(id))
        try await waitForCacheDownloads(service, archiveId: id)
        await clock.advance(by: .seconds(2))
        await store.receive(.removeItemFromDownloading(id))
        await task.finish()
        XCTAssertEqual(requests.withLock { $0 }, [
            "GET /api/info", "GET /api/archives/\(id)/files", "GET /cold-retry/2"
        ])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("1.jpg")), good)
        XCTAssertEqual(try database.readCache(id)?.cached, true)
    }

    @MainActor
    func testCacheRetryActionRecoversMissingPageAndCompletesArchive() async throws {
        let id = "cacheFeatureRetry-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        try good.write(to: folder.appendingPathComponent("1.jpg"))
        try Data("error".utf8).write(to: folder.appendingPathComponent("2.img"))
        let requests = OSAllocatedUnfairLock(initialState: [String]())
        stub(condition: isHost("localhost") && isPath("/api/archives/\(id)/files") && isMethodGET()) { @Sendable _ in
            HTTPStubsResponse(jsonObject: ["pages": ["./cache-feature/1", "./cache-feature/2"]],
                              statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        stub(condition: isHost("localhost") && pathStartsWith("/cache-feature/")) { @Sendable request in
            requests.withLock { $0.append(request.url!.path) }
            let response = HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
            response.requestTime = 0.2
            return response
        }
        let database = try AppDatabase(DatabaseQueue())
        var cache = cacheTestRecord(id: id)
        try database.saveCache(&cache)
        let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        let clock = TestClock()
        let store = TestStore(initialState: failedCacheState(id: id)) { CacheFeature() } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        let task = await store.send(.retryCache(id)) {
            $0.failedDownloads.remove(id)
            $0.retryingDownloads.insert(id)
        }
        await store.send(.retryCache(id))
        await store.receive(.retryCacheFinished(id)) { $0.retryingDownloads.remove(id) }
        try await waitForCacheDownloads(service, archiveId: id)
        await clock.advance(by: .seconds(2))
        await store.receive(.removeItemFromDownloading(id)) { $0.downloading.removeValue(forKey: id) }
        await task.finish()
        XCTAssertEqual(requests.withLock { $0 }, ["/cache-feature/2"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("1.jpg")), good)
        XCTAssertEqual(try database.readCache(id)?.cached, true)
        XCTAssertEqual(try database.readCache(id)?.progress, 1)
        XCTAssertEqual(try database.readCache(id)?.toc, cache.toc)
    }

    @MainActor
    func testRetryExtractionFailureKeepsRetryAvailable() async throws {
        let id = "cacheExtractionFailure"
        stub(condition: isHost("localhost") && isPath("/api/archives/\(id)/files")) { @Sendable _ in
            HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        let store = TestStore(initialState: failedCacheState(id: id)) { CacheFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }
        store.exhaustivity = .off
        await store.send(.retryCache(id))
        await store.receive(\.retryCacheFailed)
        await store.finish()
        XCTAssertEqual(store.state.downloading[id]?.current, 1)
        XCTAssertEqual(store.state.failedDownloads, [id])
        XCTAssertTrue(store.state.retryingDownloads.isEmpty)
        XCTAssertFalse(store.state.errorMessage.isEmpty)
    }

    @MainActor
    func testRelaunchRecognizesIncompleteCacheWithoutActiveDownloads() async throws {
        let id = "cacheRelaunch-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try cacheTestImageData().write(to: folder.appendingPathComponent("1.jpg"))
        try Data("error".utf8).write(to: folder.appendingPathComponent("2.jpg"))
        let database = try AppDatabase(DatabaseQueue())
        var cache = cacheTestRecord(id: id)
        try database.saveCache(&cache)
        let store = TestStore(initialState: CacheFeature.State()) { CacheFeature() } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        let task = await store.send(.load)
        await store.receive(.updateProgressInDownloading(id, 1))
        await store.receive(.cacheDownloadFailed(id))
        await task.finish()
        XCTAssertEqual(store.state.failedDownloads, [id])
        XCTAssertEqual(try database.readCache(id)?.cached, false)
    }

    func testTankoubonCachingUsesGlobalPageNumbersForUnderlyingArchives() async throws {
        let id = "TANK_cacheTest-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        stub(condition: isHost("localhost") && pathStartsWith("/cache-tank/")) { @Sendable request in
            let expected = request.url!.lastPathComponent == "a" ? "1" : "2"
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Archive-Id"), id)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Page-Number"), expected)
            return HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
        }
        let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        try await service.cachePages(archiveId: id, pages: [
            ReaderExtractedPage(archiveId: "a", path: "/cache-tank/a", archivePageNumber: 1),
            ReaderExtractedPage(archiveId: "b", path: "/cache-tank/b", archivePageNumber: 1)
        ])
        try await waitForCacheDownloads(service, archiveId: id)
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: folder, totalPages: 2), [1, 2])
    }

    @MainActor
    func testNormalReaderDownloadKeepsImageAndRendersItInPageCell() async throws {
        UserDefaults.standard.set(false, forKey: SettingsKey.translationEnabled)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.translationEnabled) }
        let good = cacheTestImageData()
        stub(condition: isHost("localhost") && isPath("/normal-reader-page")) { @Sendable _ in
            HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
        }
        let state = PageFeature.State(archiveId: UUID().uuidString, pageId: "/normal-reader-page", pageNumber: 1)
        let folder = try XCTUnwrap(state.folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(initialState: state) { PageFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }
        let cell = UIPageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: store, fitPageWidth: false, showsStamps: false,
                       onCreateStamp: { _ in }, onEditStamp: { _ in })
        await store.send(.load(true)).finish()
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(store.imageLoaded)
        XCTAssertEqual(store.pageMode, .normal)
        XCTAssertTrue(store.errorMessage.isEmpty)
        let stored = try XCTUnwrap(ImageService.shared.storedImagePath(folderUrl: folder, pageNumber: "1"))
        XCTAssertEqual(try Data(contentsOf: stored), good)
        var views = cell.contentView.subviews
        var renderedImage: UIImage?
        while let view = views.popLast() {
            views.append(contentsOf: view.subviews)
            if let imageView = view as? UIImageView, !imageView.isHidden, let image = imageView.image {
                renderedImage = image
            }
        }
        let expectedImage = try XCTUnwrap(UIImage(data: good)?.cgImage)
        XCTAssertEqual(renderedImage?.isSymbolImage, false)
        XCTAssertEqual(renderedImage?.cgImage?.width, expectedImage.width)
        XCTAssertEqual(renderedImage?.cgImage?.height, expectedImage.height)
    }

    @MainActor
    func testCachedReaderRendersValidPageRetainedBesideInvalidCopy() async throws {
        let state = PageFeature.State(archiveId: UUID().uuidString,
                                      pageId: "/cached-retained-page", pageNumber: 1, cached: true)
        let folder = try XCTUnwrap(state.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        try Data("<html>Error</html>".utf8).write(to: folder.appendingPathComponent("1.img"))
        try good.write(to: folder.appendingPathComponent("1.jpg"))
        let requests = OSAllocatedUnfairLock(initialState: 0)
        stub(condition: isHost("localhost") && isPath(state.pageId)) { @Sendable _ in
            requests.withLock { $0 += 1 }
            return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        try await service.cachePages(archiveId: state.sourceArchiveId, pages: [
            ReaderExtractedPage(archiveId: state.sourceArchiveId, path: state.pageId, archivePageNumber: 1)
        ])
        try await waitForCacheDownloads(service, archiveId: state.sourceArchiveId)
        let store = Store(initialState: state) { PageFeature() } withDependencies: {
            $0.lanraragiService = service
        }
        let cell = UIPageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: store, fitPageWidth: false, showsStamps: false,
                       onCreateStamp: { _ in }, onEditStamp: { _ in })
        await store.send(.load(false)).finish()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: folder, totalPages: 1), [1])
        XCTAssertEqual(ImageService.shared.storedImagePath(folderUrl: folder, pageNumber: "1")?.lastPathComponent,
                       "1.jpg")
        XCTAssertEqual(store.pageMode, .normal)
        XCTAssertTrue(store.errorMessage.isEmpty)
        XCTAssertEqual(requests.withLock { $0 }, 0)
        var views = cell.contentView.subviews
        var renderedImage: UIImage?
        while let view = views.popLast() {
            views.append(contentsOf: view.subviews)
            if let imageView = view as? UIImageView, !imageView.isHidden, let image = imageView.image {
                renderedImage = image
            }
        }
        let expectedImage = try XCTUnwrap(UIImage(data: good)?.cgImage)
        XCTAssertEqual(renderedImage?.isSymbolImage, false)
        XCTAssertEqual(renderedImage?.cgImage?.width, expectedImage.width)
        XCTAssertEqual(renderedImage?.cgImage?.height, expectedImage.height)
    }

    @MainActor
    func testPageFeatureReportsInvalidDownloadedImageAsAnError() async throws {
        UserDefaults.standard.set(false, forKey: SettingsKey.translationEnabled)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.translationEnabled) }
        stub(condition: isHost("localhost") && isPath("/cache-invalid-reader-page")) { @Sendable _ in
            HTTPStubsResponse(data: Data("not an image".utf8), statusCode: 200,
                              headers: ["Content-Type": "image/jpeg"])
        }
        let state = PageFeature.State(archiveId: UUID().uuidString,
                                      pageId: "/cache-invalid-reader-page", pageNumber: 1)
        defer { if let folder = state.folder { try? FileManager.default.removeItem(at: folder) } }
        let store = TestStore(initialState: state) { PageFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }
        store.exhaustivity = .off
        let task = await store.send(.load(true))
        await store.receive(.setError(String(localized: "archive.page.store.failed")))
        await task.finish()
        XCTAssertEqual(store.state.pageMode, .loading)
        XCTAssertFalse(store.state.loading)
        XCTAssertFalse(store.state.errorMessage.isEmpty)
        XCTAssertNil(ImageService.shared.storedImagePath(folderUrl: state.folder, pageNumber: "1"))
    }

    @MainActor
    func testCachedCoversSurviveDatabaseClearAndStayOffline() async throws {
        let cover = cacheTestImageData()
        stub(condition: isHost("localhost")) { @Sendable _ in
            XCTFail("Cached covers must not request the server")
            return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        for id in ["cached-cover", "TANK_cached-cover"] {
            let database = try AppDatabase(DatabaseQueue())
            var cache = ArchiveCache(
                id: id, title: "Archive", tags: "", thumbnail: cover,
                cached: true, totalPages: 1, toc: nil, lastUpdate: Date()
            )
            try database.saveCache(&cache)
            var thumbnail = ArchiveThumbnail(id: id, thumbnail: cover, lastUpdate: Date())
            try database.saveArchiveThumbnail(&thumbnail)
            let state = GridFeature.State(archive: Shared(value: cache.toArchiveItem()), cached: true)
            let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
            let gridStore = Store(initialState: state) { GridFeature() } withDependencies: {
                $0.appDatabase = database
                $0.lanraragiService = service
            }
            let renderedCover = try XCTUnwrap(renderCachedCover(gridStore, database: database))
            try database.clearDatabase()
            XCTAssertNil(try database.readArchiveThumbnail(id))
            XCTAssertEqual(try database.readCache(id)?.thumbnail, cover)
            XCTAssertEqual(renderCachedCover(gridStore, database: database), renderedCover)

            let store = TestStore(initialState: state) { GridFeature() } withDependencies: {
                $0.appDatabase = database
                $0.lanraragiService = service
            }
            for force in [false, true] {
                await store.send(.load(force))
                await store.finish()
            }
        }
    }

    func testClearingDatabasePreservesCachedCoverWithoutSharedThumbnail() throws {
        let database = try AppDatabase(DatabaseQueue())
        let cover = Data("saved cover".utf8)
        var cache = ArchiveCache(
            id: "cached-cover", title: "Archive", tags: "", thumbnail: cover,
            cached: true, totalPages: 1, toc: nil, lastUpdate: Date(timeIntervalSince1970: 1), progress: 1
        )
        try database.saveCache(&cache)
        try database.clearDatabase()
        XCTAssertEqual(try database.readCache(cache.id), cache)
    }

    @MainActor
    func testReaderCacheActionDownloadsSplitSourcePageOnce() async throws {
        let id = "cacheReader-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        let requests = OSAllocatedUnfairLock(initialState: [Int]())
        stub(condition: isHost("localhost") && pathStartsWith("/cache-reader/")) { @Sendable request in
            requests.withLock { $0.append(Int(request.value(forHTTPHeaderField: "X-Page-Number")!)!) }
            return HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
        }
        let archive = ArchiveItem(id: id, name: "Archive", extension: "cbz", tags: "", isNew: false,
                                  progress: 1, pagecount: 2, dateAdded: nil)
        var state = ArchiveReaderFeature.State(currentArchiveId: id, allArchives: [Shared(value: archive)])
        state.pages = [
            PageFeature.State(archiveId: id, pageId: "/cache-reader/1", pageNumber: 1, pageMode: .left),
            PageFeature.State(archiveId: id, pageId: "/cache-reader/1", pageNumber: 1, pageMode: .right),
            PageFeature.State(archiveId: id, pageId: "/cache-reader/2", pageNumber: 2)
        ]
        let database = try AppDatabase(DatabaseQueue())
        var thumbnail = ArchiveThumbnail(id: id, thumbnail: good, lastUpdate: Date())
        try database.saveArchiveThumbnail(&thumbnail)
        let service = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        let store = TestStore(initialState: state) { ArchiveReaderFeature() } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
        }
        store.exhaustivity = .off
        await store.send(.downloadPages)
        await store.receive(.finishDownloadPages)
        await store.finish()
        try await waitForCacheDownloads(service, archiveId: id)
        XCTAssertEqual(requests.withLock { $0.sorted() }, [1, 2])
        XCTAssertEqual(try database.readCache(id)?.totalPages, 2)
        XCTAssertEqual(try database.readCache(id)?.thumbnail, good)
        try database.clearDatabase()
        XCTAssertEqual(try database.readCache(id)?.thumbnail, good)
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: folder, totalPages: 2), [1, 2])
    }

    func testBackgroundCacheRejectsErrorResponsesAndInvalidImages() async throws {
        let cacheService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        let id = "cacheReject-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        defer { try? FileManager.default.removeItem(at: folder) }
        let responses = [(401, Data("Unauthorized".utf8)), (404, cacheTestImageData()),
                         (200, Data("<html>Error</html>".utf8))]
        for (index, response) in responses.enumerated() {
            stub(condition: isHost("localhost") && isPath("/cache-reject/\(index)")) { @Sendable request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer YXBpS2V5")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Archive-Id"), id)
                return HTTPStubsResponse(data: response.1, statusCode: Int32(response.0), headers: nil)
            }
        }
        try await cacheService.cachePages(archiveId: id, pages: responses.indices.map {
            ReaderExtractedPage(archiveId: id, path: "/cache-reject/\($0)", archivePageNumber: $0 + 1)
        })
        try await waitForCacheDownloads(cacheService, archiveId: id)
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: folder, totalPages: 3), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testCacheRetryKeepsValidPagesAndDoesNotDuplicateActiveRequests() async throws {
        let cacheService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        let id = "cacheRetry-" + UUID().uuidString
        let folder = LANraragiService.cachePath!.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = cacheTestImageData()
        try good.write(to: folder.appendingPathComponent("1.jpg"))
        try Data("invalid".utf8).write(to: folder.appendingPathComponent("2.img"))
        let requests = OSAllocatedUnfairLock(initialState: [Int]())
        stub(condition: isHost("localhost") && pathStartsWith("/cache-retry/")) { @Sendable request in
            let page = Int(request.url!.lastPathComponent)!
            requests.withLock { $0.append(page) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Page-Number"), String(page))
            let response = HTTPStubsResponse(data: good, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
            response.requestTime = 0.2
            return response
        }
        let pages = (1...2).map {
            ReaderExtractedPage(archiveId: id, path: "/cache-retry/\($0)", archivePageNumber: $0)
        }
        async let first: Void = cacheService.cachePages(archiveId: id, pages: pages)
        async let second: Void = cacheService.cachePages(archiveId: id, pages: pages)
        _ = try await (first, second)
        try await cacheService.cachePages(archiveId: id, pages: pages)
        try await waitForCacheDownloads(cacheService, archiveId: id)
        XCTAssertEqual(requests.withLock { $0 }, [2])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("1.jpg")), good)
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: folder, totalPages: 2), [1, 2])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("2.img").path))
    }

    func testBackgroundCacheTransportFailureLeavesNoPageOrActiveDownload() async throws {
        let cacheService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        let id = "cacheTransport-" + UUID().uuidString
        stub(condition: isHost("localhost") && isPath("/cache-transport")) { @Sendable _ in
            HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        try await cacheService.cachePages(archiveId: id, pages: [
            ReaderExtractedPage(archiveId: id, path: "/cache-transport", archivePageNumber: 1)
        ])
        try await waitForCacheDownloads(cacheService, archiveId: id)
        XCTAssertNil(ImageService.shared.storedImagePath(
            folderUrl: LANraragiService.cachePath?.appendingPathComponent(id), pageNumber: "1"
        ))
    }

}

@MainActor
private func renderCachedCover(_ store: StoreOf<GridFeature>, database: AppDatabase) -> Data? {
    withDependencies {
        $0.appDatabase = database
    } operation: {
        ImageRenderer(content: ArchiveGridV2(store: store).frame(width: 180, height: 270))
            .uiImage?.pngData()
    }
}

private func cacheTestImageData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }.jpegData(compressionQuality: 0.9)!
}

private func waitForCacheDownloads(_ service: LANraragiService, archiveId: String) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await service.activeCacheDownloadIDs().contains(archiveId) {
        guard ContinuousClock.now < deadline else {
            XCTFail("Cache download did not finish")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

private func cacheTestRecord(id: String) -> ArchiveCache {
    ArchiveCache(id: id, title: "Archive", tags: "", thumbnail: nil, cached: false,
                 totalPages: 2, toc: [ArchiveChapter(name: "Chapter", page: 1)], lastUpdate: Date(), progress: 1)
}

private func failedCacheState(id: String) -> CacheFeature.State {
    var state = CacheFeature.State()
    state.downloading[id] = PageProgress(current: 1, total: 2)
    state.failedDownloads.insert(id)
    return state
}
