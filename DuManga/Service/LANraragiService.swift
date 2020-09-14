//
// Created on 9/9/20.
//

import Foundation
import Combine
import Alamofire
import AlamofireImage

class LANraragiService {
    private var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    private let authInterceptor = AuthInterceptor()
    private var session: Session
    private let imageDownloader: ImageDownloader

    init() {
        self.session = Session(interceptor: authInterceptor)
        let downloaderSession = Session(configuration: ImageDownloader.defaultURLSessionConfiguration(),
                startRequestsImmediately: false,
                interceptor: authInterceptor)
        self.imageDownloader = ImageDownloader(session: downloaderSession,
                downloadPrioritization: .fifo,
                maximumActiveDownloads: 4,
                imageCache: AutoPurgingImageCache())
        ImageResponseSerializer.addAcceptableImageContentTypes(["application/x-download"])
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

    func retrieveArchiveIndex() -> AnyPublisher<[ArchiveIndexResponse], AFError> {
        session.request("\(url)/api/archives")
                .validate()
                .publishDecodable(type: [ArchiveIndexResponse].self)
                .value()
    }

    func retrieveArchiveThumbnail(id: String) -> AnyPublisher<Image, AFIError> {
            let request = URLRequest(url: URL(string: "\(url)/api/archives/\(id)/thumbnail")!)
            return Future<Image, AFIError> { promise in
                self.imageDownloader.download(request) { response in
                    switch response.result {
                    case let .success(thumbnail):
                        promise(.success(thumbnail))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
    }

    func searchArchiveIndex(category: String? = nil,
                            filter: String? = nil,
                            start: String? = nil,
                            sortby: String? = nil,
                            order: String? = nil) -> AnyPublisher<ArchiveSearchResponse, AFError>{
        var query = [String: String]()
        if category != nil {
            query["category"] = category
        }
        if filter != nil {
            query["filter"] = filter
        }
        if start != nil {
            query["start"] = start
        }
        if sortby != nil {
            query["sortby"] = sortby
        }
        if order != nil {
            query["order"] = order
        }

        return session.request("\(url)/api/search", parameters: query)
                .validate()
                .publishDecodable(type: ArchiveSearchResponse.self)
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
