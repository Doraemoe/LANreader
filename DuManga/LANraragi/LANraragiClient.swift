//
//  LANRaragiClient.swift
//  DuManga
//
//  Created by Jin Yifan on 22/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

import Foundation
import Alamofire
import AlamofireImage
import Logging

class LANRaragiClient {
    static let logger = Logger(label: "LANRaragiClient")
    
    let url: String
    let auth: String
    
    init(url: String, apiKey: String) {
        self.url = url
        self.auth = apiKey.data(using: .utf8)!.base64EncodedString()
    }

    func getArchiveIndex(completionHandler: @escaping ([ArchiveIndexResponse]?) -> Void)  {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(auth)"
        ]
        AF.request("\(url)/api/archives", headers: headers)
            .validate()
            .responseDecodable(of: [ArchiveIndexResponse].self) { response in
                do {
                    let archiveIndex = try response.result.get()
                    completionHandler(archiveIndex)
                } catch {
                    LANRaragiClient.logger.error("Error retrieving the index: \(error)")
                    completionHandler(nil)
                }
        }
    }
    
    func getArchiveThumbnail(id: String, completionHandler: @escaping (Image?) -> Void) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(auth)"
        ]
        ImageResponseSerializer.addAcceptableImageContentTypes(["application/x-download"])
        AF.request("\(url)/api/archives/\(id)/thumbnail", headers: headers)
        .validate()
        .responseImage { response in
            do {
                let thumbnail = try response.result.get()
                completionHandler(thumbnail)
            } catch {
                LANRaragiClient.logger.error("Error retrieving thumbnail: \(error)")
                completionHandler(nil)
            }
        }
    }
    
    func postArchiveExtract(id: String, completionHandler: @escaping (ArchiveExtractResponse?) -> Void) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(auth)"
        ]
        AF.request("\(url)/api/archives/\(id)/extract", method: .post, headers: headers)
            .validate()
            .responseDecodable(of: ArchiveExtractResponse.self) { response in
                do {
                    let pages = try response.result.get()
                    completionHandler(pages)
                } catch {
                    LANRaragiClient.logger.error("Error extracting archive: \(error)")
                    completionHandler(nil)
                }
        }
    }
    
    func getArchivePage(page: String, completionHandler: @escaping (Image?) -> Void) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(auth)"
        ]
        ImageResponseSerializer.addAcceptableImageContentTypes(["application/x-download"])
        AF.request("\(url)/\(page)", headers: headers)
        .validate()
        .responseImage { response in
            do {
                let page = try response.result.get()
                completionHandler(page)
            } catch {
                LANRaragiClient.logger.error("Error retrieving page: \(error)")
                completionHandler(nil)
            }
        }
    }

}

