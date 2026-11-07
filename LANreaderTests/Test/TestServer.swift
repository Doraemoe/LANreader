import Foundation
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

/// The stubbed LANraragi server that tests talk to.
enum TestServer {
    /// Tests run against a current server by default: one new enough for every API path and feature
    /// the app uses, including `GET /files` extraction, chapter editing and stamps.
    static let currentVersion = "0.9.80"
    /// An older server, for tests of the fallback paths the app still supports.
    static let legacyVersion = "0.9.30"
    static let url = "https://localhost"
    static let apiKey = "apiKey"
}

/// Points the shared service at the stub server and verifies it. Verification is what sets the API
/// paths and feature support the app derives from the server version.
@discardableResult
func configureTestServer(version: String = TestServer.currentVersion) async throws -> LANraragiService {
    UserDefaults.standard.set(TestServer.url, forKey: SettingsKey.lanraragiUrl)
    UserDefaults.standard.set(TestServer.apiKey, forKey: SettingsKey.lanraragiApiKey)
    let body = Data("""
    {
      "archives_per_page": 100,
      "debug_mode": false,
      "has_password": true,
      "motd": "",
      "name": "LANraragi",
      "nofun_mode": false,
      "server_tracks_progress": true,
      "version": "\(version)",
      "version_name": "Test"
    }
    """.utf8)
    stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
        HTTPStubsResponse(data: body, statusCode: 200, headers: ["Content-Type": "application/json"])
    }
    let service = LANraragiService.shared
    _ = try await service.verifyClient(url: TestServer.url, apiKey: TestServer.apiKey)
    return service
}
