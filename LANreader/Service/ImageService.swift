import UIKit
import Dependencies
import ImageIO
import UniformTypeIdentifiers

enum ImageSplitSide: Sendable {
    case left
    case right
}

private struct StoredImageFile {
    let url: URL
    let isAnimated: Bool
}

struct StoredPageImageResult: Sendable {
    let url: URL
    let shouldDisplayAsSplitPages: Bool
}

final class ImageService: Sendable {
    static let shared = ImageService()

    private static let maxStoredLongEdge: CGFloat = 4096
    private static let maxDecodedImageBytes: Double = 64 * 1024 * 1024
    private static let jpegCompressionQuality: CGFloat = 0.92

    func isAnimatedImage(imageUrl: URL, imageData: Data? = nil) -> Bool {
        guard let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData) else { return false }
        return CGImageSourceGetCount(imageSource) > 1
    }

    func shouldSplitWideImage(imageUrl: URL, imageData: Data? = nil) -> Bool {
        guard !isAnimatedImage(imageUrl: imageUrl, imageData: imageData),
              let imageSize = imagePixelSize(imageUrl: imageUrl, imageData: imageData),
              imageSize.height > 0 else {
            return false
        }
        return imageSize.width / imageSize.height > 1.2
    }

    func storedImagePath(folderUrl: URL?, pageNumber: String) -> URL? {
        guard let folderUrl else { return nil }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderUrl,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let matched = files.filter {
            !$0.hasDirectoryPath
                && $0.deletingPathExtension().lastPathComponent == pageNumber
        }
        return matched.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first
    }

    func splitImage(imageUrl: URL, side: ImageSplitSide) -> UIImage? {
        guard let image = UIImage(contentsOfFile: imageUrl.path(percentEncoded: false)),
              let cgImage = image.cgImage else {
            return nil
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard pixelWidth > 1, pixelHeight > 0 else {
            return nil
        }

        let midpoint = pixelWidth / 2
        let cropRect: CGRect
        switch side {
        case .left:
            cropRect = CGRect(x: 0, y: 0, width: CGFloat(midpoint), height: CGFloat(pixelHeight))
        case .right:
            cropRect = CGRect(
                x: CGFloat(midpoint),
                y: 0,
                width: CGFloat(pixelWidth - midpoint),
                height: CGFloat(pixelHeight)
            )
        }

        guard cropRect.width > 0,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: image.imageOrientation)
    }

    func storePageImage(
        imageUrl: URL,
        imageData: Data? = nil,
        destinationUrl: URL,
        pageNumber: String,
        splitWideImages: Bool
    ) -> StoredPageImageResult? {
        guard let storedImage = storeImageFile(
            imageUrl: imageUrl,
            imageData: imageData,
            destinationUrl: destinationUrl,
            pageNumber: pageNumber
        ) else {
            return nil
        }

        let shouldDisplayAsSplitPages = !storedImage.isAnimated
            && splitWideImages
            && shouldSplitWideImage(imageUrl: storedImage.url)

        return StoredPageImageResult(
            url: storedImage.url,
            shouldDisplayAsSplitPages: shouldDisplayAsSplitPages
        )
    }

    func generatePreviewImage(
        sourceUrl: URL,
        destinationUrl: URL,
        maxPixelSize: CGFloat = 1024
    ) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(sourceUrl as CFURL, nil) else {
            return false
        }
        return writePreviewImage(
            from: imageSource,
            destinationUrl: destinationUrl,
            maxPixelSize: maxPixelSize
        )
    }

    func storePreviewImage(
        imageData: Data,
        destinationUrl: URL,
    ) -> Bool {
        guard hasCompleteEncodedPayload(imageData) else {
            return false
        }

        return writeData(imageData, destinationUrl: destinationUrl)
    }
}

private extension ImageService {
    private func writePreviewImage(
        from imageSource: CGImageSource,
        destinationUrl: URL,
        maxPixelSize: CGFloat
    ) -> Bool {
        guard CGImageSourceGetCount(imageSource) > 0,
              CGImageSourceGetStatus(imageSource) == .statusComplete,
              CGImageSourceGetStatusAtIndex(imageSource, 0) == .statusComplete else {
            return false
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        let previewImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options)

        guard let previewImage else {
            return false
        }

        let outputImage = if cgImageHasAlpha(previewImage) {
            flattenedImageForJPEG(previewImage)
        } else {
            previewImage
        }

        guard let outputImage else {
            return false
        }

        return writeJPEGImage(outputImage, destinationUrl: destinationUrl)
    }

    private func storeImageFile(
        imageUrl: URL,
        imageData: Data?,
        destinationUrl: URL,
        pageNumber: String
    ) -> StoredImageFile? {
        if isAnimatedImage(imageUrl: imageUrl, imageData: imageData) {
            return storeOriginalImage(
                imageUrl: imageUrl,
                imageData: imageData,
                destinationUrl: destinationUrl,
                pageNumber: pageNumber,
                isAnimated: true
            )
        }

        guard let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData),
              let imageSize = imagePixelSize(from: imageSource) else {
            return storeOriginalImage(
                imageUrl: imageUrl,
                imageData: imageData,
                destinationUrl: destinationUrl,
                pageNumber: pageNumber,
                isAnimated: false
            )
        }

        let shouldDownsample = shouldDownsampleImage(pixelSize: imageSize)
        if shouldDownsample {
            guard let url = writeStaticImage(
                from: imageSource,
                destinationUrl: destinationUrl,
                pageNumber: pageNumber,
                maxPixelSize: Self.maxStoredLongEdge
            ) else {
                return nil
            }
            return StoredImageFile(url: url, isAnimated: false)
        }

        return storeOriginalImage(
            imageUrl: imageUrl,
            imageData: imageData,
            destinationUrl: destinationUrl,
            pageNumber: pageNumber,
            isAnimated: false
        )
    }

    private func storeOriginalImage(
        imageUrl: URL,
        imageData: Data?,
        destinationUrl: URL,
        pageNumber: String,
        isAnimated: Bool
    ) -> StoredImageFile? {
        let fileExt = preferredFileExtension(imageUrl: imageUrl, imageData: imageData)
        let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).\(fileExt)")

        guard let originalData = imageData ?? (try? Data(contentsOf: imageUrl)) else {
            return nil
        }

        guard writeData(originalData, destinationUrl: mainPath) else {
            return nil
        }
        return StoredImageFile(url: mainPath, isAnimated: isAnimated)
    }

    private func hasCompleteEncodedPayload(_ imageData: Data) -> Bool {
        guard imageData.count > 4 else {
            return false
        }

        if imageData.starts(with: [0xFF, 0xD8]) {
            return hasJPEGEndMarker(imageData)
        }

        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if imageData.starts(with: pngSignature) {
            let pngTrailer = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
            return imageData.suffix(12) == pngTrailer
        }

        return true
    }

    private func hasJPEGEndMarker(_ imageData: Data) -> Bool {
        let trailingSkippableBytes = Set([UInt8(0x00), 0x09, 0x0A, 0x0D, 0x20])
        var endIndex = imageData.endIndex

        while endIndex > imageData.startIndex {
            let indexBeforeEnd = imageData.index(before: endIndex)
            if trailingSkippableBytes.contains(imageData[indexBeforeEnd]) {
                endIndex = indexBeforeEnd
            } else {
                break
            }
        }

        guard endIndex >= imageData.index(imageData.startIndex, offsetBy: 2) else {
            return false
        }

        let markerEnd = imageData.index(before: endIndex)
        let markerStart = imageData.index(before: markerEnd)
        return imageData[markerStart] == 0xFF && imageData[markerEnd] == 0xD9
    }

    private func cgImageHasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    private func flattenedImageForJPEG(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private func writeJPEGImage(_ image: CGImage, destinationUrl: URL) -> Bool {
        writeCGImage(
            image,
            destinationUrl: destinationUrl,
            type: .jpeg,
            compressionQuality: 0.9
        )
    }

    private func writeStaticImage(
        from imageSource: CGImageSource,
        destinationUrl: URL,
        pageNumber: String,
        maxPixelSize: CGFloat
    ) -> URL? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }

        let hasAlpha = cgImageHasAlpha(image)
        let fileType: UTType = hasAlpha ? .png : .jpeg
        let fileExt = preferredFileExtension(for: fileType)
        let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).\(fileExt)")
        let quality = hasAlpha ? nil : Self.jpegCompressionQuality

        guard writeCGImage(
            image,
            destinationUrl: mainPath,
            type: fileType,
            compressionQuality: quality
        ) else {
            return nil
        }

        return mainPath
    }

    private func shouldDownsampleImage(pixelSize: CGSize) -> Bool {
        let longestEdge = max(pixelSize.width, pixelSize.height)
        let decodedBytes = Double(pixelSize.width) * Double(pixelSize.height) * 4

        return longestEdge > Self.maxStoredLongEdge || decodedBytes > Self.maxDecodedImageBytes
    }

    private func writeData(_ data: Data, destinationUrl: URL) -> Bool {
        let destinationDirectory = destinationUrl.deletingLastPathComponent()

        try? FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        do {
            try data.write(to: destinationUrl)
            return true
        } catch {
            return false
        }
    }

    private func writeCGImage(
        _ image: CGImage,
        destinationUrl: URL,
        type: UTType,
        compressionQuality: CGFloat? = nil
    ) -> Bool {
        let imageData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            imageData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        let options: CFDictionary?
        if let compressionQuality {
            options = [
                kCGImageDestinationLossyCompressionQuality: compressionQuality
            ] as CFDictionary
        } else {
            options = nil
        }
        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            return false
        }

        return writeData(imageData as Data, destinationUrl: destinationUrl)
    }

    private func makeImageSource(imageUrl: URL, imageData: Data? = nil) -> CGImageSource? {
        if let imageData {
            return CGImageSourceCreateWithData(imageData as CFData, nil)
        }
        return CGImageSourceCreateWithURL(imageUrl as CFURL, nil)
    }

    private func imagePixelSize(imageUrl: URL, imageData: Data? = nil) -> CGSize? {
        guard let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData) else {
            return nil
        }
        return imagePixelSize(from: imageSource)
    }

    private func imagePixelSize(from imageSource: CGImageSource) -> CGSize? {
        guard CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        if let orientation = properties[kCGImagePropertyOrientation] as? NSNumber,
           [5, 6, 7, 8].contains(orientation.intValue) {
            return CGSize(width: height.doubleValue, height: width.doubleValue)
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func preferredFileExtension(imageUrl: URL, imageData: Data? = nil) -> String {
        if let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData),
           let imageType = CGImageSourceGetType(imageSource),
           let type = UTType(imageType as String) {
            return preferredFileExtension(for: type)
        }

        let pathExtension = imageUrl.pathExtension.lowercased()
        if !pathExtension.isEmpty,
           let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .image) {
            return pathExtension
        }

        return pathExtension.isEmpty ? "img" : pathExtension
    }

    private func preferredFileExtension(for type: UTType) -> String {
        if type.conforms(to: .jpeg) {
            return "jpg"
        }
        return type.preferredFilenameExtension?.lowercased() ?? "img"
    }

}

extension ImageService: DependencyKey {
    static let liveValue = ImageService.shared
    static let testValue = ImageService.shared
}

extension DependencyValues {
    var imageService: ImageService {
        get { self[ImageService.self] }
        set { self[ImageService.self] = newValue }
    }
}

extension UIImage {
    var topHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: .zero,
                size: CGSize(width: size.width, height: size.height / 2)
            )
        )?.image
    }
    var bottomHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: CGPoint(x: .zero, y: size.height - (size.height/2).rounded()),
                size: CGSize(width: size.width, height: size.height - (size.height/2).rounded())
            )
        )?.image
    }
}

extension CGImage {
    var image: UIImage { .init(cgImage: self) }
}
