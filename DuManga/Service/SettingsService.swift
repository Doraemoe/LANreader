//
// Created on 10/9/20.
//

import Foundation
import Combine

class SettingsService {
    // server
    func saveLanrargiServer(url: String, apiKey: String) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
        return Just(true).eraseToAnyPublisher()
    }

    // tap
    func saveTapLeftControl(control: PageControl) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(control.rawValue, forKey: SettingsKey.tapLeftKey)
        return Just(true).eraseToAnyPublisher()
    }

    func saveTapMiddleControl(control: PageControl) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(control.rawValue, forKey: SettingsKey.tapMiddleKey)
        return Just(true).eraseToAnyPublisher()
    }

    func saveTapRightControl(control: PageControl) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(control.rawValue, forKey: SettingsKey.tapRightKey)
        return Just(true).eraseToAnyPublisher()
    }

    // swipe
    func saveSwipeLeftControl(control: PageControl) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(control.rawValue, forKey: SettingsKey.swipeLeftKey)
        return Just(true).eraseToAnyPublisher()
    }

    func saveSwipeRightControl(control: PageControl) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(control.rawValue, forKey: SettingsKey.swipeRightKey)
        return Just(true).eraseToAnyPublisher()
    }

    // split
    func saveSplitPage(split: Bool) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(split, forKey: SettingsKey.splitPage)
        return Just(true).eraseToAnyPublisher()
    }

    func saveSplitPagePriorityLeft(priorityLeft: Bool) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(priorityLeft, forKey: SettingsKey.splitPagePriorityLeft)
        return Just(true).eraseToAnyPublisher()
    }

    // view
    func saveArchiveListRandom(archiveListRandom: Bool) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(archiveListRandom, forKey: SettingsKey.archiveListRandom)
        return Just(true).eraseToAnyPublisher()
    }

    func saveUseListView(useListView: Bool) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(useListView, forKey: SettingsKey.useListView)
        return Just(true).eraseToAnyPublisher()
    }
}
