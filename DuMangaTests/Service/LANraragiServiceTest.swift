//
// Created on 7/10/20.
//

import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
@testable import DuManga

class LANraragiServiceTest: XCTestCase {

    private let url = "https://localhost"
    private let apiKey = "apiKey"

    private var service: LANraragiService!

    override func setUpWithError() throws {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
        LANraragiService.resetService()
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

        let actual = try await service.verifyClient(url: url, apiKey: apiKey).value
        XCTAssertEqual(actual.archivesPerPage, "100")
        XCTAssertEqual(actual.debugMode, "0")
        XCTAssertEqual(actual.hasPassword, "1")
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

        let actual = try? await service.verifyClient(url: url, apiKey: apiKey).value
        XCTAssertNil(actual)
    }

    func testRetrieveArchiveIndex() async throws {
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

    func testSearchArchive() async throws {
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

    func testUpdateDynamicCategory() async throws {
        stub(condition: isHost("localhost")
                && isPath("/api/categories/SET_12345678")
                && isMethodPUT()
                && hasBody("name=name&pinned=0&search=search".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UpdateSearchCategoryResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let item = CategoryItem(id: "SET_12345678", name: "name", archives: [],
                                search: "search", pinned: "0")

        let actual = try await service.updateDynamicCategory(item: item).value
        let expected = try FileUtils.readJsonFile(filename: "UpdateSearchCategoryResponse")
        XCTAssertEqual(actual, expected)
    }

    func testUpdateDynamicCategoryUnauthorized() async throws {
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

        let actual = try? await service.updateDynamicCategory(item: item).value
        XCTAssertNil(actual)
    }

    func testExtractArchive() async throws {
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
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody("tags=tags&title=name".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("SetArchiveMetadataResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", normalizedName: "normalName",
                                   tags: "tags", isNew: true,
                                   progress: 0, pagecount: 10, dateAdded: 1234)
        let actual = try await service.updateArchive(archive: metadata).value
        let expected = try FileUtils.readJsonFile(filename: "SetArchiveMetadataResponse")
        XCTAssertEqual(actual, expected)
    }

    func testUpdateArchiveMetadataUnauthorized() async throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody("tags=tags&title=name".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", normalizedName: "normalName",
                                   tags: "tags", isNew: true,
                                   progress: 0, pagecount: 10, dateAdded: 1234)
        let actual = try? await service.updateArchive(archive: metadata).value
        XCTAssertNil(actual)
    }

}
