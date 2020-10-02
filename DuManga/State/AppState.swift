//
// Created on 9/9/20.
//

import Foundation
import Combine

struct AppState {
    var setting: SettingState
    var archive: ArchiveState
    var category: CategoryState

    init() {
        self.setting = SettingState()
        self.archive = ArchiveState()
        self.category = CategoryState()
    }
}

@propertyWrapper
class PublishedState<T: Equatable> {
    var wrappedValue: T {
        willSet {
            subject.send(newValue)
        }
    }

    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    private lazy var subject = CurrentValueSubject<T, Never>(wrappedValue)

    var projectedValue: AnyPublisher<T, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }
}
