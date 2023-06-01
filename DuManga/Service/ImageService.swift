import Foundation
import UIKit
import CoreGraphics
import func AVFoundation.AVMakeRect

func resizeImage(url: URL, threshold: CompressThreshold) {
    if threshold == .never {
        return
    }

    guard let image = UIImage(contentsOfFile: url.path) else { return }
    let screenRect = AVMakeRect(aspectRatio: image.size, insideRect: UIScreen.main.bounds)
    let imagePixels = image.size.width * image.scale * image.size.height * image.scale
    let screenPixels = screenRect.size.width * UIScreen.main.scale * screenRect.size.height * UIScreen.main.scale

    let drawSize = CGSize(
        width: screenRect.size.width * Double(threshold.rawValue),
        height: screenRect.size.height * Double(threshold.rawValue)
    )

    if imagePixels > screenPixels * Double(threshold.rawValue) {
        let renderer = UIGraphicsImageRenderer(size: drawSize)
        let data = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: drawSize))
        }.jpegData(compressionQuality: 0.8)
        try? data?.write(to: url)
    }
}
