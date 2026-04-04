import UIKit
import Dependencies
import ImageIO
import UniformTypeIdentifiers

final class ImageService: Sendable {
    static let shared = ImageService()

    func isAnimatedImage(imageUrl: URL, imageData: Data? = nil) -> Bool {
        guard let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData) else { return false }
        return CGImageSourceGetCount(imageSource) > 1
    }

    func storedImagePath(folderUrl: URL?, pageNumber: String) -> URL? {
        guard let folderUrl else { return nil }
        let heicPath = folderUrl.appendingPathComponent("\(pageNumber).heic", conformingTo: .heic)
        if FileManager.default.fileExists(atPath: heicPath.path(percentEncoded: false)) {
            return heicPath
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderUrl,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let matched = files.filter {
            !$0.hasDirectoryPath && $0.deletingPathExtension().lastPathComponent == pageNumber
        }
        return matched.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first
    }

    func heicDataOfImage(url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        return image.heicData()
    }

    func resizeImage(
        imageUrl: URL,
        imageData: Data? = nil,
        destinationUrl: URL,
        pageNumber: String,
        split: Bool
    ) -> Bool {
        try? FileManager.default.createDirectory(
            at: destinationUrl,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if isAnimatedImage(imageUrl: imageUrl, imageData: imageData) {
            guard let originalData = imageData ?? (try? Data(contentsOf: imageUrl)) else { return false }
            let fileExt = preferredFileExtension(imageUrl: imageUrl, imageData: originalData)
            let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).\(fileExt)")

            removeStoredImages(
                at: destinationUrl,
                pageNames: [pageNumber, "\(pageNumber)-left", "\(pageNumber)-right"]
            )
            try? originalData.write(to: mainPath, options: .atomic)
            return false
        }

        let image: UIImage
        if imageData != nil {
            guard let convertImage = UIImage(data: imageData!) else { return false }
            image = convertImage
        } else {
            guard let convertImage = UIImage(contentsOfFile: imageUrl.path(percentEncoded: false)) else { return false }
            image = convertImage
        }

        let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).heic", conformingTo: .heic)
        removeStoredImages(
            at: destinationUrl,
            pageNames: [pageNumber, "\(pageNumber)-left", "\(pageNumber)-right"]
        )

        var splitted = false

        try? image.heicData()?.write(to: mainPath)

        if split && (image.size.width / image.size.height > 1.2) {
            let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left.heic", conformingTo: .heic)
            let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right.heic", conformingTo: .heic)

            try? image.leftHalf?.heicData()?.write(to: leftPath)
            try? image.rightHalf?.heicData()?.write(to: rightPath)

            splitted = true
        }
        return splitted
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

        try? FileManager.default.createDirectory(
            at: destinationUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        do {
            try imageData.write(to: destinationUrl, options: .atomic)
            return true
        } catch {
            return false
        }
    }

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
        let destinationDirectory = destinationUrl.deletingLastPathComponent()
        let tempURL = destinationDirectory.appendingPathComponent(
            "\(UUID().uuidString).jpg",
            isDirectory: false
        )

        try? FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }

        let options = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            if FileManager.default.fileExists(atPath: destinationUrl.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(destinationUrl, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destinationUrl)
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    private func makeImageSource(imageUrl: URL, imageData: Data? = nil) -> CGImageSource? {
        if let imageData {
            return CGImageSourceCreateWithData(imageData as CFData, nil)
        }
        return CGImageSourceCreateWithURL(imageUrl as CFURL, nil)
    }

    private func preferredFileExtension(imageUrl: URL, imageData: Data? = nil) -> String {
        let pathExtension = imageUrl.pathExtension.lowercased()
        if !pathExtension.isEmpty, UTType(filenameExtension: pathExtension) != nil {
            return pathExtension
        }

        if let imageSource = makeImageSource(imageUrl: imageUrl, imageData: imageData),
           let imageType = CGImageSourceGetType(imageSource),
           let type = UTType(imageType as String),
           let preferredExtension = type.preferredFilenameExtension {
            return preferredExtension.lowercased()
        }

        return pathExtension.isEmpty ? "img" : pathExtension
    }

    private func removeStoredImages(at folderUrl: URL, pageNames: [String]) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderUrl, includingPropertiesForKeys: nil
        ) else {
            return
        }
        let pageNameSet = Set(pageNames)
        files
            .filter { pageNameSet.contains($0.deletingPathExtension().lastPathComponent) }
            .forEach { try? FileManager.default.removeItem(at: $0) }
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
    var leftHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: .zero,
                size: CGSize(width: size.width/2, height: size.height)
            )
        )?.image
    }
    var rightHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: CGPoint(x: size.width - (size.width/2).rounded(), y: .zero),
                size: CGSize(width: size.width - (size.width/2).rounded(), height: size.height)
            )
        )?.image
    }
}

extension CGImage {
    var image: UIImage { .init(cgImage: self) }
}
