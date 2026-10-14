import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
import os
@testable import LANreader

final class CategoryFeatureTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set("apiKey", forKey: SettingsKey.lanraragiApiKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testFailedInitialLoadDismissesOverlayAndAllowsRefresh() async throws {
        let offline = OSAllocatedUnfairLock(initialState: true)
        stub(condition: isHost("localhost") && isPath("/api/categories")) { @Sendable request in
            XCTAssertEqual(request.httpMethod, "GET")
            if offline.withLock({ $0 }) {
                return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
            }
            return HTTPStubsResponse(jsonObject: [[
                "id": "SET_recovered", "name": "Recovered", "archives": [], "search": "", "pinned": "0"
            ]], statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        let state = CategoryFeature.State()
        state.$categoryItems.withLock { $0 = [] }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { CategoryFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }
        store.exhaustivity = .off
        await store.send(.loadCategory(true)) {
            $0.showLoading = true
        }
        await store.receive(\.setErrorMessage)
        XCTAssertFalse(store.state.showLoading)
        XCTAssertFalse(store.state.errorMessage.isEmpty)
        XCTAssertTrue(store.state.categoryItems.isEmpty)
        await store.send(.setErrorMessage("")) {
            $0.errorMessage = ""
        }
        offline.withLock { $0 = false }
        await store.send(.loadCategory(false))
        await store.receive(\.populateCategory)
        await store.finish()
        XCTAssertEqual(store.state.categoryItems.map(\.id), ["SET_recovered"])
        XCTAssertFalse(store.state.showLoading)
    }

    @MainActor
    func testClearingErrorMessagePreservesActiveLoad() async {
        var state = CategoryFeature.State()
        state.showLoading = true
        state.errorMessage = "Previous request failed"
        let store = TestStore(initialState: state) { CategoryFeature() }
        await store.send(.setErrorMessage("")) {
            $0.errorMessage = ""
        }
    }
}
