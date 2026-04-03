//
// Created on 7/10/20.
//

import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
@testable import LANreader

// swiftlint:disable type_body_length
class LANraragiServiceTest: XCTestCase {

    private let url = "https://localhost"
    private let apiKey = "apiKey"

    private var service: LANraragiService!

    override func setUp() async throws {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
        service = LANraragiService.shared
    }

    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
        HTTPStubs.removeAllStubs()
    }

    func testGetServerInfo() async throws {
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ServerInfoResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.verifyClient(url: url, apiKey: apiKey)
        XCTAssertEqual(actual.archivesPerPage, 100)
        XCTAssertEqual(actual.debugMode, false)
        XCTAssertEqual(actual.hasPassword, true)
    }

    func testGetServerInfoUnauthorized() async throws {
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.verifyClient(url: url, apiKey: apiKey)
        XCTAssertNil(actual)
    }

    func testRetrieveArchiveIndex() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveIndexResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.retrieveArchiveIndex().value

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0].arcid, "abcd1234")
        XCTAssertEqual(actual[0].isnew, "false")
        XCTAssertEqual(actual[0].tags, "artist:abc, language:def, parody:ghi, category:jkl")
        XCTAssertEqual(actual[0].title, "title")
    }

    func testRetrieveArchiveIndexUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.retrieveArchiveIndex().value
        XCTAssertNil(actual)
    }

    func testRetrieveArchiveIndexNullTags() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveIndexResponseNullTags.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.retrieveArchiveIndex().value
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0].arcid, "abcd1234")
        XCTAssertEqual(actual[0].isnew, "false")
        XCTAssertEqual(actual[0].tags, nil)
        XCTAssertEqual(actual[0].title, "title")
    }

    func testRetrieveArchiveThumbnailReturnsImageData() async throws {
        try await configureVerifiedClient()

        let expected = Data([0xFF, 0xD8, 0xFF, 0xDB])
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/thumbnail")
                && containsQueryParams(["no_fallback": "true", "page": "3"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(data: expected, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
        }

        let actual = try await service.retrieveArchiveThumbnail(id: "id", page: 3)
        XCTAssertEqual(actual, expected)
    }

    func testRetrieveArchiveThumbnailReturnsNilWhenQueued() async throws {
        try await configureVerifiedClient()

        let queuedResponse = Data("""
        {
          "operation": "serve_thumbnail",
          "id": 42
        }
        """.utf8)
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/thumbnail")
                && containsQueryParams(["no_fallback": "true", "page": "0"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: queuedResponse,
                statusCode: 202,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.retrieveArchiveThumbnail(id: "id")
        XCTAssertNil(actual)
    }

    func testRetrieveGeneratedArchiveThumbnailReturnsImageData() async throws {
        try await configureVerifiedClient()

        let expected = Data([0x89, 0x50, 0x4E, 0x47])
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/thumbnail")
                && containsQueryParams([
                    "cachebust": "99",
                    "no_fallback": "true",
                    "page": "5"
                ])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(data: expected, statusCode: 200, headers: ["Content-Type": "image/png"])
        }

        let actual = try await service.retrieveGeneratedArchiveThumbnail(id: "id", page: 5, cacheBust: 99)
        XCTAssertEqual(actual, expected)
    }

    func testRetrieveGeneratedArchiveThumbnailReturnsNilWhenNotReady() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/thumbnail")
                && containsQueryParams([
                    "cachebust": "100",
                    "no_fallback": "true",
                    "page": "5"
                ])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: Data(),
                statusCode: 202,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.retrieveGeneratedArchiveThumbnail(id: "id", page: 5, cacheBust: 100)
        XCTAssertNil(actual)
    }

    func testQueuePageThumbnailsReturnsQueuedJob() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        {
          "job": 42,
          "operation": "generate_page_thumbnails",
          "success": 1
        }
        """.utf8)
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/files/thumbnails")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 202,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.queuePageThumbnails(id: "id").value
        XCTAssertEqual(actual.job, 42)
        XCTAssertNil(actual.message)
        XCTAssertEqual(actual.operation, "generate_page_thumbnails")
        XCTAssertEqual(actual.success, 1)
    }

    func testQueuePageThumbnailsReturnsAlreadyGeneratedMessage() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        {
          "message": "No job queued, all thumbnails already exist.",
          "operation": "generate_page_thumbnails",
          "success": 1
        }
        """.utf8)
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/files/thumbnails")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.queuePageThumbnails(id: "id").value
        XCTAssertNil(actual.job)
        XCTAssertEqual(actual.message, "No job queued, all thumbnails already exist.")
        XCTAssertEqual(actual.operation, "generate_page_thumbnails")
        XCTAssertEqual(actual.success, 1)
    }

    func testSearchArchive() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/search")
                && containsQueryParams(["category": "SET_12345678"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveSearchResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.searchArchive(category: "SET_12345678").value
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.data.count, 1)
        XCTAssertEqual(actual.draw, 0)
        XCTAssertEqual(actual.recordsFiltered, 1)
        XCTAssertEqual(actual.recordsTotal, 1234)
    }

    func testSearchArchiveIndexUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/search")
                && containsQueryParams(["category": "SET_12345678"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.searchArchive(category: "SET_12345678").value
        XCTAssertNil(actual)
    }

    func testRetrieveCategories() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/categories")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveCategoriesResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.retrieveCategories().value
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.count, 2)
        XCTAssertEqual(actual[0].archives.count, 5)
        XCTAssertEqual(actual[0].id, "SET_1234567")
        XCTAssertEqual(actual[0].last_used, "12345678")
        XCTAssertEqual(actual[0].name, "static")
        XCTAssertEqual(actual[0].pinned, "0")
        XCTAssertEqual(actual[0].search, "")

        XCTAssertEqual(actual[1].archives.count, 0)
        XCTAssertEqual(actual[1].id, "SET_0987654")
        XCTAssertEqual(actual[1].last_used, "098765432")
        XCTAssertEqual(actual[1].name, "dynamic")
        XCTAssertEqual(actual[1].pinned, "0")
        XCTAssertEqual(actual[1].search, "keyword")
    }

    func testRetrieveCategoriesUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/categories")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.retrieveCategories().value
        XCTAssertNil(actual)
    }

    func testUpdateCategory() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/categories/SET_12345678")
                && isMethodPUT()
                && hasBody(Data("name=name&pinned=0&search=search".utf8))
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UpdateSearchCategoryResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let item = CategoryItem(id: "SET_12345678", name: "name", archives: [],
                                search: "search", pinned: "0")

        let actual = try await service.updateCategory(item: item).value
        XCTAssertEqual(actual.success, 1)
    }

    func testUpdateCategoryUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/categories/SET_12345678")
                && isMethodPUT()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let item = CategoryItem(id: "SET_12345678", name: "name", archives: [],
                                search: "search", pinned: "0")

        let actual = try? await service.updateCategory(item: item).value
        XCTAssertNil(actual)
    }

    func testExtractArchive() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/extract")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveExtractResponse.json", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.extractArchive(id: "1").value
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.pages.count, 1)
        XCTAssertEqual(actual.pages[0], "./api/archives/abc123/page?path=def456/001.jpg")
    }

    func testExtractArchiveUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/extract")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.extractArchive(id: "1").value
        XCTAssertNil(actual)
    }

    func testClearNewFlag() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/isnew")
                && isMethodDELETE()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ClearNewFlagResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let actual = try await service.clearNewFlag(id: "id").value
        let expected = try FileUtils.readJsonFile(filename: "ClearNewFlagResponse")
        XCTAssertEqual(actual, expected)
    }

    func testClearNewFlagUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/isnew")
                && isMethodDELETE()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let actual = try? await service.clearNewFlag(id: "id").value
        XCTAssertNil(actual)
    }

    func testUpdateArchiveMetadata() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody(Data("tags=tags&title=name".utf8))
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("SetArchiveMetadataResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", extension: "zip",
                                   tags: "tags", isNew: true,
                                   progress: 0, pagecount: 10, dateAdded: 1234)
        let actual = try await service.updateArchive(archive: metadata).value
        let expected = try FileUtils.readJsonFile(filename: "SetArchiveMetadataResponse")
        XCTAssertEqual(actual, expected)
    }

    func testUpdateArchiveMetadataUnauthorized() async throws {
        try await configureVerifiedClient()

        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody(Data("tags=tags&title=name".utf8))
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", extension: "zip",
                                   tags: "tags", isNew: true,
                                   progress: 0, pagecount: 10, dateAdded: 1234)
        let actual = try? await service.updateArchive(archive: metadata).value
        XCTAssertNil(actual)
    }

    func testDatabaseStatsAllowsNullNamespace() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        [
          {
            "namespace": null,
            "text": "artbook",
            "weight": 3
          }
        ]
        """.utf8)

        stub(condition: isHost("localhost")
                && isPath("/api/database/stats")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.databaseStats().value
        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0].namespace, "")
        XCTAssertEqual(actual[0].text, "artbook")
        XCTAssertEqual(actual[0].weight, "3")
    }

    func testCheckJobStatusAllowsStringId() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        {
          "id": "7",
          "state": "finished",
          "task": "download_url",
          "result": {
            "success": 1,
            "url": "https://example.com/archive.zip",
            "title": "Archive Title",
            "message": "Done"
          }
        }
        """.utf8)

        stub(condition: isHost("localhost")
                && isPath("/api/minion/7/detail")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.checkJobStatus(id: 7).value
        XCTAssertEqual(actual.id, "7")
        XCTAssertEqual(actual.state, "finished")
        XCTAssertEqual(actual.task, "download_url")
        XCTAssertEqual(actual.result?.title, "Archive Title")
        XCTAssertEqual(actual.result?.message, "Done")
    }

    func testCheckBasicJobStatusDecodesPageThumbnailProgress() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        {
          "state": "active",
          "task": "generate_page_thumbnails",
          "notes": {
            "1": "processed",
            "3": "processed",
            "total_pages": 10
          },
          "error": ""
        }
        """.utf8)

        stub(condition: isHost("localhost")
                && isPath("/api/minion/9")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.checkBasicJobStatus(id: 9).value
        XCTAssertEqual(actual.state, "active")
        XCTAssertEqual(actual.task, "generate_page_thumbnails")
        XCTAssertEqual(actual.processedPages, Set([1, 3]))
        XCTAssertEqual(actual.error, "")
    }

    func testCheckJobStatusAllowsNumericId() async throws {
        try await configureVerifiedClient()

        let body = Data("""
        {
          "id": 7,
          "state": "finished",
          "task": "download_url",
          "result": {
            "success": 1,
            "url": "https://example.com/archive.zip",
            "title": "Archive Title",
            "message": "Done"
          }
        }
        """.utf8)

        stub(condition: isHost("localhost")
                && isPath("/api/minion/7/detail")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let actual = try await service.checkJobStatus(id: 7).value
        XCTAssertEqual(actual.id, "7")
        XCTAssertEqual(actual.state, "finished")
        XCTAssertEqual(actual.task, "download_url")
        XCTAssertEqual(actual.result?.title, "Archive Title")
        XCTAssertEqual(actual.result?.message, "Done")
    }

    private func configureVerifiedClient() async throws {
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ServerInfoResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        _ = try await service.verifyClient(url: url, apiKey: apiKey)
    }

}
// swiftlint:enable type_body_length
