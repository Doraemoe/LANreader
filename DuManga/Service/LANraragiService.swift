//
// Created on 9/9/20.
//

import Foundation
import Combine
import Alamofire
import Logging

class LANraragiService {
    private static let logger = Logger(label: "LANraragiService")

    private static var _shared: LANraragiService?

    private var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    private let authInterceptor = AuthInterceptor()
    private var session: Session

    private init() {
        self.session = Session(interceptor: authInterceptor)
    }

    func verifyClient(url: String, apiKey: String) async -> DataTask<String> {
        self.url = url
        self.authInterceptor.updateApiKey(apiKey)
        let cacher = ResponseCacher(behavior: .doNotCache)
        return session.request("\(self.url)/api/info")
            .cacheResponse(using: cacher)
            .validate(statusCode: 200...200)
            .serializingString()
    }

    func retrieveArchiveIndex() async -> DataTask<[ArchiveIndexResponse]> {
        session.request("\(url)/api/archives")
            .validate()
            .serializingDecodable([ArchiveIndexResponse].self)
    }

    func retrieveArchiveThumbnail(id: String) -> DownloadRequest {
        let request = URLRequest(url: URL(string: "\(url)/api/archives/\(id)/thumbnail")!)
        return session.download(request)
    }

    func searchArchive(category: String? = nil,
                       filter: String? = nil,
                       start: String = "-1",
                       sortby: String = "title",
                       order: String = "asc") async -> DataTask<ArchiveSearchResponse> {
        var query = [String: String]()
        if category != nil {
            query["category"] = category
        }
        if filter != nil {
            query["filter"] = filter
        }
        query["start"] = start
        query["sortby"] = sortby
        query["order"] = order

        return session.request("\(url)/api/search", parameters: query)
            .validate()
            .serializingDecodable(ArchiveSearchResponse.self)
    }

    func retrieveCategories() async -> DataTask<[ArchiveCategoriesResponse]> {
        session.request("\(url)/api/categories")
            .validate()
            .serializingDecodable([ArchiveCategoriesResponse].self)
    }

    func updateDynamicCategory(item: CategoryItem) async -> DataTask<String> {
        var query = [String: String]()
        query["name"] = item.name
        query["search"] = item.search
        query["pinned"] = item.pinned
        return session.request("\(url)/api/categories/\(item.id)", method: .put, parameters: query)
            .validate(statusCode: 200...200)
            .serializingString()
    }

    func extractArchive(id: String) async -> DataTask<ArchiveExtractResponse> {
        session.request("\(url)/api/archives/\(id)/extract", method: .post)
            .validate()
            .serializingDecodable(ArchiveExtractResponse.self)
    }

    func fetchArchivePageData(page: String) -> AnyPublisher<Data, AFError> {
        let request = URLRequest(url: URL(string: "\(url)/\(page)")!)
        return session.download(request)
            .validate()
            .publishData()
            .value()
            .mapError { error in
                LANraragiService.logger.error("failed to fetch archive page data: \(error)")
                return error
            }
            .eraseToAnyPublisher()
    }

    func fetchArchivePage(page: String) -> DownloadRequest {
        let request = URLRequest(url: URL(string: "\(url)/\(page)")!)
        return session.download(request)
    }

    func clearNewFlag(id: String) -> AnyPublisher<String, AFError> {
        session.request("\(url)/api/archives/\(id)/isnew", method: .delete)
            .validate(statusCode: 200...200)
            .publishString()
            .value()
    }

    func updateArchive(archive: ArchiveItem) async -> DataTask<String> {
        var query = [String: String]()
        query["title"] = archive.name
        query["tags"] = archive.tags

        return session.request("\(url)/api/archives/\(archive.id)/metadata",
                               method: .put, parameters: query)
        .validate(statusCode: 200...200)
        .serializingString()
    }

    func updateArchiveReadProgress(id: String, progress: Int) async -> DataTask<String> {
        session.request("\(url)/api/archives/\(id)/progress/\(progress)", method: .put)
            .validate(statusCode: 200...200)
            .serializingString()
    }

    func deleteArchive(id: String) async -> DataTask<ArchiveDeleteResponse> {
        session.request("\(url)/api/archives/\(id)", method: .delete)
            .validate(statusCode: 200...200)
            .serializingDecodable(ArchiveDeleteResponse.self)

    }

    public static var shared: LANraragiService {
        if _shared == nil {
            _shared = LANraragiService()
        }
        return _shared!
    }

    static func resetService() {
        _shared = nil
    }
}

class AuthInterceptor: RequestInterceptor {

    private var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""

    func updateApiKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func adapt(_ urlRequest: URLRequest,
               for session: Session,
               completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var modifiedURLRequest = urlRequest
        modifiedURLRequest.headers.add(.authorization(bearerToken: apiKey.data(using: .utf8)!.base64EncodedString()))
        completion(.success(modifiedURLRequest))
    }
}
