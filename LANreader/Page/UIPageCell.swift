import Combine
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging
import ImageIO

class UIPageCell: UICollectionViewCell {
    static let reuseIdentifier = "UIPageCell"

    var store: StoreOf<PageFeature>?

    private let logger = Logger(label: "UIPageCell")

    private var cancellables: Set<AnyCancellable> = []

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.minimumZoomScale = 1.0
        view.maximumZoomScale = 3.0
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.progressTintColor = .label
        return view
    }()

    private let progressViewLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .natural
        label.textColor = .label
        return label
    }()

    private func cancelSubscriptions() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)
        contentView.addSubview(progressView)
        contentView.addSubview(progressViewLabel)

        scrollView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressViewLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            progressView.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(
                equalTo: contentView.widthAnchor, multiplier: 0.9),

            progressViewLabel.leadingAnchor.constraint(
                equalTo: progressView.leadingAnchor),
            progressViewLabel.topAnchor.constraint(
                equalTo: progressView.bottomAnchor, constant: 8)
        ])
    }

    func configure(with store: StoreOf<PageFeature>) {
        // Tear down any existing observation from a previous page assignment
        cancelSubscriptions()
        self.store = store
        imageView.stopAnimating()
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        setupObserve(store: store)
    }

    // swiftlint:disable function_body_length
    func setupObserve(store: StoreOf<PageFeature>) {
        store.publisher.progress
            .sink { [weak self] _ in
                guard let self else { return }
                // Ensure the cell is still showing this store (may have been reused)
                guard self.store === store else { return }
                guard !store.imageLoaded else { return }

                imageView.isHidden = true
                progressView.isHidden = false
                progressViewLabel.isHidden = false
                progressView.progress = Float(store.progress)
                progressViewLabel.text = store.progress > 1 ? String(localized: "translating") : String(
                    format: "%.2f%%", store.progress * 100)
            }
            .store(in: &cancellables)

        store.publisher.translationStatus
            .sink { [weak self] status in
                guard let self else { return }
                guard self.store === store else { return }
                guard !status.isEmpty else { return }

                progressViewLabel.text = status
            }
            .store(in: &cancellables)

        store.publisher.imageLoaded
            .sink { [weak self] loaded in
                guard let self else { return }
                guard self.store === store else { return }
                guard loaded else { return }

                if store.errorMessage.isEmpty {
                    imageView.isHidden = false
                    progressView.isHidden = true
                    progressViewLabel.isHidden = true
                    let contentPath = {
                        switch store.pageMode {
                        case .left:
                            return store.pathLeft
                        case .right:
                            return store.pathRight
                        default:
                            return store.path
                        }
                    }()
                    let selectedPath = resolvedContentPath(store: store, basePath: contentPath)
                    if let path = selectedPath,
                        let uiImage = loadImage(path: path) {
                        imageView.image = uiImage
                        if path.pathExtension.lowercased() == "gif" {
                            imageView.startAnimating()
                        } else {
                            imageView.stopAnimating()
                        }
                    } else {
                        imageView.stopAnimating()
                        imageView.image = UIImage(systemName: "rectangle.slash")
                    }
                } else {
                    progressView.isHidden = true
                    progressViewLabel.text = store.errorMessage
                }
            }
            .store(in: &cancellables)
    }
    // swiftlint:enable function_body_length

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelSubscriptions()
        store = nil
        imageView.stopAnimating()
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let image = imageView.image {
            let width = layoutAttributes.frame.width
            let height = width * (image.size.height / image.size.width)
            attributes.frame.size.height = height
        }
        return attributes
    }

    private func resolvedContentPath(store: StoreOf<PageFeature>, basePath: URL?) -> URL? {
        if let basePath,
            FileManager.default.fileExists(atPath: basePath.path(percentEncoded: false)) {
            return basePath
        }
        if store.pageMode == .normal,
            let gifPath = store.gifPath,
            FileManager.default.fileExists(atPath: gifPath.path(percentEncoded: false)) {
            return gifPath
        }
        return basePath
    }

    private func loadImage(path: URL) -> UIImage? {
        if path.pathExtension.lowercased() == "gif" {
            return UIImage.animatedGif(path: path)
        }
        return UIImage(contentsOfFile: path.path(percentEncoded: false))
    }
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

private extension UIImage {
    static func animatedGif(path: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(path as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        if count == 1, let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: cgImage)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration: Double = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += gifFrameDuration(source: source, at: index)
        }

        guard !frames.isEmpty else { return nil }
        if duration <= 0 {
            duration = Double(frames.count) * 0.1
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    static func gifFrameDuration(source: CGImageSource, at index: Int) -> Double {
        let defaultDelay = 0.1
        guard let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any],
            let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return defaultDelay }

        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? defaultDelay

        // Some GIFs set tiny delays that cause excessive CPU usage and stutter.
        return delay < 0.02 ? defaultDelay : delay
    }
}
