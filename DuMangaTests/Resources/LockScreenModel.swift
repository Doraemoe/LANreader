//
//  LockScreenModel.swift
//  DuManga
//

import Foundation

@Observable
class LockScreenModel {
    var pin: String = ""
    var showPin = false
    var isDisabled = false
    var state = LockScreenState.normal

    @ObservationIgnored var disableBiometricsAuth = false
    @ObservationIgnored var isAuthenticating = false

    func switchToVerify() {
        state = .verify
        pin = ""
        isDisabled = false
    }

    func failed() {
        pin = ""
        isDisabled = false
    }

    func revertBackToNew() {
        state = .new
        pin = ""
        isDisabled = false
    }

    func unload() {
        pin = ""
        showPin = false
        isDisabled = false
        state = .normal
        disableBiometricsAuth = false
    }
}

enum LockScreenState: String, CaseIterable {
    case new
    case verify
    case normal
    case remove
}
