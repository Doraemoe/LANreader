import XCTest
import UIKit
import ComposableArchitecture
@testable import LANreader

final class ViewSettingsFeatureTests: LANreaderTestCase {
    @MainActor
    func testPasscodeToggleOpensLockScreenOnlyWhenNoneIsShowing() async {
        let store = TestStore(initialState: ViewSettingsFeature.State()) {
            ViewSettingsFeature()
        }

        await store.send(.showLockScreen(true)) {
            $0.destination = .lockScreen(LockScreenFeature.State(lockState: .new))
        }
        await store.send(.showLockScreen(false))
    }

    @MainActor
    func testTurningPasscodeOffOpensLockScreenToRemoveIt() async {
        let store = TestStore(initialState: ViewSettingsFeature.State()) {
            ViewSettingsFeature()
        }

        await store.send(.showLockScreen(false)) {
            $0.destination = .lockScreen(LockScreenFeature.State(lockState: .remove))
        }
    }
}

final class SettingsFeatureTests: LANreaderTestCase {
    @MainActor
    func testTappingSettingsRowsPushesDestinationsOntoStack() async throws {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.serverConfigTapped) {
            $0.path.append(.serverConfig(LANraragiConfigFeature.State()))
        }
        let serverConfigID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.popFrom(id: serverConfigID))) {
            $0.path.removeAll()
        }

        await store.send(.uploadTapped) {
            $0.path.append(.upload(UploadFeature.State()))
        }
        let uploadID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.popFrom(id: uploadID))) {
            $0.path.removeAll()
        }

        await store.send(.translationTapped) {
            $0.path.append(.translation(TranslationConfigFeature.State()))
        }
        let translationID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.popFrom(id: translationID))) {
            $0.path.removeAll()
        }

        await store.send(.supportTapped) {
            $0.path.append(.support(SupportFeature.State()))
        }
        let supportID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.popFrom(id: supportID))) {
            $0.path.removeAll()
        }

        await store.send(.logTapped) {
            $0.path.append(.log(LogFeature.State()))
        }
        let logID = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.popFrom(id: logID))) {
            $0.path.removeAll()
        }
    }

    @MainActor
    func testSavingServerConfigDismissesFromSettingsPath() async throws {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.serverConfigTapped) {
            $0.path.append(.serverConfig(LANraragiConfigFeature.State()))
        }
        let id = try XCTUnwrap(store.state.path.ids.first)
        await store.send(.path(.element(id: id, action: .serverConfig(.saveComplate))))
        await store.receive(\.path.popFrom) {
            $0.path.removeAll()
        }
    }

    @MainActor
    func testSettingsNavigationControllerPushesAndPopsWithStore() async throws {
        let store = Store(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        let nav = makeSettingsNavigationController(store: store)
        nav.loadViewIfNeeded()

        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertTrue(nav.topViewController is SettingsHostingController<SettingsView>)
        XCTAssertEqual(nav.topViewController?.navigationItem.title, String(localized: "settings"))

        withUITransaction(\.uiKit.disablesAnimations, true) {
            _ = store.send(.serverConfigTapped)
        }
        await waitUntil { nav.viewControllers.count == 2 }
        XCTAssertEqual(nav.viewControllers.count, 2)
        XCTAssertTrue(nav.topViewController is SettingsHostingController<LANraragiConfigView>)

        let id = try XCTUnwrap(store.path.ids.first)
        withUITransaction(\.uiKit.disablesAnimations, true) {
            _ = store.send(.path(.element(id: id, action: .serverConfig(.saveComplate))))
        }
        await waitUntil { nav.viewControllers.count == 1 }
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertTrue(nav.topViewController is SettingsHostingController<SettingsView>)
        XCTAssertTrue(store.path.isEmpty)

        withUITransaction(\.uiKit.disablesAnimations, true) {
            _ = store.send(.supportTapped)
        }
        await waitUntil { nav.viewControllers.count == 2 }
        XCTAssertTrue(nav.topViewController is SettingsHostingController<SupportView>)
        XCTAssertEqual(nav.topViewController?.navigationItem.title, String(localized: "settings.support"))
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
