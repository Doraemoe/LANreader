import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
import XCTest

/// Base class for every test in the suite.
///
/// A request that no stub answers fails the test instead of silently reaching the network, and the
/// app's settings are restored afterwards so values a test writes can't leak into later tests or into
/// the app on that simulator.
class LANreaderTestCase: XCTestCase {
    private var savedSettings: [String: Any]?
    private var unmatchedRequests: UnmatchedRequests?
    private var unmatchedRequestStub: HTTPStubsDescriptor?

    override func setUp() async throws {
        try await super.setUp()
        savedSettings = UserDefaults.standard.persistentDomain(forName: Self.settingsDomain)
        HTTPStubs.removeAllStubs()
        let unmatchedRequests = UnmatchedRequests()
        self.unmatchedRequests = unmatchedRequests
        // Added first, so every stub a test adds later is matched before this one.
        unmatchedRequestStub = stub(condition: { @Sendable _ in true }) { @Sendable request in
            unmatchedRequests.append(request)
            return HTTPStubsResponse(error: URLError(.cannotConnectToHost))
        }
    }

    override func tearDown() async throws {
        HTTPStubs.removeAllStubs()
        for request in unmatchedRequests?.all ?? [] {
            XCTFail("Request had no stub: \(request)")
        }
        if let savedSettings {
            UserDefaults.standard.setPersistentDomain(savedSettings, forName: Self.settingsDomain)
        } else {
            UserDefaults.standard.removePersistentDomain(forName: Self.settingsDomain)
        }
        try await super.tearDown()
    }

    /// For a test that has to go through the real URL loading system, such as one checking how
    /// App Transport Security rejects a plain HTTP server.
    func allowRequestsWithoutStubs() {
        if let unmatchedRequestStub {
            HTTPStubs.removeStub(unmatchedRequestStub)
        }
    }

    private static var settingsDomain: String {
        Bundle.main.bundleIdentifier ?? "com.jif.LANreader.3"
    }
}

private final class UnmatchedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String] = []

    var all: [String] {
        lock.withLock { requests }
    }

    func append(_ request: URLRequest) {
        let description = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<no URL>")"
        lock.withLock { requests.append(description) }
    }
}
