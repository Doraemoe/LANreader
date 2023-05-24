import Foundation

enum TriggerAction {
    case thumbnailRefreshAction(id: String)
    case pageRefreshAction(id: String)
    case archiveDeleteAction(id: String)
}
