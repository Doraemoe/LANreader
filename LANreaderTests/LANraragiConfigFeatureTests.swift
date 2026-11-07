import XCTest
import Alamofire
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

@MainActor
final class LANraragiConfigFeatureTests: LANreaderTestCase {

    func testInsecureConnectionAlertExplainsTheFailureAndEndsVerifying() async {
        stub(condition: isHost("100.64.0.1") && isPath("/api/info")) { @Sendable _ in
            HTTPStubsResponse(error: URLError(.appTransportSecurityRequiresSecureConnection))
        }
        var state = LANraragiConfigFeature.State()
        state.formUrl = "http://100.64.0.1:3000"
        state.formKey = "apiKey"

        let store = TestStore(initialState: state) {
            LANraragiConfigFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.verifyServer) {
            $0.isVerifying = true
        }
        await store.receive(.showInsecureConnectionAlert) {
            $0.isVerifying = false
            $0.alert = AlertState {
                TextState("lanraragi.config.error.insecure.title")
            } message: {
                TextState("lanraragi.config.error.insecure.message")
            }
        }
    }

    // iOS rejects a plain HTTP Tailscale address before any connection is attempted, so this
    // exercises the real error the reducer branches on without contacting a server.
    func testRecognisesTheRealAppTransportSecurityRejection() async {
        allowRequestsWithoutStubs()
        do {
            _ = try await LANraragiService.shared.verifyClient(
                url: "http://100.64.0.1:3000",
                apiKey: "apiKey"
            )
            XCTFail("expected App Transport Security to reject a plain HTTP Tailscale address")
        } catch {
            XCTAssertTrue(
                LANraragiConfigFeature.isInsecureConnectionFailure(error),
                "the real rejection must be recognised, got \(error)"
            )
        }
    }

    func testTreatsOtherConnectionFailuresAsOrdinaryErrors() {
        let unreachable = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)

        XCTAssertFalse(LANraragiConfigFeature.isInsecureConnectionFailure(unreachable))
        XCTAssertFalse(
            LANraragiConfigFeature.isInsecureConnectionFailure(
                AFError.sessionTaskFailed(error: unreachable)
            )
        )
    }
}
