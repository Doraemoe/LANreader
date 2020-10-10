//
// Created on 7/10/20.
//

import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
import CombineExpectations
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

    func testGetServerInfo() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ServerInfoResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.verifyClient(url: url, apiKey: apiKey)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        let expected = try FileUtils.readJsonFile(filename: "ServerInfoResponse")
        XCTAssertEqual(actual, expected)
    }

    func testGetServerInfoUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.verifyClient(url: url, apiKey: apiKey)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        let expected = try FileUtils.readJsonFile(filename: "UnauthorizedResponse")
        XCTAssertEqual(actual, expected)
    }

    func testRetrieveArchiveIndex() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveIndexResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.retrieveArchiveIndex()
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0].arcid, "abcd1234")
        XCTAssertEqual(actual[0].isnew, "false")
        XCTAssertEqual(actual[0].tags, "artist:abc, language:def, parody:ghi, category:jkl")
        XCTAssertEqual(actual[0].title, "title")
    }

    func testRetrieveArchiveIndexUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.retrieveArchiveIndex()
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testRetrieveArchiveThumbnail() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/thumbnail")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("placeholder.jpg", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type": "application/x-download;name=\"placeholder.jpg\""])
        }

        let publisher = service.retrieveArchiveThumbnail(id: "1")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        XCTAssertNotNil(actual)
    }

    func testRetrieveArchiveThumbnailUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/thumbnail")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.retrieveArchiveThumbnail(id: "1")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testSearchArchiveIndex() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/search")
                && containsQueryParams(["category": "SET_12345678"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveSearchResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.searchArchiveIndex(category: "SET_12345678")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.data.count, 1)
        XCTAssertEqual(actual.draw, 0)
        XCTAssertEqual(actual.recordsFiltered, 1)
        XCTAssertEqual(actual.recordsTotal, 1234)
    }

    func testSearchArchiveIndexUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/search")
                && containsQueryParams(["category": "SET_12345678"])
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.searchArchiveIndex(category: "SET_12345678")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testRetrieveCategories() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/categories")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveCategoriesResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.retrieveCategories()
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
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

    func testRetrieveCategoriesUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/categories")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.retrieveCategories()
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testUpdateDynamicCategory() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/categories/SET_12345678")
                && isMethodPUT()
                && hasBody("name=name&pinned=0&search=search".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UpdateSearchCategoryResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let item = CategoryItem(id: "SET_12345678", name: "name", archives: [], search: "search", pinned: "0")

        let publisher = service.updateDynamicCategory(item: item)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        let expected = try FileUtils.readJsonFile(filename: "UpdateSearchCategoryResponse")
        XCTAssertEqual(actual, expected)
    }

    func testUpdateDynamicCategoryUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/categories/SET_12345678")
                && isMethodPUT()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let item = CategoryItem(id: "SET_12345678", name: "name", archives: [], search: "search", pinned: "0")

        let publisher = service.updateDynamicCategory(item: item)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testExtractArchive() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/extract")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveExtractResponse.json", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type": "application/json"])
        }

        let publisher = service.extractArchive(id: "1")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual.pages.count, 1)
        XCTAssertEqual(actual.pages[0], "./api/archives/abc123/page?path=def456/001.jpg")
    }

    func testExtractArchiveUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/1/extract")
                && isMethodPOST()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.extractArchive(id: "1")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testFetchArchivePage() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/abc123/page")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("placeholder.jpg", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type": "application/x-download;name=\"placeholder.jpg\""])
        }

        let publisher = service.fetchArchivePage(page: "api/archives/abc123/page")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        XCTAssertNotNil(actual)
    }

    func testFetchArchivePageUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/abc123/page")
                && isMethodGET()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.fetchArchivePage(page: "api/archives/abc123/page")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testClearNewFlag() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/isnew")
                && isMethodDELETE()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ClearNewFlagResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.clearNewFlag(id: "id")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        let expected = try FileUtils.readJsonFile(filename: "ClearNewFlagResponse")
        XCTAssertEqual(actual, expected)
    }

    func testClearNewFlagUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/isnew")
                && isMethodDELETE()
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let publisher = service.clearNewFlag(id: "id")
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

    func testUpdateArchiveMetadata() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody("tags=tags&title=name".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("SetArchiveMetadataResponse.json", type(of: self))!,
                    statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder"))
        let publisher = service.updateArchiveMetaData(archiveMetadata: metadata)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.single, timeout: 1.0)
        let expected = try FileUtils.readJsonFile(filename: "SetArchiveMetadataResponse")
        XCTAssertEqual(actual, expected)
    }

    func testUpdateArchiveMetadataUnauthorized() throws {
        stub(condition: isHost("localhost")
                && isPath("/api/archives/id/metadata")
                && isMethodPUT()
                && hasBody("tags=tags&title=name".data(using: .utf8)!)
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
            HTTPStubsResponse(
                    fileAtPath: OHPathForFile("UnauthorizedResponse.json", type(of: self))!,
                    statusCode: 401, headers: ["Content-Type": "application/json"])
        }

        let metadata = ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder"))
        let publisher = service.updateArchiveMetaData(archiveMetadata: metadata)
        let recorder = publisher.record()
        let actual = try wait(for: recorder.completion, timeout: 1.0)
        if case .finished = actual {
            XCTFail("Should not success")
        }
    }

}
