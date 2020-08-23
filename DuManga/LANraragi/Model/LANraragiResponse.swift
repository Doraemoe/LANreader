//
//  ArchiveIndexResponse.swift
//  DuManga
//
//  Created by Jin Yifan on 22/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

struct ArchiveIndexResponse: Decodable {
    let arcid: String
    let isnew: String
    let tags: String
    let title: String
}

struct ArchiveExtractResponse: Decodable {
    let pages: [String]
}
