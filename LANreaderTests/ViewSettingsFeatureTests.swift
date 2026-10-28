import XCTest
import ComposableArchitecture
@testable import LANreader

final class ViewSettingsFeatureTests: XCTestCase {
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
