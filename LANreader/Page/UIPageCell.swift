import Combine
import ComposableArchitecture
import AnimatedImage
import SwiftUI
import UIKit
import Logging
import ImageIO

private final class PreviewAwareAnimatedImageView: AnimatedImageView {
    var onFirstFrameRendered: (() -> Void)?
    private var hasRenderedFirstFrame = false

    func resetFirstFrameState() {
        hasRenderedFirstFrame = false
    }

    override func updateContents(for targetTimestamp: TimeInterval) {
        super.updateContents(for: targetTimestamp)

        guard !hasRenderedFirstFrame, layer.contents != nil else { return }
        hasRenderedFirstFrame = true
        onFirstFrameRendered?()
    }
}

class UIPageCell: UICollectionViewCell {
    static let reuseIdentifier = "UIPageCell"

    var store: StoreOf<PageFeature>?

    private let logger = Logger(label: "UIPageCell")
    private let imageService = ImageService.shared
    private static let animatedImageMemoryLimitMB: Double = 128
    private static let animatedImageConfiguration: AnimatedImage.Configuration = {
        var config = AnimatedImage.Configuration.unlimited
        config.maxMemoryUsage = .init(value: animatedImageMemoryLimitMB, unit: .megabytes)
        config.maxLevelOfIntegrity = 1
        config.interpolationQuality = .high
        return config
    }()

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

    private let animatedImageView: PreviewAwareAnimatedImageView = {
        let view = PreviewAwareAnimatedImageView(frame: .zero)
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
        animatedImageView.onFirstFrameRendered = { [weak self] in
            DispatchQueue.main.async {
                self?.imageView.isHidden = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)
        scrollView.addSubview(animatedImageView)
        contentView.addSubview(progressView)
        contentView.addSubview(progressViewLabel)

        scrollView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        animatedImageView.translatesAutoresizingMaskIntoConstraints = false
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

            animatedImageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            animatedImageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            animatedImageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            animatedImageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            animatedImageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            animatedImageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

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
        animatedImageView.resetFirstFrameState()
        self.store = store
        imageView.image = nil
        imageView.isHidden = true
        animatedImageView.image = nil
        animatedImageView.isHidden = true
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        setupObserve(store: store)
        renderCurrentState(store: store)
    }

    func setupObserve(store: StoreOf<PageFeature>) {
        store.publisher.progress
            .sink { [weak self] _ in
                guard let self else { return }
                // Ensure the cell is still showing this store (may have been reused)
                guard self.store === store else { return }
                guard !store.imageLoaded else { return }

                imageView.isHidden = true
                animatedImageView.isHidden = true
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
                    progressView.isHidden = true
                    progressViewLabel.isHidden = true
                    renderImage(store: store)
                } else {
                    imageView.isHidden = true
                    animatedImageView.isHidden = true
                    progressView.isHidden = true
                    progressViewLabel.text = store.errorMessage
                }
            }
            .store(in: &cancellables)
    }

    // swiftlint:disable function_body_length
    private func renderImage(store: StoreOf<PageFeature>) {
        animatedImageView.resetFirstFrameState()

        let pageName: String = {
            switch store.pageMode {
            case .left:
                return "\(store.pageNumber)-left"
            case .right:
                return "\(store.pageNumber)-right"
            default:
                return "\(store.pageNumber)"
            }
        }()

        guard let contentPath = imageService.storedImagePath(
            folderUrl: store.folder,
            pageNumber: pageName
        ) else {
            imageView.image = UIImage(systemName: "rectangle.slash")
            imageView.isHidden = false
            animatedImageView.image = nil
            animatedImageView.isHidden = true
            return
        }

        if imageService.isAnimatedImage(imageUrl: contentPath) {
            do {
                if let previewImage = previewImage(at: contentPath) {
                    imageView.image = previewImage
                } else {
                    imageView.image = UIImage(systemName: "rectangle.slash")
                }
                imageView.isHidden = false

                let image = try AnimatedImage(
                    contentsOf: contentPath,
                    withConfiguration: Self.animatedImageConfiguration
                )
                animatedImageView.image = image
                animatedImageView.isHidden = false
            } catch {
                logger.error("failed to render animated image. \(error)")
                if let staticImage = previewImage(at: contentPath) {
                    imageView.image = staticImage
                } else {
                    imageView.image = UIImage(systemName: "rectangle.slash")
                }
                imageView.isHidden = false
                animatedImageView.image = nil
                animatedImageView.isHidden = true
            }
        } else {
            if let staticImage = previewImage(at: contentPath) {
                imageView.image = staticImage
            } else {
                imageView.image = UIImage(systemName: "rectangle.slash")
            }
            imageView.isHidden = false
            animatedImageView.image = nil
            animatedImageView.isHidden = true
        }
    }
    // swiftlint:enable function_body_length

    private func renderCurrentState(store: StoreOf<PageFeature>) {
        if store.errorMessage.isEmpty {
            if store.imageLoaded {
                progressView.isHidden = true
                progressViewLabel.isHidden = true
                renderImage(store: store)
            } else {
                imageView.isHidden = true
                animatedImageView.isHidden = true
                progressView.isHidden = false
                progressViewLabel.isHidden = false
                progressView.progress = Float(store.progress)
                progressViewLabel.text = store.translationStatus.isEmpty ?
                String(format: "%.2f%%", store.progress * 100) :
                store.translationStatus
            }
        } else {
            imageView.isHidden = true
            animatedImageView.isHidden = true
            progressView.isHidden = true
            progressViewLabel.isHidden = false
            progressViewLabel.text = store.errorMessage
        }
    }

    private func previewImage(at url: URL) -> UIImage? {
        if let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            return image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelSubscriptions()
        animatedImageView.resetFirstFrameState()
        store = nil
        imageView.image = nil
        imageView.isHidden = true
        animatedImageView.image = nil
        animatedImageView.isHidden = true
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
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return animatedImageView.isHidden ? imageView : animatedImageView
    }
}
