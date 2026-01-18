//
// Created on 9/9/20.
//

import Foundation
import Alamofire
import Logging
import Dependencies

actor LANraragiService {
    public static let downloadPath = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    .appendingPathComponent("current session", conformingTo: .folder)

    public static let cachePath = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: .picturesDirectory,
        create: true
    )
    .appendingPathComponent("cached", conformingTo: .folder)

    private static let logger = Logger(label: "LANraragiService")

    private static let newAPIMinVersion = "0.9.70"

    static let shared = LANraragiService()

    private var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    private var authInterceptor = AuthInterceptor(apiKey: nil)
    private var session: Session
    private let snakeCaseEncoder: JSONDecoder
    private let imageService = ImageService.shared

    private var urlSession: URLSession?
    private var urlSessionDelegate: URLSessionDelegateHandler?

    private(set) var useNewAPI: Bool = false

    private init() {
        self.session = Session(interceptor: authInterceptor)
        self.snakeCaseEncoder = JSONDecoder()
        self.snakeCaseEncoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func getURLSession() -> URLSession {
        if let urlSession = urlSession {
            return urlSession
        }
        let config = URLSessionConfiguration.background(withIdentifier: "com.jif.LANreader.download")
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 5
        let delegate = URLSessionDelegateHandler(imageService: imageService)
        self.urlSessionDelegate = delegate
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.urlSession = session
        return session
    }

    func verifyClient(url: String, apiKey: String) async -> DataTask<ServerInfo> {
        self.url = url
        let interceptor = AuthInterceptor(apiKey: apiKey)
        self.authInterceptor = interceptor
        self.session = Session(interceptor: interceptor)
        let cacher = ResponseCacher(behavior: .doNotCache)
        return session.request("\(self.url)/api/info")
            .cacheResponse(using: cacher)
            .validate(statusCode: 200...200)
            .serializingDecodable(ServerInfo.self, decoder: self.snakeCaseEncoder)
    }

    func checkServerVersionAtStartup() async {
        let storedUrl = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        let storedApiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""

        guard !storedUrl.isEmpty else {
            Self.logger.info("No server URL configured, skipping version check")
            return
        }

        do {
            let serverInfo = try await verifyClient(url: storedUrl, apiKey: storedApiKey).value
            updateAPIVersionFlag(serverVersion: serverInfo.version)
        } catch {
            Self.logger.warning("Failed to check server version at startup: \(error.localizedDescription)")
        }
    }

    func updateAPIVersionFlag(serverVersion: String) {
        self.useNewAPI = Self.compareVersions(serverVersion, isAtLeast: Self.newAPIMinVersion)
        Self.logger.info("Server version: \(serverVersion), using new API: \(self.useNewAPI)")
    }

    private static func compareVersions(_ version: String, isAtLeast minVersion: String) -> Bool {
        let versionComponents = version.split(separator: ".").compactMap { Int($0) }
        let minComponents = minVersion.split(separator: ".").compactMap { Int($0) }

        // Pad arrays to same length with zeros
        let maxLength = max(versionComponents.count, minComponents.count)
        let paddedVersion = versionComponents + Array(repeating: 0, count: maxLength - versionComponents.count)
        let paddedMin = minComponents + Array(repeating: 0, count: maxLength - minComponents.count)

        for (version, minVersion) in zip(paddedVersion, paddedMin) {
            if version > minVersion { return true }
            if version < minVersion { return false }
        }
        return true // versions are equal
    }

    func retrieveArchiveIndex() async -> DataTask<[ArchiveIndexResponse]> {
        session.request("\(url)/api/archives") { $0.timeoutInterval = 240 }
            .validate()
            .serializingDecodable([ArchiveIndexResponse].self)
    }

    func retrieveArchiveThumbnail(id: String, page: Int = 0) -> DownloadRequest {
        let query = ["page": page]

        // Create URL with query parameters
        var components = URLComponents(string: "\(url)/api/archives/\(id)/thumbnail")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: String($0.value)) }

        let request = URLRequest(url: components.url!)
        return session.download(request, to: { tempUrl, rsp in
            let destName: String
            if let filename = rsp.suggestedFilename {
                let fileExt = (filename as NSString).pathExtension
                destName = "\(id).\(fileExt)"
            } else {
                destName = id
            }
            let destinationUrl = LANraragiService.downloadPath?
                .appendingPathComponent("thumbnail", conformingTo: .folder)
                .appendingPathComponent(destName, conformingTo: .image)
            ?? tempUrl
            return (destinationUrl, [.createIntermediateDirectories, .removePreviousFile])
        }).validate()
    }

    func queuePageThumbnails(id: String) async -> DataTask<String> {
        return session.request("\(url)/api/archives/\(id)/files/thumbnails", method: .post)
            .validate(statusCode: [200, 202])
            .serializingString()
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

    func randomArchives(
        category: String? = nil,
        filter: String? = nil
    ) async -> DataTask<ArchiveRandomResponse> {
        var query = [String: String]()
        query["count"] = "100"
        if let category = category {
            query["category"] = category
        }
        if let filter = filter {
            query["filter"] = filter
        }
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

    func updateCategory(item: CategoryItem) async -> DataTask<GenericSuccessResponse> {
        var query = [String: String]()
        query["name"] = item.name
        if !item.search.isEmpty {
            query["search"] = item.search
        }
        query["pinned"] = item.pinned
        return session.request("\(url)/api/categories/\(item.id)", method: .put, parameters: query)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)
    }

    func deleteCategory(id: String) async -> DataTask<GenericSuccessResponse> {
        return session.request("\(url)/api/categories/\(id)", method: .delete)
            .validate(statusCode: 200...200)
            .serializingDecodable(GenericSuccessResponse.self)
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
        if useNewAPI {
            return session.request("\(url)/api/archives/\(id)/files", method: .get)
                .validate()
                .serializingDecodable(ArchiveExtractResponse.self)
        } else {
            return session.request("\(url)/api/archives/\(id)/extract", method: .post)
                .validate()
                .serializingDecodable(ArchiveExtractResponse.self)
        }
    }

    func fetchArchivePage(page: String, pageNumber: Int) -> DownloadRequest {
        let baseURL = getDomainURL(from: self.url)
            // Combine with the page path parameter
        let fullURL = URL(string: page, relativeTo: baseURL)!

        let request = URLRequest(url: fullURL)
        return session.download(request, to: { tempUrl, rsp in
            let destName: String
            if let filename = rsp.suggestedFilename {
                let fileExt = (filename as NSString).pathExtension
                destName = "\(pageNumber).\(fileExt)"
            } else {
                destName = "\(pageNumber)"
            }
            let id = String(page.split(separator: "/")[2])
            let destinationUrl = LANraragiService.downloadPath?
                .appendingPathComponent(id, conformingTo: .folder)
                .appendingPathComponent(destName, conformingTo: .image)
            ?? tempUrl
            return (destinationUrl, [.createIntermediateDirectories, .removePreviousFile])
        }).validate()
    }

    func backgroupFetchArchivePage(page: String, archiveId: String, pageNumber: Int) {
        var request = URLRequest(url: URL(string: "\(url)/\(page)")!)
        request.setValue("Bearer \(authInterceptor.encodedApiKey())", forHTTPHeaderField: "Authorization")
        request.setValue(archiveId, forHTTPHeaderField: "X-Archive-Id")
        request.setValue("\(pageNumber)", forHTTPHeaderField: "X-Page-Number")
        getURLSession().downloadTask(with: request).resume()
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

    func databaseStats() async -> DataTask<[StatsResponse]> {
        session.request("\(url)/api/database/stats", method: .get)
            .validate(statusCode: 200...200)
            .serializingDecodable([StatsResponse].self)
    }

    private func getDomainURL(from urlString: String) -> URL? {
        guard let url = URL(string: urlString) else { return nil }

        // Get components: scheme, host, port
        guard let scheme = url.scheme, let host = url.host else { return nil }

        // Reconstruct just domain part with optional port
        let portPart = url.port != nil ? ":\(url.port!)" : ""
        let domainString = "\(scheme)://\(host)\(portPart)"

        return URL(string: domainString)
    }
}

final class AuthInterceptor: RequestInterceptor, Sendable {

    private let apiKey: String

    init(apiKey: String?) {
        self.apiKey = apiKey ?? UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
    }

    func adapt(_ urlRequest: URLRequest,
               for session: Session,
               completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var modifiedURLRequest = urlRequest
        modifiedURLRequest.headers.add(.authorization(bearerToken: apiKey.data(using: .utf8)!.base64EncodedString()))
        completion(.success(modifiedURLRequest))
    }

    func encodedApiKey() -> String {
        apiKey.data(using: .utf8)!.base64EncodedString()
    }
}

// Separate class to handle URLSession delegate callbacks since actors can't conform to @objc protocols
final class URLSessionDelegateHandler: NSObject, URLSessionDelegate, URLSessionDownloadDelegate, Sendable {
    private let imageService: ImageService

    init(imageService: ImageService) {
        self.imageService = imageService
    }

    func urlSession(_: URLSession, downloadTask task: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let splitImage = UserDefaults.standard.bool(forKey: SettingsKey.splitWideImage)

        if let archiveId = task.originalRequest?.value(forHTTPHeaderField: "X-Archive-Id"),
           let pageNumber = task.originalRequest?.value(forHTTPHeaderField: "X-Page-Number"),
           let cachePath = LANraragiService.cachePath {
            let folder = cachePath.appendingPathComponent(archiveId, conformingTo: .folder)
            _ = imageService.resizeImage(
                imageUrl: location,
                destinationUrl: folder,
                pageNumber: pageNumber,
                split: splitImage
            )
        }
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
