//
// Created on 9/9/20.
//

import Foundation

enum AppAction {
    case archive(action: ArchiveAction)
    case category(action: CategoryAction)
    case page(action: PageAction)
    case trigger(action: TriggerAction)
    case noop
}
