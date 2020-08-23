//
//  LANRaragiClientTest.swift
//  DuMangaTests
//
//  Created by Jin Yifan on 22/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

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
}
