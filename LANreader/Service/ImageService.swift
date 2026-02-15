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
        try? FileManager.default.createDirectory(at: destinationUrl, withIntermediateDirectories: true)

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
