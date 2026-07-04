import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ArchiveListFeatureTests: XCTestCase {
    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testSearchTabDoesNotLoadWithoutSearchFilter() async {
        let archive = ArchiveItem(
            id: "existing",
            name: "Existing",
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 0,
            pagecount: 10,
            dateAdded: nil
        )
        var initialState = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
        initialState.archives = [GridFeature.State(archive: Shared(value: archive))]
        initialState.archivesToDisplay = initialState.archives
        initialState.total = 1

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        await store.send(.load(true)) {
            $0.archives = []
            $0.archivesToDisplay = []
            $0.total = 0
        }
    }

    func testLibraryTabCanLoadWithoutSearchFilter() {
        let state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )

        XCTAssertTrue(state.canLoadArchives)
    }

    @MainActor
    func testGridLoadUsesArchiveThumbnailEndpointForNormalArchive() async throws {
        try await configureVerifiedClient()

        let archiveId = "0123456789012345678901234567890123456789"
        let expectedThumbnail = Data([0xFF, 0xD8, 0xFF, 0xDB])
        stubArchiveThumbnail(id: archiveId, data: expectedThumbnail)

        let database = try makeInMemoryDatabase()
        let store = makeGridTestStore(
            archive: makeArchive(id: archiveId, fileExtension: "zip"),
            database: database
        )

        await store.send(.load(false))
        await store.receive(.increaseNonce) {
            $0.nonce = 1
        }

        let savedThumbnail = try database.readArchiveThumbnail(archiveId)
        XCTAssertEqual(savedThumbnail?.thumbnail, expectedThumbnail)
    }

    @MainActor
    func testGridLoadUsesTankoubonThumbnailEndpointForTankArchive() async throws {
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let expectedThumbnail = Data([0x89, 0x50, 0x4E, 0x47])
        stubTankoubonThumbnail(id: tankId, data: expectedThumbnail)

        let database = try makeInMemoryDatabase()
        let store = makeGridTestStore(
            archive: makeArchive(id: tankId, fileExtension: ".tank"),
            database: database
        )

        await store.send(.load(false))
        await store.receive(.increaseNonce) {
            $0.nonce = 1
        }

        let savedThumbnail = try database.readArchiveThumbnail(tankId)
        XCTAssertEqual(savedThumbnail?.thumbnail, expectedThumbnail)
    }

}

private func configureVerifiedClient() async throws {
    let url = "https://localhost"
    let apiKey = "apiKey"
    UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
    UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)

    stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "archives_per_page": 100,
              "debug_mode": false,
              "has_password": true,
              "motd": "",
              "name": "LANraragi",
              "nofun_mode": false,
              "server_tracks_progress": true,
              "version": "0.9.30",
              "version_name": "Dodgy Docker"
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }

    _ = try await LANraragiService.shared.verifyClient(url: url, apiKey: apiKey)
}

private func stubArchiveThumbnail(id: String, data: Data) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(id)/thumbnail")
            && containsQueryParams(["no_fallback": "true", "page": "0"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
    }
}

private func stubTankoubonThumbnail(id: String, data: Data) {
    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(id)/thumbnail")
            && containsQueryParams(["no_fallback": "true"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/png"])
    }
}

@MainActor
private func makeGridTestStore(
    archive: ArchiveItem,
    database: AppDatabase
) -> TestStoreOf<GridFeature> {
    TestStore(initialState: GridFeature.State(archive: Shared(value: archive))) {
        GridFeature()
    } withDependencies: {
        $0.appDatabase = database
    }
}

private func makeArchive(id: String, fileExtension: String) -> ArchiveItem {
    ArchiveItem(
        id: id,
        name: "Archive",
        extension: fileExtension,
        tags: "",
        isNew: false,
        progress: 0,
        pagecount: 10,
        dateAdded: nil
    )
}

private func makeInMemoryDatabase() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
}
