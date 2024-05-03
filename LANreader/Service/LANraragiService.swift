//
// Created on 9/9/20.
//

import Foundation
import Alamofire
import Logging
import Dependencies

class LANraragiService {
    public static let downloadPath = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    .appendingPathComponent("current session", conformingTo: .folder)

    public static let thumbnailPath = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: .picturesDirectory,
        create: true
    )
    .appendingPathComponent("thumbnail", conformingTo: .folder)

    private static let logger = Logger(label: "LANraragiService")

    private static var _shared: LANraragiService?

    private var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    private let authInterceptor = AuthInterceptor()
    private var session: Session
    private var prefetchSession: Session
    private let snakeCaseEncoder: JSONDecoder

    private init() {
        self.session = Session(interceptor: authInterceptor)
        self.prefetchSession = Session(interceptor: authInterceptor)
        self.snakeCaseEncoder = JSONDecoder()
        self.snakeCaseEncoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func verifyClient(url: String, apiKey: String) async -> DataTask<ServerInfo> {
        self.url = url
        self.authInterceptor.updateApiKey(apiKey)
        let cacher = ResponseCacher(behavior: .doNotCache)
        return session.request("\(self.url)/api/info")
            .cacheResponse(using: cacher)
            .validate(statusCode: 200...200)
            .serializingDecodable(ServerInfo.self, decoder: self.snakeCaseEncoder)
    }

    func retrieveArchiveIndex() async -> DataTask<[ArchiveIndexResponse]> {
        session.request("\(url)/api/archives") { $0.timeoutInterval = 240 }
            .validate()
            .serializingDecodable([ArchiveIndexResponse].self)
    }

    func retrieveArchiveMetadata(id: String) -> DataTask<ArchiveIndexResponse> {
        session.request("\(url)/api/archives/\(id)/metadata")
            .validate()
            .serializingDecodable(ArchiveIndexResponse.self)
    }

    func retrieveArchiveThumbnail(id: String) -> DownloadRequest {
        let request = URLRequest(url: URL(string: "\(url)/api/archives/\(id)/thumbnail")!)
        return session.download(request, to: { tempUrl, response in
            let destinationUrl = LANraragiService.downloadPath?
                .appendingPathComponent("thumbnail", conformingTo: .folder)
                .appendingPathComponent(response.suggestedFilename ?? "\(id).jpeg", conformingTo: .image)
            ?? tempUrl
            return (destinationUrl, [.createIntermediateDirectories, .removePreviousFile])
        }).validate()
    }

    func updateArchiveThumbnail(id: String, page: Int) -> DataTask<String> {
        let query = ["page": page]
        return session.request("\(url)/api/archives/\(id)/thumbnail", method: .put, parameters: query)
            .validate(statusCode: 200...200)
            .serializingString()
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

    func randomArchives() async -> DataTask<ArchiveRandomResponse> {
        let query = ["count": 100]
        return session.request("\(url)/api/search/random", method: .get, parameters: query)
            .validate(statusCode: 200...200)
            .serializingDecodable(ArchiveRandomResponse.self)
    }

    func retrieveCategories() async -> DataTask<[ArchiveCategoriesResponse]> {
        session.request("\(url)/api/categories")
            .validate()
            .serializingDecodable([ArchiveCategoriesResponse].self)
    }

    func addCategory(name: String, search: String) async -> DataTask<GenericSuccessResponse> {
        var query = [String: String]()
        query["name"] = name
        if !search.isEmpty {
            query["search"] = search
        }
        return session.request("\(url)/api/categories", method: .put, parameters: query)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)
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

    func addArchiveToCategory(categoryId: String, archiveId: String) async -> DataTask<GenericSuccessResponse> {
        session.request("\(url)/api/categories/\(categoryId)/\(archiveId)", method: .put)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)
    }

    func removeArchiveFromCategory(categoryId: String, archiveId: String) async -> DataTask<GenericSuccessResponse> {
        session.request("\(url)/api/categories/\(categoryId)/\(archiveId)", method: .delete)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)
    }

    func extractArchive(id: String) async -> DataTask<ArchiveExtractResponse> {
        session.request("\(url)/api/archives/\(id)/extract", method: .post)
            .validate()
            .serializingDecodable(ArchiveExtractResponse.self)
    }

    func fetchArchivePage(page: String) -> DownloadRequest {
        let request = URLRequest(url: URL(string: "\(url)/\(page)")!)
        return session.download(request, to: { tempUrl, response in
            let id = String(page.split(separator: "/")[2])
            let destinationUrl = LANraragiService.downloadPath?
                .appendingPathComponent(id, conformingTo: .folder)
                .appendingPathComponent(response.suggestedFilename!, conformingTo: .image)
            ?? tempUrl
            return (destinationUrl, [.createIntermediateDirectories, .removePreviousFile])
        }).validate()
    }

    func prefetchArchivePage(page: String) -> DownloadRequest {
        let request = URLRequest(url: URL(string: "\(url)/\(page)")!)
        return prefetchSession.download(request, to: { tempUrl, response in
            let id = String(page.split(separator: "/")[2])
            let destinationUrl = LANraragiService.downloadPath?
                .appendingPathComponent(id, conformingTo: .folder)
                .appendingPathComponent(response.suggestedFilename!, conformingTo: .image)
            ?? tempUrl
            return (destinationUrl, [.createIntermediateDirectories, .removePreviousFile])
        })
    }

    func clearNewFlag(id: String) -> DataTask<String> {
        session.request("\(url)/api/archives/\(id)/isnew", method: .delete)
            .validate(statusCode: 200...200)
            .serializingString()
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

    func deleteArchive(id: String) async -> DataTask<GenericSuccessResponse> {
        session.request("\(url)/api/archives/\(id)", method: .delete)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)

    }

    func queueUrlDownload(downloadUrl: String) async -> DataTask<QueueUrlDownloadResponse> {
        let query = ["url": downloadUrl]
        return session.request("\(url)/api/download_url", method: .post, parameters: query)
            .validate(statusCode: 200...200)
            .serializingDecodable(QueueUrlDownloadResponse.self)
    }

    func checkJobStatus(id: Int) async -> DataTask<JobStatus> {
        session.request("\(url)/api/minion/\(id)/detail", method: .get)
                .validate(statusCode: 200...200)
                .serializingDecodable(JobStatus.self)
    }

    func databaseBackup() async -> DataTask<DatabaseBackup> {
        session.request("\(url)/api/database/backup", method: .get)
            .validate(statusCode: 200...200)
            .serializingDecodable(DatabaseBackup.self)
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

extension LANraragiService: DependencyKey {
    static let liveValue = LANraragiService.shared
    static let testValue = LANraragiService.shared
}

extension DependencyValues {
  var lanraragiService: LANraragiService {
    get { self[LANraragiService.self] }
    set { self[LANraragiService.self] = newValue }
  }
}
