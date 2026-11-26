import Foundation
import Logging

public struct ReaderExtractedPage: Equatable, Sendable {
    public let archiveId: String
    public let path: String
    public let archivePageNumber: Int

    public init(archiveId: String, path: String, archivePageNumber: Int) {
        self.archiveId = archiveId
        self.path = path
        self.archivePageNumber = archivePageNumber
    }
}

private let archiveExtractionLogger = Logger(label: "ArchiveExtraction")

extension LANraragiService {
    func extractArchiveForReading(
        id: String
    ) async throws -> (pages: [ReaderExtractedPage], tankoubonDetails: TankoubonDetailsMetadata?) {
        guard id.isTankoubonArchiveId else {
            let response = try await extractArchive(id: id).value
            return (
                pages: Self.extractedPages(from: response.pages, archiveId: id),
                tankoubonDetails: nil
            )
        }

        let tankoubon = try await retrieveFullTankoubon(id: id).value
        var details = TankoubonDetailsMetadata(response: tankoubon)
        let archiveIds = Self.tankoubonArchiveIds(from: tankoubon)
        let archiveMetadata = Dictionary(
            (tankoubon.result.fullData ?? []).map { ($0.arcid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pages: [ReaderExtractedPage] = []
        var chapters: [ArchiveChapter] = []

        if archiveIds.isEmpty {
            archiveExtractionLogger.error("tankoubon returned no archives. id=\(id)")
        }

        for archiveId in archiveIds {
            let metadata = archiveMetadata[archiveId]
            let response = try await extractArchive(id: archiveId).value
            if response.pages.isEmpty {
                archiveExtractionLogger.error("server returned empty pages. id=\(archiveId)")
            }
            let extractedPages = Self.extractedPages(from: response.pages, archiveId: archiveId)
            let chapterResult = Self.tankoubonChapters(
                from: metadata,
                pageOffset: pages.count,
                extractedPageCount: extractedPages.count
            )
            chapters.append(contentsOf: chapterResult.chapters)
            if let metadata, !metadata.title.isEmpty, !extractedPages.isEmpty {
                details.defaultChapters.append(
                    ArchiveChapter(name: metadata.title, page: pages.count + 1)
                )
            }
            if let automaticPage = chapterResult.automaticPage {
                details.automaticChapterPages.insert(automaticPage)
            }
            pages.append(contentsOf: extractedPages)
        }

        details.toc = chapters.isEmpty ? nil : chapters
        return (pages: pages, tankoubonDetails: details)
    }

    nonisolated func saveAndCacheArchive(
        _ archive: ArchiveItem,
        pages: [ReaderExtractedPage],
        toc: [ArchiveChapter]? = nil,
        database: AppDatabase
    ) async throws {
        var cache = ArchiveCache(
            id: archive.id,
            title: archive.name,
            tags: archive.tags,
            thumbnail: (try? database.readArchiveThumbnail(archive.id))?.thumbnail,
            cached: false,
            totalPages: pages.count,
            toc: toc ?? archive.toc,
            lastUpdate: Date(),
            progress: archive.progress
        )
        try database.saveCache(&cache)
        try await cachePages(archiveId: archive.id, pages: pages)
    }

    private static func tankoubonArchiveIds(from response: TankoubonFullResponse) -> [String] {
        if let archives = response.result.archives, !archives.isEmpty {
            return archives
        }
        return response.result.fullData?.map(\.arcid) ?? []
    }

    private static func extractedPages(from pages: [String], archiveId: String) -> [ReaderExtractedPage] {
        pages.enumerated().map { index, path in
            ReaderExtractedPage(archiveId: archiveId, path: path, archivePageNumber: index + 1)
        }
    }

    private static func tankoubonChapters(
        from archiveMetadata: ArchiveIndexResponse?,
        pageOffset: Int,
        extractedPageCount: Int
    ) -> (chapters: [ArchiveChapter], automaticPage: Int?) {
        guard extractedPageCount > 0, let archiveMetadata else { return ([], nil) }
        var chapters: [ArchiveChapter] = (archiveMetadata.toc ?? []).compactMap { chapter in
            guard (1...extractedPageCount).contains(chapter.page) else { return nil }
            return ArchiveChapter(name: chapter.name, page: pageOffset + chapter.page)
        }
        let firstPage = pageOffset + 1
        if !archiveMetadata.title.isEmpty,
           !chapters.contains(where: { $0.page == firstPage }) {
            chapters.insert(
                ArchiveChapter(name: archiveMetadata.title, page: firstPage),
                at: 0
            )
            return (chapters, firstPage)
        }
        return (chapters, nil)
    }
}
