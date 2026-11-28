import UIKit

struct ReaderPullNavigationContext {
    let pageCount: Int
    let currentPageIndex: Int
    let readDirection: ReadDirection
    let doublePageLayout: Bool
    let spreadPairingOffset: Int
    let atFirstArchive: Bool
    let atLastArchive: Bool
}

@MainActor
final class ReaderPullNavigationOverlay {
    enum Edge: Equatable {
        case previous
        case next
    }

    private struct ScrollMetrics {
        let offset: CGFloat
        let maxOffset: CGFloat
        let axis: NSLayoutConstraint.Axis
    }

    private struct CardPlacement {
        let edge: Edge
        let axis: NSLayoutConstraint.Axis
        let isRTLReading: Bool
        let cardSize: CGSize
        let edgeInset: CGFloat
    }

    private let pullThreshold: CGFloat = 80
    private var pullEdge: Edge?
    private var pullProgress: CGFloat = 0 // 0..1
    private var pullActive = false
    private let pullIndicatorContainer = UIView()
    private let pullArrowView = UIImageView()
    private let pullStatusLabel = UILabel()
    private let pullProgressView = UIProgressView(progressViewStyle: .default)
    private let pullStatusBackground = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterial)
    )
    private var lastReportedProgressBucket = -1 // for throttled updates
    private var pullThresholdCrossedHapticsFired = false

    func install(in hostView: UIView) {
        pullStatusBackground.isHidden = true
        pullStatusBackground.clipsToBounds = true
        pullStatusBackground.layer.cornerRadius = 24
        pullStatusBackground.layer.cornerCurve = .continuous
        pullStatusBackground.layer.borderWidth = 1
        pullStatusBackground.layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor
        hostView.addSubview(pullStatusBackground)

        pullIndicatorContainer.clipsToBounds = true
        pullIndicatorContainer.layer.cornerRadius = 18
        pullIndicatorContainer.layer.cornerCurve = .continuous
        pullIndicatorContainer.backgroundColor = UIColor.secondarySystemFill
        pullStatusBackground.contentView.addSubview(pullIndicatorContainer)

        pullArrowView.contentMode = .scaleAspectFit
        pullArrowView.tintColor = .secondaryLabel
        pullArrowView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        pullIndicatorContainer.addSubview(pullArrowView)

        pullStatusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        pullStatusLabel.adjustsFontForContentSizeCategory = true
        pullStatusLabel.textColor = .label
        pullStatusLabel.textAlignment = .natural
        pullStatusLabel.numberOfLines = 1
        pullStatusLabel.isHidden = true
        pullStatusBackground.contentView.addSubview(pullStatusLabel)

        pullProgressView.trackTintColor = UIColor.separator.withAlphaComponent(0.14)
        pullProgressView.progressTintColor = .systemBlue
        pullProgressView.layer.cornerRadius = 1.5
        pullProgressView.clipsToBounds = true
        pullStatusBackground.contentView.addSubview(pullProgressView)
    }

    func update(for scrollView: UIScrollView, in hostView: UIView, context: ReaderPullNavigationContext) {
        let metrics = scrollMetrics(for: scrollView, readDirection: context.readDirection)
        let atFirst = isAtFirstVisualPage(in: scrollView, context: context)
        let atLast = isAtLastVisualPage(in: scrollView, context: context)
        guard atFirst || atLast else {
            endInteraction()
            return
        }

        let offset = metrics.offset
        let maxOffset = metrics.maxOffset
        let overscroll: CGFloat
        if offset < 0 && atFirst {
            overscroll = -offset
            pullEdge = .previous
        } else if offset > maxOffset && atLast {
            overscroll = offset - maxOffset
            pullEdge = .next
        } else {
            endInteraction()
            return
        }

        pullActive = overscroll > 0
        pullProgress = min(1, overscroll / pullThreshold)
        // Throttle UI updates to avoid excessive layout work (bucket by 5%)
        let bucket = Int(pullProgress * 20) // 0..20
        guard bucket != lastReportedProgressBucket else { return }
        lastReportedProgressBucket = bucket
        updatePullViews(overscroll: overscroll, axis: metrics.axis, in: hostView, context: context)
    }

    func completeInteraction(context: ReaderPullNavigationContext) -> Edge? {
        defer { endInteraction() }
        guard pullActive && pullProgress >= 1, let edge = pullEdge else { return nil }
        let atArchiveBoundary = (edge == .previous && context.atFirstArchive)
            || (edge == .next && context.atLastArchive)
        return atArchiveBoundary ? nil : edge
    }

    static func symbolName(
        for edge: Edge,
        axis: NSLayoutConstraint.Axis,
        isRTLReading: Bool,
        flipped: Bool
    ) -> String {
        if axis == .horizontal {
            if isRTLReading {
                switch edge {
                case .previous: return flipped ? "arrow.right" : "arrow.left"
                case .next:     return flipped ? "arrow.left"  : "arrow.right"
                }
            } else {
                switch edge {
                case .previous: return flipped ? "arrow.left" : "arrow.right"
                case .next:     return flipped ? "arrow.right" : "arrow.left"
                }
            }
        } else {
            switch edge {
            case .previous: return flipped ? "arrow.up" : "arrow.down"
            case .next:     return flipped ? "arrow.down" : "arrow.up"
            }
        }
    }

    private func isAtFirstVisualPage(
        in scrollView: UIScrollView,
        context: ReaderPullNavigationContext
    ) -> Bool {
        guard context.pageCount > 0 else { return true }
        if context.readDirection == .upDown {
            // For vertical reading rely on scroll position for accuracy; allow small epsilon
            return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
        }

        return context.currentPageIndex <= ReaderPositioning.firstVisualPageIndex(
            pageCount: context.pageCount,
            readDirection: context.readDirection,
            doublePageLayout: context.doublePageLayout,
            spreadOffset: context.spreadPairingOffset
        )
    }

    private func isAtLastVisualPage(
        in scrollView: UIScrollView,
        context: ReaderPullNavigationContext
    ) -> Bool {
        guard context.pageCount > 0 else { return true }
        let lastIndex = context.pageCount - 1
        if context.readDirection == .upDown {
            // Check if we've scrolled to (or beyond) bottom
            let maxOffset = max(
                0,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            return scrollView.contentOffset.y >= maxOffset - 1
        }

        return context.currentPageIndex >= lastIndex
    }

    private func scrollMetrics(for scrollView: UIScrollView, readDirection: ReadDirection) -> ScrollMetrics {
        let axis: NSLayoutConstraint.Axis = readDirection == .upDown ? .vertical : .horizontal
        if axis == .horizontal {
            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            return ScrollMetrics(offset: scrollView.contentOffset.x, maxOffset: maxOffset, axis: axis)
        } else {
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            return ScrollMetrics(offset: scrollView.contentOffset.y, maxOffset: maxOffset, axis: axis)
        }
    }

    private func layoutPullIndicator(
        overscroll: CGFloat,
        axis: NSLayoutConstraint.Axis,
        in hostView: UIView,
        isRTLReading: Bool
    ) {
        guard let edge = pullEdge else { return }
        let iconSize: CGFloat = 36
        let cardHeight: CGFloat = 52
        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 10
        let cardWidth = pullCardWidth(
            in: hostView,
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            spacing: spacing
        )
        let progress = min(1, overscroll / pullThreshold)
        let edgeInset = 16 + progress * 14
        let cardFrame = pullCardFrame(
            CardPlacement(
                edge: edge,
                axis: axis,
                isRTLReading: isRTLReading,
                cardSize: CGSize(width: cardWidth, height: cardHeight),
                edgeInset: edgeInset
            ),
            in: hostView
        )
        pullStatusBackground.bounds = CGRect(origin: .zero, size: cardFrame.size)
        pullStatusBackground.center = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        pullStatusBackground.layer.cornerRadius = cardHeight / 2
        layoutPullCardContent(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            spacing: spacing
        )
    }

    private func pullCardWidth(
        in hostView: UIView,
        iconSize: CGFloat,
        horizontalPadding: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let maxWidth = max(min(hostView.bounds.width - 32, 360), 0)
        pullStatusLabel.sizeToFit()
        let labelAvailableWidth = max(maxWidth - iconSize - spacing - horizontalPadding * 2, 0)
        let labelWidth = min(
            labelAvailableWidth,
            pullStatusLabel.bounds.width
        )
        let minimumWidth = min(172, maxWidth)
        return min(maxWidth, max(minimumWidth, iconSize + spacing + labelWidth + horizontalPadding * 2))
    }

    private func pullCardFrame(_ placement: CardPlacement, in hostView: UIView) -> CGRect {
        let cardWidth = placement.cardSize.width
        let cardHeight = placement.cardSize.height
        if placement.axis == .horizontal {
            let showOnLeft = (placement.edge == .previous && !placement.isRTLReading)
                || (placement.edge == .next && placement.isRTLReading)
            let xPosition = showOnLeft ? placement.edgeInset : hostView.bounds.width - cardWidth - placement.edgeInset
            return CGRect(
                x: xPosition,
                y: hostView.bounds.midY - cardHeight / 2,
                width: cardWidth,
                height: cardHeight
            )
        }

        let safeArea = hostView.safeAreaInsets
        let yPosition = placement.edge == .previous
            ? safeArea.top + placement.edgeInset
            : hostView.bounds.height - safeArea.bottom - cardHeight - placement.edgeInset
        return CGRect(x: (hostView.bounds.width - cardWidth) / 2, y: yPosition, width: cardWidth, height: cardHeight)
    }

    private func layoutPullCardContent(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        iconSize: CGFloat,
        horizontalPadding: CGFloat,
        spacing: CGFloat
    ) {
        pullIndicatorContainer.frame = CGRect(
            x: horizontalPadding,
            y: (cardHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        pullArrowView.frame = pullIndicatorContainer.bounds.insetBy(dx: 8, dy: 8)
        let labelX = horizontalPadding + iconSize + spacing
        pullStatusLabel.frame = CGRect(
            x: labelX,
            y: (cardHeight - pullStatusLabel.font.lineHeight) / 2 - 1,
            width: cardWidth - labelX - horizontalPadding,
            height: pullStatusLabel.font.lineHeight + 2
        )
        pullProgressView.frame = CGRect(
            x: horizontalPadding + 2,
            y: cardHeight - 5,
            width: cardWidth - (horizontalPadding + 2) * 2,
            height: 3
        )
    }

    private func updatePullViews(
        overscroll: CGFloat,
        axis: NSLayoutConstraint.Axis,
        in hostView: UIView,
        context: ReaderPullNavigationContext
    ) {
        guard pullActive, let edge = pullEdge else { return }
        pullIndicatorContainer.isHidden = false
        pullStatusBackground.isHidden = false
        pullStatusLabel.isHidden = false
        let atArchiveBoundary = (edge == .previous && context.atFirstArchive)
            || (edge == .next && context.atLastArchive)
        let flipped = !atArchiveBoundary && pullProgress >= 1
        let isRTLReading = context.readDirection == .rightLeft
        pullArrowView.image = UIImage(
            systemName: Self.symbolName(for: edge, axis: axis, isRTLReading: isRTLReading, flipped: flipped)
        )

        if atArchiveBoundary {
            pullStatusLabel.text = edge == .previous
                ? String(localized: "archive.read.first")
                : String(localized: "archive.read.last")
        } else if flipped {
            pullStatusLabel.text = String(localized: "archive.read.load")
        } else {
            pullStatusLabel.text = edge == .previous
                ? String(localized: "archive.read.previous")
                : String(localized: "archive.read.next")
        }
        layoutPullIndicator(overscroll: overscroll, axis: axis, in: hostView, isRTLReading: isRTLReading)
        updatePullStyle(atArchiveBoundary: atArchiveBoundary, releaseReady: flipped)
        if flipped && !pullThresholdCrossedHapticsFired {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            pullThresholdCrossedHapticsFired = true
        } else if !flipped {
            pullThresholdCrossedHapticsFired = false
        }
        let alpha = min(1, 0.3 + pullProgress * 0.7)
        pullArrowView.alpha = alpha
        pullStatusLabel.alpha = alpha
        pullStatusBackground.alpha = alpha
        pullStatusBackground.transform = CGAffineTransform(
            scaleX: 0.96 + pullProgress * 0.04,
            y: 0.96 + pullProgress * 0.04
        )
    }

    private func updatePullStyle(atArchiveBoundary: Bool, releaseReady: Bool) {
        let tintColor: UIColor = if atArchiveBoundary {
            .tertiaryLabel
        } else if releaseReady {
            .systemBlue
        } else {
            .secondaryLabel
        }
        pullArrowView.tintColor = tintColor
        pullStatusLabel.textColor = atArchiveBoundary ? .secondaryLabel : .label
        pullIndicatorContainer.backgroundColor = tintColor.withAlphaComponent(releaseReady ? 0.18 : 0.10)
        pullStatusBackground.layer.borderColor = tintColor.withAlphaComponent(releaseReady ? 0.34 : 0.14).cgColor
        pullProgressView.progressTintColor = tintColor
        pullProgressView.setProgress(Float(pullProgress), animated: false)
    }

    private func endInteraction() {
        pullActive = false
        pullEdge = nil
        pullProgress = 0
        lastReportedProgressBucket = -1
        pullIndicatorContainer.isHidden = true
        pullStatusLabel.isHidden = true
        pullStatusBackground.isHidden = true
        pullStatusBackground.transform = .identity
        pullProgressView.setProgress(0, animated: false)
        pullThresholdCrossedHapticsFired = false
    }
}
