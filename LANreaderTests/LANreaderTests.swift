//  Created 22/8/20.

import XCTest
import UIKit
import ImageIO
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
}

private func makeJPEGData(color: UIColor) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180))
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
    }
    return image.jpegData(compressionQuality: 0.9)!
}

private func makeTransparentPNGData() -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format)
    let image = renderer.image { context in
        UIColor.clear.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))

        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 20, y: 20, width: 160, height: 60))
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
