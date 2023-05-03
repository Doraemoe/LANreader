//
// Created on 9/9/20.
//

import Foundation
import Combine

struct AppState {
    var setting: SettingState
    var archive: ArchiveState
    var category: CategoryState
    var page: PageState
    var trigger: TriggerState

    init() {
        setting = SettingState()
        archive = ArchiveState()
        category = CategoryState()
        page = PageState()
        trigger = TriggerState()
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
