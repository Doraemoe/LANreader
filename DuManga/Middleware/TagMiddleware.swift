import Foundation
import Combine
import Logging

private let logger = Logger(label: "TagMiddleware")

func tagMiddleware(database: AppDatabase) -> Middleware<AppState, AppAction> {
    { _, action in
        switch action {
        case .archive(action: .finishFetchArchive):
            Task.detached(priority: .background) {
                try? await Task.sleep(for: .seconds(10))
                _ = try? database.deleteAllTag()
                let archives = try? database.readAllArchive()
                archives?.forEach { archive in
                    archive.tags.forEach { tag in
                        var tagItem = TagItem(tag: tag)
                        try? database.saveTag(tagItem: &tagItem)
                    }
                }
            }
        case let .archive(action: .updateArchive(archive)):
            Task.detached(priority: .background) {
                try? await Task.sleep(for: .seconds(10))
                let tagList = archive.tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                tagList.forEach { tag in
                    var tagItem = TagItem(tag: tag)
                    try? database.saveTag(tagItem: &tagItem)
                }
            }
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}
