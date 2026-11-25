import XCTest
import SwiftUI
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

    @MainActor
    func testCustomSortExplanationWrapsVerticallyOnCompactPhoneWidth() async throws {
        let store = Store(initialState: ViewSettingsFeature.State()) {
            ViewSettingsFeature()
        }
        store.$searchSortCustom.withLock { $0 = "artist" }
        let zhLarge = try await measureCustomSortRow(store: store, locale: "zh-Hans", dynamicTypeSize: .large)
        let enLarge = try await measureCustomSortRow(store: store, locale: "en", dynamicTypeSize: .large)
        let zhLargeText = try await measureCustomSortRow(store: store, locale: "zh-Hans", dynamicTypeSize: .xxxLarge)

        XCTAssertGreaterThan(zhLarge.cellHeight, zhLarge.fieldHeight + 20)
        XCTAssertGreaterThan(enLarge.cellHeight, enLarge.fieldHeight + 20)
        XCTAssertGreaterThan(zhLargeText.cellHeight, zhLarge.cellHeight)
    }

    @MainActor
    private func measureCustomSortRow(
        store: StoreOf<ViewSettingsFeature>,
        locale: String,
        dynamicTypeSize: DynamicTypeSize
    ) async throws -> (cellHeight: CGFloat, fieldHeight: CGFloat) {
        let rootView = Form {
            Section(header: Text("settings.view")) {
                ViewSettings(store: store)
            }
        }
        .environment(\.locale, Locale(identifier: locale))
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        let controller = UIHostingController(rootView: rootView)
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        window.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        await waitUntil { findFirstSubview(of: UITextField.self, in: window) != nil }
        window.layoutIfNeeded()
        let textField = try XCTUnwrap(findFirstSubview(of: UITextField.self, in: window))
        let cell = try XCTUnwrap(enclosingCollectionCell(for: textField))
        return (cell.bounds.height, textField.bounds.height)
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
private func findFirstSubview<ViewType: UIView>(of type: ViewType.Type, in root: UIView) -> ViewType? {
    if let match = root as? ViewType {
        return match
    }
    for subview in root.subviews {
        if let match = findFirstSubview(of: type, in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private func enclosingCollectionCell(for view: UIView) -> UICollectionViewCell? {
    var current: UIView? = view.superview
    while let candidate = current {
        if let cell = candidate as? UICollectionViewCell {
            return cell
        }
        current = candidate.superview
    }
    return nil
}
