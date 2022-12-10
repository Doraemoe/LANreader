//
//  LockScreenModel.swift
//  DuManga
//

import Foundation

class LockScreenModel: ObservableObject {
    @Published var pin: String = ""
    @Published var showPin = false
    @Published var isDisabled = false
    @Published var state = LockScreenState.normal

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
    }
}

enum LockScreenState: String, CaseIterable {
    case new
    case verify
    case normal
    case remove
}
