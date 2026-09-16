import CoreGraphics
import Foundation

/// Pure layout math for the continuous vertical reader.
///
/// Page height is treated as a known layout input derived from the image aspect ratio, rather than
/// something discovered by self-sizing after the image decodes. Pages whose real dimensions are not
/// known yet fall back to the archive's measured median, which keeps the estimate close because
/// pages within an archive are near-uniform.
enum ReaderPageLayout {
    struct SliderPreviewBubbleLayout: Equatable {
        let width: CGFloat
        let imageHeight: CGFloat
        let rowHeight: CGFloat
    }

    /// Aspect ratio (height / width) used before any page in the archive has been measured.
    /// Roughly matches the common A-series and B-series page proportions.
    static let defaultAspectRatio: Double = 1.4

    static func validatedAspectRatio(_ aspectRatio: Double?) -> Double {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else {
            return defaultAspectRatio
        }
        return aspectRatio
    }

    static func aspectRatio(for imageSize: CGSize) -> Double? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        return Double(imageSize.height / imageSize.width)
    }

    /// A split page shows half of the source image width, so it renders twice as tall relative to its width.
    static func splitAspectRatio(for sourceAspectRatio: Double) -> Double {
        sourceAspectRatio * 2
    }

    static func medianAspectRatio(_ aspectRatios: [Double]) -> Double? {
        let usable = aspectRatios.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !usable.isEmpty else { return nil }
        return usable[usable.count / 2]
    }

    static func itemHeight(width: CGFloat, aspectRatio: Double?) -> CGFloat {
        guard width > 0 else { return 0 }
        return (width * validatedAspectRatio(aspectRatio)).rounded()
    }

    static func sliderPreviewBubbleLayout(readerSize: CGSize) -> SliderPreviewBubbleLayout {
        let aspectRatio: CGFloat = 248 / 176
        let availableWidth = max(readerSize.width - 48, 0)
        let targetWidth = min(max(availableWidth * 0.34, min(176, availableWidth)), 360)
        let maxImageHeight = min(max(readerSize.height, 0) * 0.5, 520)
        let width = min(targetWidth, maxImageHeight / aspectRatio)
        let imageHeight = (width * aspectRatio).rounded(.toNearestOrAwayFromZero)

        return SliderPreviewBubbleLayout(
            width: width.rounded(.toNearestOrAwayFromZero),
            imageHeight: imageHeight,
            rowHeight: imageHeight + 52
        )
    }
}
