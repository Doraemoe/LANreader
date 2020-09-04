//  Created 22/8/20.

import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import DuManga

class LANRaragiClientTest: XCTestCase {
    
    let url = "https://localhost"
    let apiKey = "apiKey"
    
    override func tearDownWithError() throws {
        HTTPStubs.removeAllStubs()
    }
    
    func testHealthCheck() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
            fileAtPath: OHPathForFile("ServerInfoResponse.json", type(of: self))!, statusCode: 200, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testHealthCheck")
        client.healthCheck { healthy in
            XCTAssertTrue(healthy)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testHealthCheckFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
                jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testHealthCheckFailure")
        client.healthCheck() { healthy in
            XCTAssertFalse(healthy)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testGetArchiveIndex() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
            fileAtPath: OHPathForFile("ArchiveIndexResponse.json", type(of: self))!, statusCode: 200, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveIndex")
        client.getArchiveIndex() { (res: [ArchiveIndexResponse]?) in
            XCTAssertNotNil(res)
            XCTAssertEqual(res?.count, 1)
            XCTAssertEqual(res?[0].arcid, "abcd1234")
            XCTAssertEqual(res?[0].isnew, "false")
            XCTAssertEqual(res?[0].tags, "artist:abc, language:def, parody:ghi, category:jkl")
            XCTAssertEqual(res?[0].title, "title")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchiveIndexFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
                jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveIndexFailure")
        client.getArchiveIndex() { (res: [ArchiveIndexResponse]?) in
            XCTAssertNil(res)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchiveMetadata() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/id/metadata")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
            fileAtPath: OHPathForFile("ArchiveMetadataResponse.json", type(of: self))!, statusCode: 200, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveMetadata")
        client.getArchiveMetadata(id: "id") { (res: ArchiveIndexResponse?) in
            XCTAssertNotNil(res)
            XCTAssertEqual(res?.arcid, "abcd1234")
            XCTAssertEqual(res?.isnew, "false")
            XCTAssertEqual(res?.tags, "artist:abc, language:def, parody:ghi, category:jkl")
            XCTAssertEqual(res?.title, "title")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchiveMetadataFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/id/metadata")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
                jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveMetadataFailure")
        client.getArchiveMetadata(id: "id") { (res: ArchiveIndexResponse?) in
            XCTAssertNil(res)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchiveThumbnail() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/1/thumbnail")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(
                    fileAtPath: OHPathForFile("placeholder.jpg", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type":"application/x-download;name=\"placeholder.jpg\""])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveThumbnail")
        client.getArchiveThumbnail(id: "1", completionHandler: { (res: UIImage?) in
            XCTAssertNotNil(res)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchiveThumbnailFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/1/thumbnail")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveThumbnail")
        client.getArchiveThumbnail(id: "1", completionHandler: { (res: UIImage?) in
            XCTAssertNil(res)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testExtractArchive() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/1/extract")
            && isMethodPOST()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(
                    fileAtPath: OHPathForFile("ArchiveExtractResponse.json", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testExtractArchive")
        client.postArchiveExtract(id: "1", completionHandler: { (res: ArchiveExtractResponse?) in
            XCTAssertNotNil(res)
            XCTAssertEqual(res?.pages.count, 1)
            XCTAssertEqual(res?.pages[0], "./api/archives/abc123/page?path=def456/001.jpg")
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testExtractArchiveFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/1/extract")
            && isMethodPOST()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testExtractArchiveFailure")
        client.postArchiveExtract(id: "1", completionHandler: { (res: ArchiveExtractResponse?) in
            XCTAssertNil(res)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchivePage() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/abc123/page")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(
                    fileAtPath: OHPathForFile("placeholder.jpg", type(of: self))!, statusCode: 200,
                    headers: ["Content-Type":"application/x-download;name=\"placeholder.jpg\""])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchivePage")
        client.getArchivePage(page: "api/archives/abc123/page", completionHandler: { (res: UIImage?) in
            XCTAssertNotNil(res)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetArchivePageFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/archives/abc123/page")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
                return HTTPStubsResponse(jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetArchiveThumbnail")
        client.getArchivePage(page: "api/archives/abc123/page", completionHandler: { (res: UIImage?) in
            XCTAssertNil(res)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetCategories() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/categories")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
            fileAtPath: OHPathForFile("ArchiveCategoriesResponse.json", type(of: self))!, statusCode: 200, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetCategories")
        client.getCategories() { (res: [ArchiveCategoriesResponse]?) in
            XCTAssertNotNil(res)
            XCTAssertEqual(res?.count, 2)
            XCTAssertEqual(res?[0].archives.count, 5)
            XCTAssertEqual(res?[0].id, "SET_1234567")
            XCTAssertEqual(res?[0].last_used, "12345678")
            XCTAssertEqual(res?[0].name, "static")
            XCTAssertEqual(res?[0].pinned, "0")
            XCTAssertEqual(res?[0].search, "")
            
            XCTAssertEqual(res?[1].archives.count, 0)
            XCTAssertEqual(res?[1].id, "SET_0987654")
            XCTAssertEqual(res?[1].last_used, "098765432")
            XCTAssertEqual(res?[1].name, "dynamic")
            XCTAssertEqual(res?[1].pinned, "0")
            XCTAssertEqual(res?[1].search, "keyword")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetCategoriesFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/categories")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
                jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testGetCategoriesFailure")
        client.getCategories() { (res: [ArchiveCategoriesResponse]?) in
            XCTAssertNil(res)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSearchArchiveIndex() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/search")
            && containsQueryParams(["category": "SET_12345678"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
            fileAtPath: OHPathForFile("ArchiveSearchResponse.json", type(of: self))!, statusCode: 200, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testSearchArchiveIndex")
        client.searchArchiveIndex(category: "SET_12345678") { (res: ArchiveSearchResponse?) in
            XCTAssertNotNil(res)
            XCTAssertEqual(res?.data.count, 1)
            XCTAssertEqual(res?.draw, 0)
            XCTAssertEqual(res?.recordsFiltered, 1)
            XCTAssertEqual(res?.recordsTotal, 1234)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSearchArchiveIndexFailure() throws {
        stub(condition: isHost("localhost")
            && isPath("/api/search")
            && containsQueryParams(["category": "SET_12345678"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
            return HTTPStubsResponse(
                jsonObject: ["error": "This API is protected and requires login or an API Key."], statusCode: 401, headers: ["Content-Type":"application/json"])
        }
        
        let client = LANRaragiClient(url: url, apiKey: apiKey)
        
        let expectation = XCTestExpectation(description: "testSearchArchiveIndexFailure")
        client.searchArchiveIndex(category: "SET_12345678") { (res: ArchiveSearchResponse?) in
            XCTAssertNil(res)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

}
