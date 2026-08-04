import XCTest
import Alamofire
import ComposableArchitecture
@testable import LANreader

@MainActor
final class LANraragiConfigFeatureTests: XCTestCase {

    func testInsecureConnectionAlertExplainsTheFailureAndEndsVerifying() async {
        var state = LANraragiConfigFeature.State()
        state.isVerifying = true

        let store = TestStore(initialState: state) {
            LANraragiConfigFeature()
        }

        await store.send(.showInsecureConnectionAlert) {
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
