import GRDB
import GRDBQuery
import Combine
import SwiftUI

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue = AppDatabase.shared
}

extension EnvironmentValues {
    var appDatabase: AppDatabase {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

extension Query where Request.DatabaseContext == AppDatabase {
    init(_ request: Request) {
        self.init(request, in: \.appDatabase)
    }
}

struct ArchiveThumbnailRequest: Queryable {
    static var defaultValue: ArchiveThumbnail? { nil }

    var id: String

    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<ArchiveThumbnail?, Error> {
        ValueObservation
            .tracking(ArchiveThumbnail.filter(id: id).fetchOne)
            .publisher(in: appDatabase.dbReader, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

struct ArchiveImageRequest: Queryable {
    static var defaultValue: ArchiveImage? { nil }

    var id: String

    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<ArchiveImage?, Error> {
        ValueObservation
            .tracking(ArchiveImage.filter(id: id).fetchOne)
            .publisher(in: appDatabase.dbReader, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
