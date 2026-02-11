import UIKit
import Dependencies
import ImageIO
import UniformTypeIdentifiers

enum PageMainImageType: String, CaseIterable, Sendable {
    case heic
    case gif
    case webp

    static let cacheLookupOrder: [PageMainImageType] = [.heic, .gif, .webp]

    var isAnimatedContainer: Bool {
        self == .gif || self == .webp
    }
}

enum PageImagePathResolver {
    static func mainPath(in folder: URL, pageNumber: String, type: PageMainImageType) -> URL {
        folder.appendingPathComponent("\(pageNumber).\(type.rawValue)")
    }

    static func mainPath(in folder: URL?, pageNumber: Int, type: PageMainImageType) -> URL? {
        guard let folder else { return nil }
        return mainPath(in: folder, pageNumber: String(pageNumber), type: type)
    }

    static func existingMainPath(in folder: URL?, pageNumber: Int) -> URL? {
        guard let folder else { return nil }
        for type in PageMainImageType.cacheLookupOrder {
            let path = mainPath(in: folder, pageNumber: String(pageNumber), type: type)
            if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
                return path
            }
        }
        return nil
    }

    static func hasAnimatedMainPath(in folder: URL?, pageNumber: Int) -> Bool {
        guard let existingPath = existingMainPath(in: folder, pageNumber: pageNumber) else {
            return false
        }
        guard let type = PageMainImageType(rawValue: existingPath.pathExtension.lowercased()) else {
            return false
        }
        return type.isAnimatedContainer
    }
}

final class ImageService: Sendable {
    static let shared = ImageService()

    func heicDataOfImage(url: URL) -> Data? {
        guard let image = previewImage(url: url) else { return nil }
        return image.heicData()
    }

    // swiftlint:disable function_body_length
    func resizeImage(
        imageUrl: URL,
        imageData: Data? = nil,
        destinationUrl: URL,
        pageNumber: String,
        split: Bool
    ) -> Bool {
        try? FileManager.default.createDirectory(at: destinationUrl, withIntermediateDirectories: true)
        let mainPath = PageImagePathResolver.mainPath(in: destinationUrl, pageNumber: pageNumber, type: .heic)
        let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left.heic", conformingTo: .heic)
        let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right.heic", conformingTo: .heic)

        if imageData == nil,
            let animatedType = animatedContainerType(url: imageUrl),
            let animatedData = try? Data(contentsOf: imageUrl) {
            let destination = PageImagePathResolver.mainPath(
                in: destinationUrl,
                pageNumber: pageNumber,
                type: animatedType
            )
            try? animatedData.write(to: destination, options: .atomic)
            removeIfExists(mainPath)
            removeIfExists(leftPath)
            removeIfExists(rightPath)

            for type in PageMainImageType.allCases where type != animatedType {
                let stalePath = PageImagePathResolver.mainPath(
                    in: destinationUrl,
                    pageNumber: pageNumber,
                    type: type
                )
                removeIfExists(stalePath)
            }
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

        var splitted = false

        for type in PageMainImageType.allCases where type != .heic {
            let stalePath = PageImagePathResolver.mainPath(
                in: destinationUrl,
                pageNumber: pageNumber,
                type: type
            )
            removeIfExists(stalePath)
        }
        try? image.heicData()?.write(to: mainPath)

        if split && (image.size.width / image.size.height > 1.2) {
            try? image.leftHalf?.heicData()?.write(to: leftPath)
            try? image.rightHalf?.heicData()?.write(to: rightPath)

            splitted = true
        } else {
            removeIfExists(leftPath)
            removeIfExists(rightPath)
        }
        return splitted
    }
    // swiftlint:enable function_body_length

    private func previewImage(url: URL) -> UIImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 1,
            let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: frame)
        }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    private func animatedContainerType(url: URL) -> PageMainImageType? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard CGImageSourceGetCount(source) > 1 else { return nil }
        guard let type = CGImageSourceGetType(source) else { return nil }
        let utType = UTType(type as String)
        if utType?.conforms(to: .gif) == true {
            return .gif
        }
        if utType?.conforms(to: .webP) == true {
            return .webp
        }
        return nil
    }

    private func removeIfExists(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: url)
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
