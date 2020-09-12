//
// Created on 9/9/20.
//

import Foundation
import Combine
import Alamofire

class LANraragiService {
    private var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    private let authInterceptor = AuthInterceptor()
    private var session: Session

    init() {
        self.session = Session(interceptor: authInterceptor)
    }

    func verifyClient(url: String, apiKey: String) -> AnyPublisher<String, AFError> {
        self.url = url
        self.authInterceptor.updateApiKey(apiKey)
        let cacher = ResponseCacher(behavior: .doNotCache)
        return session.request("\(self.url)/api/info")
                .cacheResponse(using: cacher)
                .validate(statusCode: 200...500)
                .publishString()
                .value()
    }

    func retrieveCategories() -> AnyPublisher<[ArchiveCategoriesResponse], AFError> {
        session.request("\(self.url)/api/categories")
                .validate()
                .publishDecodable(type: [ArchiveCategoriesResponse].self)
                .value()
    }

    func updateDynamicCategory(item: CategoryItem) -> AnyPublisher<String, AFError> {
        var query = [String: String]()
        query["name"] = item.name
        query["search"] = item.search
        query["pinned"] = item.pinned
        return session.request("\(url)/api/categories/\(item.id)", method: .put, parameters: query)
                .validate(statusCode: 200...200)
                .publishString()
                .value()
    }
}

class AuthInterceptor: RequestInterceptor {

    private var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""

    func updateApiKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var modifiedURLRequest = urlRequest
        modifiedURLRequest.headers.add(.authorization(bearerToken: apiKey.data(using: .utf8)!.base64EncodedString()))
        completion(.success(modifiedURLRequest))
    }
}
