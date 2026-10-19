//  Created 22/8/20.

import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import LANreader

class LANreaderTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testStorePreviewImageRejectsTruncatedJPEGData() throws {
        let previewURL = tempDirectory.appendingPathComponent("preview.jpg")
        let service = ImageService.shared

        let truncatedJPEG = makeJPEGData(color: .systemBlue).dropLast(32)

        XCTAssertFalse(service.storePreviewImage(imageData: truncatedJPEG, destinationUrl: previewURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path(percentEncoded: false)))
    }

    func testStorePageImageRejectsInvalidAndTruncatedPayloads() throws {
        let source = tempDirectory.appendingPathComponent("download.tmp")
        let folder = tempDirectory.appendingPathComponent("pages")
        let payloads = [
            Data(), Data("<html>Unauthorized</html>".utf8), Data("{\"error\":\"failed\"}".utf8),
            Data(makeJPEGData(color: .red).dropLast(32)), Data(makeTransparentPNGData().dropLast(20))
        ]
        for payload in payloads {
            try payload.write(to: source)
            XCTAssertNil(ImageService.shared.storePageImage(
                imageUrl: source, destinationUrl: folder, pageNumber: "1", splitWideImages: false
            ))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testValidStoredPageNumbersCountsOnlyDistinctCompleteImagesInRange() throws {
        let good = makeJPEGData(color: .blue)
        for filename in ["0.jpg", "1.jpg", "1.png", "4.jpg"] {
            try good.write(to: tempDirectory.appendingPathComponent(filename))
        }
        try Data("error".utf8).write(to: tempDirectory.appendingPathComponent("2.jpg"))
        try Data(good.dropLast(32)).write(to: tempDirectory.appendingPathComponent("3.jpg"))
        XCTAssertEqual(ImageService.shared.validStoredPageNumbers(folderUrl: tempDirectory, totalPages: 3), [1])
    }

    func testStoredPageNumbersCountsStoredPagesByName() throws {
        let good = makeJPEGData(color: .blue)
        for filename in ["0.jpg", "1.jpg", "2.png", "4.jpg", "cover.jpg"] {
            try good.write(to: tempDirectory.appendingPathComponent(filename))
        }
        XCTAssertEqual(ImageService.shared.storedPageNumbers(folderUrl: tempDirectory, totalPages: 3), [1, 2])
    }

    func testStoredImagePathFindsStoredPageByNumber() throws {
        try makeJPEGData(color: .blue).write(to: tempDirectory.appendingPathComponent("3.jpg"))

        XCTAssertEqual(
            ImageService.shared.storedImagePath(folderUrl: tempDirectory, pageNumber: "3")?.lastPathComponent,
            "3.jpg"
        )
        XCTAssertNil(ImageService.shared.storedImagePath(folderUrl: tempDirectory, pageNumber: "4"))
    }

    func testReadingSessionPagesLiveInCachesAndOfflineCachesAreExcludedFromBackup() throws {
        let sessionFolder = try XCTUnwrap(LANraragiService.downloadPath)
        let cachesFolder = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        XCTAssertEqual(sessionFolder.deletingLastPathComponent().standardizedFileURL, cachesFolder.standardizedFileURL)

        let cacheFolder = try XCTUnwrap(LANraragiService.cachePath)
        let values = try cacheFolder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testExcludeFromBackupCreatesAndMarksFolder() throws {
        let folder = tempDirectory.appendingPathComponent("cached", conformingTo: .folder)

        try PageStorage.excludeFromBackup(folder)

        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testStaleLaunchItemsSkipPagesDownloadedAfterLaunch() throws {
        let fileManager = FileManager.default
        let temporaryFolder = tempDirectory.appendingPathComponent("tmp", conformingTo: .folder)
        let sessionFolder = tempDirectory.appendingPathComponent("current session", conformingTo: .folder)
        let legacyFolder = tempDirectory.appendingPathComponent("legacy session", conformingTo: .folder)
        let oldPage = sessionFolder.appendingPathComponent("archive/1.jpg")
        for folder in [temporaryFolder, oldPage.deletingLastPathComponent(), legacyFolder] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("old".utf8).write(to: temporaryFolder.appendingPathComponent("download.tmp"))
        try makeJPEGData(color: .blue).write(to: oldPage)

        let staleItems = PageStorage.takeStaleItems(
            temporaryFolder: temporaryFolder,
            sessionFolder: sessionFolder,
            legacySessionFolder: legacyFolder
        )
        XCTAssertFalse(fileManager.fileExists(atPath: sessionFolder.path))
        let newPage = sessionFolder.appendingPathComponent("archive/1.jpg")
        try fileManager.createDirectory(at: newPage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeJPEGData(color: .red).write(to: newPage)

        PageStorage.remove(staleItems)

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: temporaryFolder.path), [])
        XCTAssertFalse(fileManager.fileExists(atPath: legacyFolder.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newPage.path))
    }

    func testSuccessfulPageReplacementRemovesInvalidAndOlderFormats() throws {
        let source = tempDirectory.appendingPathComponent("download.tmp")
        let folder = tempDirectory.appendingPathComponent("pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("error".utf8).write(to: folder.appendingPathComponent("1.img"))
        try makeJPEGData(color: .blue).write(to: folder.appendingPathComponent("1.jpg"))
        let replacement = makeTransparentPNGData()
        try replacement.write(to: source)
        let stored = try XCTUnwrap(ImageService.shared.storePageImage(
            imageUrl: source, destinationUrl: folder, pageNumber: "1", splitWideImages: false
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["1.png"])
        XCTAssertEqual(ImageService.shared.storedImagePath(folderUrl: folder, pageNumber: "1"), stored.url)
        XCTAssertEqual(try Data(contentsOf: stored.url), replacement)
    }

    func testPageStorageKeepsNewImageWhenFolderURLHasABaseURL() throws {
        let source = tempDirectory.appendingPathComponent("download.tmp")
        let folder = try XCTUnwrap(URL(string: "current%20session/pages/", relativeTo: tempDirectory))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("error".utf8).write(to: folder.appendingPathComponent("1.img"))
        let good = makeJPEGData(color: .blue)
        try good.write(to: source)

        let stored = try XCTUnwrap(ImageService.shared.storePageImage(
            imageUrl: source, destinationUrl: folder, pageNumber: "1", splitWideImages: false
        ))

        XCTAssertEqual(try Data(contentsOf: stored.url), good)
        let lookup = try XCTUnwrap(ImageService.shared.storedImagePath(folderUrl: folder, pageNumber: "1"))
        XCTAssertEqual(try Data(contentsOf: lookup), good)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["1.jpg"])
    }

    func testStorePreviewImageWritesPreviewForCompleteJPEGData() throws {
        let previewURL = tempDirectory.appendingPathComponent("preview.jpg")
        let service = ImageService.shared
        let imageData = makeJPEGData(color: .systemGreen)

        XCTAssertTrue(
            service.storePreviewImage(
                imageData: imageData,
                destinationUrl: previewURL
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path(percentEncoded: false)))
        XCTAssertEqual(try Data(contentsOf: previewURL), imageData)
    }

    func testGeneratePreviewImageWritesBoundedJPEGForTransparentPNG() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.png")
        let previewURL = tempDirectory.appendingPathComponent("preview.jpg")
        let service = ImageService.shared

        try makeTransparentPNGData().write(to: sourceURL, options: .atomic)

        XCTAssertTrue(
            service.generatePreviewImage(
                sourceUrl: sourceURL,
                destinationUrl: previewURL,
                maxPixelSize: 64
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path(percentEncoded: false)))

        let previewData = try Data(contentsOf: previewURL)
        XCTAssertTrue(previewData.starts(with: [0xFF, 0xD8]))

        let imageSource = CGImageSourceCreateWithURL(previewURL as CFURL, nil)
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource!, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        XCTAssertEqual(width, 64)
        XCTAssertEqual(height, 32)
    }

    func testSplitImageCropsWideImageHalves() throws {
        let sourceURL = tempDirectory.appendingPathComponent("wide.png")
        let service = ImageService.shared

        try makeWidePNGData().write(to: sourceURL, options: .atomic)

        XCTAssertTrue(service.shouldSplitWideImage(imageUrl: sourceURL))

        let leftImage = try XCTUnwrap(service.splitImage(imageUrl: sourceURL, side: .left))
        let rightImage = try XCTUnwrap(service.splitImage(imageUrl: sourceURL, side: .right))

        XCTAssertEqual(leftImage.cgImage?.width, 60)
        XCTAssertEqual(leftImage.cgImage?.height, 60)
        XCTAssertEqual(rightImage.cgImage?.width, 60)
        XCTAssertEqual(rightImage.cgImage?.height, 60)
    }

    func testStorePageImageStoresSmallJPEGWithoutTranscoding() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        let service = ImageService.shared
        let imageData = makeJPEGData(color: .systemPurple)

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "1",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "1"))
        XCTAssertEqual(storedURL.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageUsesDetectedTypeForDownloadedTempFile() throws {
        let sourceURL = tempDirectory.appendingPathComponent("download.tmp")
        let service = ImageService.shared
        let imageData = makeJPEGData(color: .systemPurple)

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "8",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "8"))
        XCTAssertEqual(storedURL.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageUsesStoredPathForSplitDecisionWhenSourceHasNoExtension() throws {
        let sourceDirectory = tempDirectory.appendingPathComponent("downloads", isDirectory: true)
        let destinationDirectory = tempDirectory.appendingPathComponent("pages", isDirectory: true)
        let sourceURL = sourceDirectory.appendingPathComponent("9")
        let service = ImageService.shared
        let imageData = makeWidePNGData()

        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: destinationDirectory,
                pageNumber: "9",
                splitWideImages: true
            ),
            shouldDisplayAsSplitPages: true
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: destinationDirectory, pageNumber: "9"))
        XCTAssertEqual(storedURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImagePreservesSmallJPEGWhenSourceIsExistingPageFile() throws {
        let sourceURL = tempDirectory.appendingPathComponent("1.jpg")
        let service = ImageService.shared
        let imageData = makeJPEGData(color: .systemPurple)

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "1",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "1"))
        XCTAssertEqual(storedURL, sourceURL)
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageStoresSmallPNGWithoutTranscoding() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.png")
        let service = ImageService.shared
        let imageData = makeTransparentPNGData()

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "2",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "2"))
        XCTAssertEqual(storedURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageStoresSmallHEICWithoutTranscoding() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.heic")
        let service = ImageService.shared
        let imageData = try makeHEICData()

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "7",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "7"))
        XCTAssertEqual(storedURL.pathExtension, "heic")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageDownsamplesLargeOpaqueImageToJPEG() throws {
        let sourceURL = tempDirectory.appendingPathComponent("large.jpg")
        let service = ImageService.shared
        let imageData = makeJPEGData(
            color: .systemOrange,
            size: CGSize(width: 5_000, height: 100)
        )

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "3",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "3"))
        let storedData = try Data(contentsOf: storedURL)
        let storedSize = try XCTUnwrap(imagePixelSize(at: storedURL))

        XCTAssertEqual(storedURL.pathExtension, "jpg")
        XCTAssertTrue(storedData.starts(with: [0xFF, 0xD8]))
        XCTAssertLessThanOrEqual(max(storedSize.width, storedSize.height), 4_096)
        XCTAssertNotEqual(storedData, imageData)
    }

    func testStorePageImageDownsamplesLargeTransparentImageToPNG() throws {
        let sourceURL = tempDirectory.appendingPathComponent("large.png")
        let service = ImageService.shared
        let imageData = makeTransparentPNGData(size: CGSize(width: 5_000, height: 100))

        try imageData.write(to: sourceURL, options: .atomic)

        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "4",
                splitWideImages: false
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "4"))
        let storedSize = try XCTUnwrap(imagePixelSize(at: storedURL))

        XCTAssertEqual(storedURL.pathExtension, "png")
        XCTAssertEqual(imageType(at: storedURL), .png)
        XCTAssertTrue(imageHasAlpha(at: storedURL))
        XCTAssertLessThanOrEqual(max(storedSize.width, storedSize.height), 4_096)
    }

    func testStorePageImageStoresAnimatedImageWithoutTranscoding() throws {
        let sourceURL = tempDirectory.appendingPathComponent("animated.gif")
        let service = ImageService.shared
        let imageData = makeAnimatedGIFData()

        try imageData.write(to: sourceURL, options: .atomic)

        XCTAssertTrue(service.isAnimatedImage(imageUrl: sourceURL))
        assertStoredPageImage(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: tempDirectory,
                pageNumber: "5",
                splitWideImages: true
            ),
            shouldDisplayAsSplitPages: false
        )

        let storedURL = try XCTUnwrap(service.storedImagePath(folderUrl: tempDirectory, pageNumber: "5"))
        XCTAssertEqual(storedURL.pathExtension, "gif")
        XCTAssertEqual(try Data(contentsOf: storedURL), imageData)
    }

    func testStorePageImageWriteFailureDoesNotRemoveExistingCachedPage() throws {
        let cacheFolder = tempDirectory.appendingPathComponent("readonly", isDirectory: true)
        let sourceURL = tempDirectory.appendingPathComponent("large.jpg")
        let existingURL = cacheFolder.appendingPathComponent("6.jpg")
        let service = ImageService.shared
        let existingData = makeJPEGData(color: .systemBlue)
        let imageData = makeJPEGData(
            color: .systemRed,
            size: CGSize(width: 5_000, height: 100)
        )

        try FileManager.default.createDirectory(
            at: cacheFolder,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try existingData.write(to: existingURL, options: .atomic)
        try imageData.write(to: sourceURL, options: .atomic)

        _ = chmod(cacheFolder.path(percentEncoded: false), S_IRUSR | S_IXUSR)
        _ = chmod(existingURL.path(percentEncoded: false), S_IRUSR)
        defer {
            _ = chmod(existingURL.path(percentEncoded: false), S_IRUSR | S_IWUSR)
            _ = chmod(cacheFolder.path(percentEncoded: false), S_IRWXU)
        }

        try XCTSkipIf(
            FileManager.default.isWritableFile(atPath: existingURL.path(percentEncoded: false)),
            "filesystem ignores read-only file permissions"
        )

        XCTAssertNil(
            service.storePageImage(
                imageUrl: sourceURL,
                destinationUrl: cacheFolder,
                pageNumber: "6",
                splitWideImages: false
            )
        )
        XCTAssertEqual(try Data(contentsOf: existingURL), existingData)
    }
}

private func assertStoredPageImage(
    _ result: StoredPageImageResult?,
    shouldDisplayAsSplitPages expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let result else {
        XCTFail("Expected image to be stored", file: file, line: line)
        return
    }

    XCTAssertEqual(result.shouldDisplayAsSplitPages, expected, file: file, line: line)
}

private func makeJPEGData(
    color: UIColor,
    size: CGSize = CGSize(width: 120, height: 180)
) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.jpegData(compressionQuality: 0.9)!
}

private func makeTransparentPNGData(
    size: CGSize = CGSize(width: 200, height: 100)
) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
        UIColor.clear.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        UIColor.systemBlue.setFill()
        context.fill(
            CGRect(
                x: size.width * 0.1,
                y: size.height * 0.2,
                width: size.width * 0.8,
                height: size.height * 0.6
            )
        )
    }
    return image.pngData()!
}

private func makeWidePNGData() -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60), format: format)
    let image = renderer.image { context in
        UIColor.systemRed.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))

        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 60, y: 0, width: 60, height: 60))
    }
    return image.pngData()!
}

private func makeAnimatedGIFData() -> Data {
    let data = NSMutableData()
    let frameProperties = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 0.1
        ]
    ] as CFDictionary

    let destination = CGImageDestinationCreateWithData(
        data,
        UTType.gif.identifier as CFString,
        2,
        nil
    )!
    CGImageDestinationAddImage(
        destination,
        makeCGImage(color: .systemRed),
        frameProperties
    )
    CGImageDestinationAddImage(
        destination,
        makeCGImage(color: .systemGreen),
        frameProperties
    )
    _ = CGImageDestinationFinalize(destination)

    return data as Data
}

private func makeHEICData() throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.heic.identifier as CFString,
        1,
        nil
    ) else {
        throw XCTSkip("HEIC encoding is unavailable in this test environment")
    }

    let options = [
        kCGImageDestinationLossyCompressionQuality: 0.9
    ] as CFDictionary
    CGImageDestinationAddImage(destination, makeCGImage(color: .systemPurple), options)

    guard CGImageDestinationFinalize(destination) else {
        throw XCTSkip("HEIC encoding failed in this test environment")
    }
    return data as Data
}

private func makeCGImage(
    color: UIColor,
    size: CGSize = CGSize(width: 32, height: 32)
) -> CGImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.cgImage!
}

private func imagePixelSize(at url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
        return nil
    }

    return CGSize(width: width.doubleValue, height: height.doubleValue)
}

private func imageType(at url: URL) -> UTType? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let typeIdentifier = CGImageSourceGetType(source) else {
        return nil
    }
    return UTType(typeIdentifier as String)
}

private func imageHasAlpha(at url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return false
    }

    switch image.alphaInfo {
    case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
        return true
    case .none, .noneSkipFirst, .noneSkipLast:
        return false
    @unknown default:
        return true
    }
}
